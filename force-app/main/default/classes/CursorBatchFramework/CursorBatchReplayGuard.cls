/**
 * @description Decides which Platform Events a CursorBatch subscriber is allowed to act on.
 *
 *              Platform Event delivery is at-least-once, and on 2026-08-24 the event bus rewound
 *              the committed subscriber offset for CursorBatch_Worker__e and re-delivered roughly
 *              51,000 already-acknowledged events, some 103 hours old. The handlers enqueued work
 *              on every delivery without asking whether they had seen the event before, so the
 *              redelivery executed real business logic a second time. This class is the guard that
 *              was missing: handlers call admit() once per subscriber batch and act only on the
 *              events it returns.
 *
 *              Three layers:
 *
 *              1. Job state. An event whose job record is gone, or already terminal, can never be
 *                 a legitimate dispatch. One non-locking SOQL per batch. Every event in the
 *                 incident belonged to a job that had already completed, so this layer alone
 *                 would have contained it. Applied only by callers that enable it; see
 *                 withTerminalJobGate.
 *              2. Staleness. An event older than Max_Event_Age_Minutes__c is rejected. Costs
 *                 nothing -- the event carries its own CreatedDate -- and on its own it would
 *                 have absorbed almost the entire 2026-08-24 replay, since the bulk of the
 *                 redelivered events were hours to days old. See withStalenessGate.
 *              3. Exactly-once. Insert a CursorBatch_Event_Ledger__c row keyed on the event's
 *                 identity; a DUPLICATE_VALUE means this exact event was already processed. This
 *                 is the layer that covers the in-flight window the first two cannot, and it is
 *                 why the ledger must outlive the job record.
 *
 *              The layers are independent on purpose. Any one of them stops a replay, so a
 *              widened age threshold or a purged ledger does not leave the subscriber defenceless.
 *
 *              There is no switch that turns the guard off. Only the staleness layer can reject a
 *              legitimate event, because an age threshold is a judgment call, and a job with
 *              unpredictable delivery timing narrows exactly that one check by setting
 *              Max_Event_Age_Minutes__c to AGE_GATE_DISABLED. The other two layers cannot be
 *              wrong by construction, so there is nothing to opt out of -- and an opt-out that
 *              covered all three would recreate the unguarded state this class exists to prevent.
 * @group CursorBatchFramework
 * @see CursorBatchWorkerTriggerHandler
 * @see CursorBatchCoordinatorTriggerHandler
 * @see CursorBatchCompletionHandler
 * @see CursorBatchLedgerCleanup
 */
public without sharing class CursorBatchReplayGuard {

    // ============== Channels ==============

    public static final String CHANNEL_WORKER = 'Worker';
    public static final String CHANNEL_COORDINATOR = 'Coordinator';
    public static final String CHANNEL_WORKER_COMPLETE = 'WorkerComplete';

    // ============== Rejection reasons ==============

    public static final String REASON_STALE = 'STALE';
    public static final String REASON_JOB_MISSING = 'JOB_MISSING';
    public static final String REASON_JOB_TERMINAL = 'JOB_TERMINAL';
    public static final String REASON_DUPLICATE = 'DUPLICATE';

    /**
     * @description Age beyond which an event is treated as stale when a job does not set
     *              Max_Event_Age_Minutes__c. Worker events are normally delivered within seconds;
     *              an hour is loose enough to survive a genuine delivery backlog and still tight
     *              enough to reject a replay of anything but the most recent minutes.
     */
    public static final Integer DEFAULT_MAX_EVENT_AGE_MINUTES = 60;

    /**
     * @description Sentinel for Max_Event_Age_Minutes__c that turns the staleness layer off for a
     *              job.
     *
     *              This is the guard's only opt-out, and deliberately the narrowest one. Staleness
     *              is the sole layer that can reject a legitimate event, because an age threshold
     *              is a judgment call; the job-state and exactly-once layers cannot be wrong by
     *              construction -- an event for a job that is gone or already terminal is never
     *              legitimate, and a key collision means literally the same event. So a job whose
     *              delivery timing is unpredictable disables this one check and keeps the two that
     *              are exact. There is deliberately no switch that turns the whole guard off: a
     *              guard that can be disabled is not a guarantee, and "disabled and forgotten" is
     *              the state the framework was already in when the 2026-08-24 replay arrived.
     */
    public static final Integer AGE_GATE_DISABLED = -1;

    /** Statuses from which no further dispatch is ever legitimate. */
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Completed', 'Completed with Errors', 'Failed', 'Cancelled'
    };

    /** Blocked keys sampled into the summary entry before it reports a bare count. */
    private static final Integer BLOCKED_SAMPLE_LIMIT = 5;

    /** Event_Key__c is Text(255); anything longer is stored as a digest instead. */
    private static final Integer EVENT_KEY_MAX_LENGTH = 255;

    private final String channel;
    private final ICursorBatchLogger logger;
    private Boolean terminalJobGate = false;
    private Boolean stalenessGate = true;

    /**
     * @description Overrides "now" so the staleness layer can be tested without waiting.
     */
    @TestVisible
    private static Datetime nowOverride;

    /**
     * @description Forces the ledger insert to throw, so the fail-open path can be tested without
     *              breaking the object.
     */
    @TestVisible
    private static Boolean simulateLedgerWriteFailure = false;

    /**
     * @description One event's identity and the context the guard needs to judge it. Handlers
     *              build these from their own event type so the guard stays channel-agnostic.
     */
    public class Candidate {
        public String eventKey;
        public Id jobRecordId;
        public String jobName;
        public Datetime publishedAt;
        public String replayId;
        public String cursorQueryId;
        public Integer workerNumber;

        /**
         * @description Constructs a candidate.
         * @param eventKey Deterministic identity, from one of the build*Key helpers
         * @param jobRecordId Job record the event targets; may be null
         * @param jobName Job name carried on the event, used for config lookup; may be null
         * @param publishedAt The event's own CreatedDate
         */
        public Candidate(String eventKey, Id jobRecordId, String jobName, Datetime publishedAt) {
            this.eventKey = eventKey;
            this.jobRecordId = jobRecordId;
            this.jobName = jobName;
            this.publishedAt = publishedAt;
        }
    }

    /**
     * @description The guard's answer for one subscriber batch.
     */
    public class Verdict {
        /** Keys admitted by this batch. Read for assertions; use claim() to dispatch. */
        public Set<String> admittedKeys = new Set<String>();
        /** Blocked keys mapped to the reason, so callers can reconcile per-event. */
        public Map<String, String> blockedReasonsByKey = new Map<String, String>();

        private Set<String> unclaimedKeys;

        private Verdict() {
            this.unclaimedKeys = new Set<String>();
        }

        /**
         * @description Claims the single admission for one event, consuming it.
         *
         *              Deliberately one-shot rather than a plain set lookup. A subscriber batch
         *              can contain the same event twice -- that is the ordinary shape of a
         *              redelivery burst -- and a caller iterating events would otherwise ask
         *              about the same key twice and get true both times, dispatching the work
         *              twice. Consuming the admission makes the second ask false, so the number
         *              of dispatches can never exceed the number of ledger rows written.
         * @param eventKey Key from the corresponding Candidate
         * @return true exactly once per admitted key, false for every later call and for any key
         *         that was blocked
         */
        public Boolean claim(String eventKey) {
            return String.isNotBlank(eventKey) && unclaimedKeys.remove(eventKey);
        }

        private void admit(String eventKey) {
            admittedKeys.add(eventKey);
            unclaimedKeys.add(eventKey);
        }
    }

    /**
     * @description Constructs a guard for one channel.
     * @param channel One of CHANNEL_WORKER, CHANNEL_COORDINATOR, CHANNEL_WORKER_COMPLETE
     * @param logger Logger for the aggregated summary entry
     */
    public CursorBatchReplayGuard(String channel, ICursorBatchLogger logger) {
        this.channel = channel;
        this.logger = logger != null ? logger : CursorBatchLogger.getDefault();
    }

    /**
     * @description Enables or disables the job-state layer.
     *
     *              The two dispatch channels enable it: a worker or coordinator event for a job
     *              that has already reached a terminal status is never legitimate.
     *
     *              The completion channel must not. Delivery order across batches is not
     *              guaranteed, so a non-final page event can legitimately arrive after the last
     *              worker's final event has already pushed the job terminal. Rejecting it would
     *              lose a Completed_Batches__c increment, and the duplicate finish() it might
     *              otherwise cause is already prevented by the completion transition check in
     *              CursorBatchCompletionHandler.
     * @param enabled true to reject events whose job is missing or terminal
     * @return This guard, for chaining
     */
    public CursorBatchReplayGuard withTerminalJobGate(Boolean enabled) {
        this.terminalJobGate = enabled == true;
        return this;
    }

    /**
     * @description Enables or disables the staleness layer. On by default.
     *
     *              The completion channel turns it off. A completion event is a report, not a
     *              dispatch: blocking one does not prevent work, it discards the record that work
     *              already happened. Worse, it is the one rejection a caller cannot reconcile --
     *              the dispatch channels can report a rejected shard as failed, but there is
     *              nothing to report when the report itself is what got dropped, so the job
     *              simply never reaches its terminal status. Replay protection on that channel
     *              comes from the ledger instead, which is exact rather than heuristic and whose
     *              retention already exceeds the observed replay horizon.
     * @param enabled true to reject events older than Max_Event_Age_Minutes__c
     * @return This guard, for chaining
     */
    public CursorBatchReplayGuard withStalenessGate(Boolean enabled) {
        this.stalenessGate = enabled == true;
        return this;
    }

    /**
     * @description Runs all enabled layers over one subscriber batch and records a ledger row for
     *              every admitted event. Callers must invoke this before enqueueing anything: the
     *              ledger insert and the subsequent System.enqueueJob share the trigger
     *              transaction, so if the transaction rolls back the marker rolls back with it and
     *              the events stay eligible for a genuine retry.
     * @param candidates Normalized events from this batch
     * @return Verdict naming the admitted keys and the reason each other key was blocked
     */
    public Verdict admit(List<Candidate> candidates) {
        Verdict verdict = new Verdict();
        if (candidates == null || candidates.isEmpty()) {
            return verdict;
        }

        // Reasons are collected and reported as one entry after all layers have run. A logging
        // adapter that persists entries costs DML per entry, and a redelivery arrives by the
        // thousand: per-event logging would reproduce the amplification that turned the
        // 2026-08-24 replay into an org-wide publish-allocation breach.
        Map<String, List<Candidate>> blockedByReason = new Map<String, List<Candidate>>();

        Map<Id, CursorBatch_Job__c> jobsById = terminalJobGate
            ? CursorBatchSelector.getJobStatesByIds(collectJobIds(candidates))
            : new Map<Id, CursorBatch_Job__c>();

        Datetime evaluatedAt = nowOverride != null ? nowOverride : System.now();
        Set<String> seenInThisBatch = new Set<String>();
        List<Candidate> ledgerCandidates = new List<Candidate>();

        for (Candidate candidate : candidates) {
            if (String.isBlank(candidate?.eventKey)) {
                // Nothing to key on, so nothing can be proven about it. Admitting is the lesser
                // evil: the alternative silently drops work the framework itself published.
                continue;
            }

            String effectiveJobName = resolveJobName(candidate, jobsById);
            String reason = evaluateCheapLayers(candidate, jobsById, effectiveJobName, evaluatedAt);

            if (reason == null && !seenInThisBatch.add(candidate.eventKey)) {
                // A duplicate inside one batch never reaches the unique index, because the second
                // row is never built.
                reason = REASON_DUPLICATE;
            }

            if (reason != null) {
                record(blockedByReason, reason, candidate);
                verdict.blockedReasonsByKey.put(candidate.eventKey, reason);
                continue;
            }

            ledgerCandidates.add(candidate);
        }

        applyLedgerLayer(ledgerCandidates, verdict, blockedByReason);
        reportBlocked(blockedByReason);
        return verdict;
    }

    /**
     * @description Runs the staleness and job-state layers over one candidate.
     * @param candidate Event under evaluation
     * @param jobsById Job records for this batch; empty when the job-state layer is disabled
     * @param jobName Resolved job name for config lookup
     * @param evaluatedAt Reference time for the age comparison
     * @return Rejection reason, or null when the candidate survives both layers
     */
    private String evaluateCheapLayers(
        Candidate candidate,
        Map<Id, CursorBatch_Job__c> jobsById,
        String jobName,
        Datetime evaluatedAt
    ) {
        // Job state is tested before staleness even though staleness is the cheaper predicate.
        // The job query has already run for the whole batch, so ordering costs nothing, and it
        // buys two things. It makes REASON_STALE mean "the job is live and this shard arrived
        // late", which is the only case a caller can safely reconcile -- reconciling a shard
        // whose job is already terminal would corrupt its counters. And it keeps reconciliation
        // from amplifying: in a replay of the 2026-08-24 shape every event belongs to a job that
        // completed days ago, so they all resolve to JOB_TERMINAL and none produce follow-on work.
        if (terminalJobGate && candidate.jobRecordId != null) {
            CursorBatch_Job__c job = jobsById.get(candidate.jobRecordId);
            if (job == null) {
                return REASON_JOB_MISSING;
            }
            if (TERMINAL_STATUSES.contains(job.Status__c) || job.Completed_At__c != null) {
                return REASON_JOB_TERMINAL;
            }
        }

        if (!stalenessGate) {
            return null;
        }

        Integer maxAgeMinutes = resolveMaxEventAgeMinutes(jobName);
        // A null publishedAt means the age is unknowable, not that the event is old. Treating
        // unknown as stale would reject every event a test constructs rather than publishes.
        if (maxAgeMinutes != AGE_GATE_DISABLED && candidate.publishedAt != null) {
            Long ageMinutes = (evaluatedAt.getTime() - candidate.publishedAt.getTime()) / 60000;
            if (ageMinutes > maxAgeMinutes) {
                return REASON_STALE;
            }
        }
        return null;
    }

    /**
     * @description Writes one ledger row per surviving candidate and treats a unique-key
     *              violation as proof the event was already processed.
     *
     *              Fails open on any other DML error: the candidate is admitted and the failure
     *              logged. The staleness and job-state layers are still in force, and dropping
     *              legitimate batch work because a bookkeeping insert failed is the worse
     *              outcome. This matches the ordering the framework already uses elsewhere --
     *              job state first, markers best-effort.
     * @param ledgerCandidates Candidates that passed the cheap layers
     * @param verdict Verdict to populate
     * @param blockedByReason Accumulator for rejections, reported as one entry by the caller
     */
    private void applyLedgerLayer(
        List<Candidate> ledgerCandidates,
        Verdict verdict,
        Map<String, List<Candidate>> blockedByReason
    ) {
        if (ledgerCandidates.isEmpty()) {
            return;
        }

        List<CursorBatch_Event_Ledger__c> rows = new List<CursorBatch_Event_Ledger__c>();
        for (Candidate candidate : ledgerCandidates) {
            rows.add(new CursorBatch_Event_Ledger__c(
                Event_Key__c = candidate.eventKey,
                Channel__c = channel,
                Job_Record_Id__c = String.valueOf(candidate.jobRecordId),
                Job_Name__c = truncate(candidate.jobName, 255),
                Replay_Id__c = truncate(candidate.replayId, 255),
                Cursor_Query_Id__c = truncate(candidate.cursorQueryId, 255),
                Worker_Number__c = candidate.workerNumber,
                Event_Published_At__c = candidate.publishedAt
            ));
        }

        List<Database.SaveResult> results;
        try {
            if (simulateLedgerWriteFailure) {
                throw new CursorBatchCoordinator.CursorBatchException('Simulated ledger write failure');
            }
            results = Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            logger.logException(CursorBatchLogger.scoped(
                CursorBatchLogger.SCOPE_EVENT_REPLAY_BLOCKED,
                'Channel ' + channel + ': ledger write failed for ' + rows.size() +
                    ' event(s); admitting them and relying on the staleness and job-state layers'
            ), e);
            admitAll(ledgerCandidates, verdict);
            return;
        }

        Integer writeFailures = 0;
        String firstWriteError = null;
        for (Integer i = 0; i < results.size(); i++) {
            Candidate candidate = ledgerCandidates[i];
            if (results[i].isSuccess()) {
                verdict.admit(candidate.eventKey);
                continue;
            }

            if (isDuplicate(results[i])) {
                record(blockedByReason, REASON_DUPLICATE, candidate);
                verdict.blockedReasonsByKey.put(candidate.eventKey, REASON_DUPLICATE);
                continue;
            }

            writeFailures++;
            if (firstWriteError == null) {
                firstWriteError = describeErrors(results[i]);
            }
            verdict.admit(candidate.eventKey);
        }

        if (writeFailures > 0) {
            logger.logError(CursorBatchLogger.scoped(
                CursorBatchLogger.SCOPE_EVENT_REPLAY_BLOCKED,
                'Channel ' + channel + ': ' + writeFailures + ' ledger row(s) failed to write for a ' +
                    'reason other than duplication; those events were admitted. First error: ' + firstWriteError
            ));
        }
    }

    /**
     * @description Emits one entry describing everything blocked in this transaction, at ERROR so
     *              it survives an org whose logging threshold is WARN. During the 2026-08-24
     *              incident the dispatch path's INFO lines were suppressed by exactly that
     *              threshold, which is why diagnosis needed nine separate forensic audits.
     * @param blockedByReason Rejections, grouped by reason
     */
    private void reportBlocked(Map<String, List<Candidate>> blockedByReason) {
        if (blockedByReason.isEmpty()) {
            return;
        }

        String summary = 'Channel ' + channel + ': blocked ' + summarize(blockedByReason);
        Candidate sample = firstCandidate(blockedByReason);

        CursorBatchLogger.withScopeTags(
            logger,
            CursorBatchCompletionHandler.resolveJobTag(sample?.jobName),
            new Set<String>{ CursorBatchLogger.TAG_REPLAY_BLOCKED }
        ).logError(CursorBatchLogger.scoped(CursorBatchLogger.SCOPE_EVENT_REPLAY_BLOCKED, summary));
    }

    /**
     * @description Renders per-reason counts with a bounded sample of keys.
     * @param byReason Candidates grouped by rejection reason
     * @return Human-readable summary fragment
     */
    private String summarize(Map<String, List<Candidate>> byReason) {
        List<String> fragments = new List<String>();
        for (String reason : byReason.keySet()) {
            List<Candidate> rejected = byReason.get(reason);
            List<String> sampleKeys = new List<String>();
            for (Integer i = 0; i < Math.min(rejected.size(), BLOCKED_SAMPLE_LIMIT); i++) {
                sampleKeys.add(rejected[i].eventKey);
            }
            String fragment = rejected.size() + ' ' + reason + ' [' + String.join(sampleKeys, ', ');
            fragment += rejected.size() > sampleKeys.size()
                ? ', ...and ' + (rejected.size() - sampleKeys.size()) + ' more]'
                : ']';
            fragments.add(fragment);
        }
        return String.join(fragments, ', ');
    }

    // ============== Key composition ==============

    /**
     * @description Builds the identity of a worker event.
     *
     *              Worker events are published exactly once per worker, at fan-out; pages and
     *              retries are chained with System.enqueueJob and never republish. So the shard
     *              is the identity. Including the cursor queryId is what keeps a legitimate
     *              coordinator retry working: a retry builds a fresh cursor and therefore a fresh
     *              queryId, producing a new key, while a redelivery carries the original queryId
     *              and collides.
     * @param jobRecordId Job record the worker belongs to
     * @param cursorQueryId Cursor queryId (SOQL) or csvCursorQuery session id (CSV)
     * @param workerNumber Worker number within the fan-out
     * @return Event key, digested when it would overflow the field
     */
    public static String buildWorkerKey(Id jobRecordId, String cursorQueryId, Integer workerNumber) {
        return fitKey('W', String.valueOf(jobRecordId) + '#' + cursorQueryId + '#' + workerNumber);
    }

    /**
     * @description Builds the identity of a coordinator event. The job record is created per
     *              submission, so it identifies the run; the class component keeps the CSV_Ready
     *              and CSV_Error callbacks from colliding with the initial dispatch for the same
     *              job.
     * @param jobRecordId Job record the coordinator event targets
     * @param coordinatorClass Coordinator class name, or the CSV_Ready / CSV_Error sentinel
     * @return Event key, digested when it would overflow the field
     */
    public static String buildCoordinatorKey(Id jobRecordId, String coordinatorClass) {
        return fitKey('C', String.valueOf(jobRecordId) + '#' + coordinatorClass);
    }

    /**
     * @description Builds the identity of a worker completion event. Unlike the dispatch
     *              channels, a completion event has no job-derived identity -- a worker publishes
     *              one per page plus one final -- so the bus ReplayId is the only thing that
     *              distinguishes them. Format is unchanged from the pre-ledger
     *              CursorBatch_Processed_Event__c key so existing operational queries still read.
     * @param jobRecordId Job record the completion reports against
     * @param replayId Platform Event ReplayId
     * @return Event key, or null when either component is missing
     */
    public static String buildCompletionKey(Id jobRecordId, String replayId) {
        if (jobRecordId == null || String.isBlank(replayId)) {
            return null;
        }
        return fitKey(null, String.valueOf(jobRecordId) + '#' + replayId);
    }

    /**
     * @description Keeps a composed key inside Event_Key__c. A cursor queryId is opaque and of
     *              unbounded length, so the readable form can overflow; the digest preserves
     *              uniqueness and the components remain queryable in their own ledger fields.
     * @param prefix Channel prefix, or null for none
     * @param body Composed key body
     * @return Key guaranteed to fit the field
     */
    private static String fitKey(String prefix, String body) {
        String key = String.isBlank(prefix) ? body : prefix + '#' + body;
        if (key.length() <= EVENT_KEY_MAX_LENGTH) {
            return key;
        }
        String digest = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(body)));
        return String.isBlank(prefix) ? digest : prefix + '#' + digest;
    }

    // ============== Configuration ==============

    /**
     * @description Resolves the staleness threshold for a job.
     * @param jobName Job name (CursorBatch_Config__mdt MasterLabel)
     * @return Threshold in minutes, or AGE_GATE_DISABLED when the job opts out
     */
    @TestVisible
    private static Integer resolveMaxEventAgeMinutes(String jobName) {
        CursorBatch_Config__mdt config = safeConfig(jobName);
        Decimal configured = config?.Max_Event_Age_Minutes__c;
        if (configured == null) {
            return DEFAULT_MAX_EVENT_AGE_MINUTES;
        }
        if (configured < 0) {
            return AGE_GATE_DISABLED;
        }
        return configured.intValue();
    }

    /**
     * @description Reads job config without letting a lookup failure decide dispatch. A missing
     *              config yields the defaults, which are the protective values.
     * @param jobName Job name (CursorBatch_Config__mdt MasterLabel)
     * @return Config record, or null
     */
    private static CursorBatch_Config__mdt safeConfig(String jobName) {
        if (String.isBlank(jobName)) {
            return null;
        }
        try {
            return CursorBatchCoordinator.getConfig(jobName);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Determines which job name to look configuration up under. The event's own
     *              value is preferred, but the coordinator channel reuses Job_Name__c to carry
     *              the csvCursorQuery or an error message on CSV callbacks, so when it does not
     *              resolve to a config the job record queried for the job-state layer is used
     *              instead.
     * @param candidate Event under evaluation
     * @param jobsById Job records for this batch
     * @return Job name to resolve configuration with, possibly null
     */
    private String resolveJobName(Candidate candidate, Map<Id, CursorBatch_Job__c> jobsById) {
        if (safeConfig(candidate.jobName) != null) {
            return candidate.jobName;
        }
        CursorBatch_Job__c job = candidate.jobRecordId != null ? jobsById.get(candidate.jobRecordId) : null;
        return job != null && String.isNotBlank(job.Job_Name__c) ? job.Job_Name__c : candidate.jobName;
    }

    // ============== Helpers ==============

    private static Set<Id> collectJobIds(List<Candidate> candidates) {
        Set<Id> jobIds = new Set<Id>();
        for (Candidate candidate : candidates) {
            if (candidate?.jobRecordId != null) {
                jobIds.add(candidate.jobRecordId);
            }
        }
        return jobIds;
    }

    private static void record(Map<String, List<Candidate>> byReason, String reason, Candidate candidate) {
        if (!byReason.containsKey(reason)) {
            byReason.put(reason, new List<Candidate>());
        }
        byReason.get(reason).add(candidate);
    }

    private static void admitAll(List<Candidate> candidates, Verdict verdict) {
        for (Candidate candidate : candidates) {
            verdict.admit(candidate.eventKey);
        }
    }

    private static Candidate firstCandidate(Map<String, List<Candidate>> byReason) {
        for (String reason : byReason.keySet()) {
            List<Candidate> rejected = byReason.get(reason);
            if (!rejected.isEmpty()) {
                return rejected[0];
            }
        }
        return null;
    }

    private static Boolean isDuplicate(Database.SaveResult result) {
        for (Database.Error error : result.getErrors()) {
            if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    private static String describeErrors(Database.SaveResult result) {
        List<String> messages = new List<String>();
        for (Database.Error error : result.getErrors()) {
            messages.add(error.getStatusCode() + ': ' + error.getMessage());
        }
        return String.join(messages, ' | ');
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > maxLength ? value.left(maxLength) : value;
    }
}
