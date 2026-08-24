/**
 * @description Unit tests for CursorBatchReplayGuard.
 *
 *              The guard cannot be exercised end-to-end through a Platform Event trigger, because
 *              ReplayId and CreatedDate are not writable on a constructed event and are not
 *              controllable on a published one. So the layers are tested here against Candidates
 *              built directly, and the trigger handlers' own tests cover the wiring.
 * @group CursorBatchFramework
 * @see CursorBatchReplayGuard
 */
@IsTest
private without sharing class CursorBatchReplayGuardTest {

    private static final String QUERY_ID = 'TestCursorQueryId';

    // =====================================================================================
    // Layer 1 -- staleness
    // =====================================================================================

    @IsTest
    static void staleEventIsBlocked() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        candidate.publishedAt = System.now().addHours(-3);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'An event older than the default 60-minute threshold must not be dispatched.');
        Assert.areEqual(CursorBatchReplayGuard.REASON_STALE,
            verdict.blockedReasonsByKey.get(candidate.eventKey),
            'The rejection must be attributed to staleness.');
    }

    @IsTest
    static void freshEventIsAdmittedAndLedgered() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey), 'A just-published event must be admitted.');
        List<CursorBatch_Event_Ledger__c> ledger = [
            SELECT Event_Key__c, Channel__c, Job_Record_Id__c, Worker_Number__c, Cursor_Query_Id__c
            FROM CursorBatch_Event_Ledger__c
        ];
        Assert.areEqual(1, ledger.size(), 'Admitting an event must leave exactly one ledger row.');
        Assert.areEqual(candidate.eventKey, ledger[0].Event_Key__c, 'The ledger row must carry the event key.');
        Assert.areEqual(CursorBatchReplayGuard.CHANNEL_WORKER, ledger[0].Channel__c,
            'The ledger row must record which channel delivered the event.');
        Assert.areEqual(job.Id, ledger[0].Job_Record_Id__c, 'The ledger row must record the job.');
        Assert.areEqual(1, ledger[0].Worker_Number__c, 'The ledger row must record the worker shard.');
        Assert.areEqual(QUERY_ID, ledger[0].Cursor_Query_Id__c, 'The ledger row must record the cursor.');
    }

    @IsTest
    static void ageGateDisabledAdmitsAnAncientEvent() {
        // Max_Event_Age_Minutes__c = -1 is the documented opt-out for a job whose events can
        // legitimately sit undelivered.
        CursorBatchCoordinator.testConfig = configWithMaxEventAge(-1);
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        candidate.publishedAt = System.now().addDays(-4);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey),
            'A job that sets Max_Event_Age_Minutes__c to -1 must not have its events age-gated.');
    }

    @IsTest
    static void configuredAgeThresholdIsHonored() {
        CursorBatchCoordinator.testConfig = configWithMaxEventAge(5);
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        candidate.publishedAt = System.now().addMinutes(-10);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'A 10-minute-old event must be blocked when the job sets a 5-minute threshold.');
    }

    @IsTest
    static void eventWithNoPublishTimeSkipsTheAgeGate() {
        // Constructed (never published) events carry a null CreatedDate. The guard cannot judge
        // their age, and must not treat unknown as stale.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        candidate.publishedAt = null;

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey),
            'An event with no publish timestamp must not be rejected as stale.');
    }

    // =====================================================================================
    // Layer 2 -- job state
    // =====================================================================================

    @IsTest
    static void terminalJobBlocksDispatch() {
        CursorBatch_Job__c job = processingJob();
        job.Status__c = 'Completed';
        job.Completed_At__c = System.now();
        update job;

        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        CursorBatchReplayGuard.Verdict verdict = guard(true).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'A worker event for a job that has already completed is never legitimate. Every one of ' +
            'the ~51,000 events replayed on 2026-08-24 was in exactly this state.');
        Assert.areEqual(CursorBatchReplayGuard.REASON_JOB_TERMINAL,
            verdict.blockedReasonsByKey.get(candidate.eventKey),
            'The rejection must be attributed to the job being terminal.');
    }

    @IsTest
    static void completedAtAloneBlocksDispatch() {
        // The RCA calls "Completed_At__c old, LastModifiedDate recent" the highest signal-to-noise
        // tripwire available. This turns it from a monitor into a gate, independent of Status__c.
        CursorBatch_Job__c job = processingJob();
        job.Completed_At__c = System.now();
        update job;

        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        CursorBatchReplayGuard.Verdict verdict = guard(true).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'A completion timestamp must block dispatch even while Status__c still reads Processing.');
    }

    @IsTest
    static void missingJobBlocksDispatch() {
        CursorBatch_Job__c job = processingJob();
        Id jobId = job.Id;
        delete job;

        CursorBatchReplayGuard.Candidate candidate = new CursorBatchReplayGuard.Candidate(
            CursorBatchReplayGuard.buildWorkerKey(jobId, QUERY_ID, 1), jobId, 'TestJob', System.now()
        );

        CursorBatchReplayGuard.Verdict verdict = guard(true).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'An event whose job record no longer exists must not be dispatched.');
        Assert.areEqual(CursorBatchReplayGuard.REASON_JOB_MISSING,
            verdict.blockedReasonsByKey.get(candidate.eventKey),
            'The rejection must be attributed to the missing job.');
    }

    @IsTest
    static void terminalJobIsAdmittedWhenTheGateIsOff() {
        // The completion channel runs with the gate off on purpose: delivery order is not
        // guaranteed, so a non-final page event can legitimately arrive after the job went
        // terminal, and dropping it would lose a Completed_Batches__c increment.
        CursorBatch_Job__c job = processingJob();
        job.Status__c = 'Completed';
        job.Completed_At__c = System.now();
        update job;

        CursorBatchReplayGuard.Candidate candidate = new CursorBatchReplayGuard.Candidate(
            CursorBatchReplayGuard.buildCompletionKey(job.Id, '1001'), job.Id, 'TestJob', System.now()
        );

        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER_COMPLETE, new CursorBatchTestUtils.MockCursorBatchLogger()
        ).withTerminalJobGate(false).admit(new List<CursorBatchReplayGuard.Candidate>{ candidate });

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey),
            'With the job-state gate disabled, a terminal job must not block a completion event.');
    }

    // =====================================================================================
    // Layer 3 -- exactly-once
    // =====================================================================================

    @IsTest
    static void alreadyLedgeredEventIsBlocked() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate first = workerCandidate(job, 1, QUERY_ID);

        // Stand in for a previous transaction having already processed this event.
        insert new CursorBatch_Event_Ledger__c(
            Event_Key__c = first.eventKey,
            Channel__c = CursorBatchReplayGuard.CHANNEL_WORKER
        );

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ first }
        );

        Assert.isFalse(verdict.admittedKeys.contains(first.eventKey),
            'An event whose key is already in the ledger must be recognised as a replay.');
        Assert.areEqual(CursorBatchReplayGuard.REASON_DUPLICATE,
            verdict.blockedReasonsByKey.get(first.eventKey),
            'The rejection must be attributed to duplication.');
    }

    @IsTest
    static void duplicateWithinOneBatchIsClaimableOnce() {
        // Asserting on claim() rather than on admittedKeys.size(). The latter is a Set built from
        // two identical keys, so it reads 1 no matter what the guard decides -- it tests Apex, not
        // the guard. Whether a caller can dispatch twice is the property that actually matters.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate first = workerCandidate(job, 1, QUERY_ID);
        CursorBatchReplayGuard.Candidate second = workerCandidate(job, 1, QUERY_ID);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ first, second }
        );

        Assert.isTrue(verdict.claim(first.eventKey), 'The first delivery must be claimable.');
        Assert.isFalse(verdict.claim(second.eventKey),
            'The second delivery of the same event must not be claimable, or the caller dispatches it twice.');
        Assert.areEqual(1, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'The in-batch duplicate must never reach the unique index as a second row.');
    }

    @IsTest
    static void anAdmittedEventIsClaimableExactlyOnce() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isTrue(verdict.claim(candidate.eventKey), 'The admission must be claimable once.');
        Assert.isFalse(verdict.claim(candidate.eventKey),
            'A second claim of the same key must fail; the admission is consumed.');
        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey),
            'Claiming must not erase the record that the event was admitted.');
    }

    @IsTest
    static void claimRejectsBlankAndUnknownKeys() {
        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>()
        );

        Assert.isFalse(verdict.claim(null), 'A null key can never be claimed.');
        Assert.isFalse(verdict.claim(''), 'A blank key can never be claimed.');
        Assert.isFalse(verdict.claim('W#never-admitted'), 'An unadmitted key can never be claimed.');
    }

    @IsTest
    static void coordinatorRetryWithANewCursorIsAdmitted() {
        // The regression that matters most. A coordinator retry builds a fresh cursor and fans
        // out the same worker numbers again. That is legitimate work and must get through, which
        // is the whole reason the cursor queryId is part of the key rather than just the shard.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate firstAttempt = workerCandidate(job, 1, 'cursorFromFirstAttempt');
        CursorBatchReplayGuard.Candidate retryAttempt = workerCandidate(job, 1, 'cursorFromRetry');

        Assert.areNotEqual(firstAttempt.eventKey, retryAttempt.eventKey,
            'The same shard of a different cursor must be a different event identity.');

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ firstAttempt, retryAttempt }
        );

        Assert.isTrue(verdict.admittedKeys.contains(firstAttempt.eventKey), 'The original fan-out must be admitted.');
        Assert.isTrue(verdict.admittedKeys.contains(retryAttempt.eventKey),
            'A retry that rebuilt the cursor must be allowed to fan out again.');
    }

    @IsTest
    static void ledgerWriteFailureFailsOpen() {
        // Dropping legitimate batch work because a bookkeeping insert failed is worse than
        // admitting an event the cheap layers already vetted.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchReplayGuard.simulateLedgerWriteFailure = true;

        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER, mockLogger
        ).admit(new List<CursorBatchReplayGuard.Candidate>{ candidate });

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey),
            'A ledger write failure must admit the event rather than silently drop the work.');
        Assert.areEqual(1, mockLogger.exceptionMessages.size(),
            'The ledger write failure must be reported, since exactly-once is no longer being enforced.');
    }

    // =====================================================================================
    // Modes
    // =====================================================================================

    @IsTest
    static void partialLedgerWriteFailureFailsOpenPerRow() {
        // A row that fails for a reason other than duplication is admitted, because the cheap
        // layers already vetted it and dropping real batch work is the worse outcome. Provoked by
        // overflowing Channel__c, which the guard sets from the channel name rather than from
        // event data, so this is the only field it cannot pre-truncate.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = new CursorBatchTestUtils.MockCursorBatchLogger();

        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            'C'.repeat(60), mockLogger
        ).admit(new List<CursorBatchReplayGuard.Candidate>{ candidate });

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey),
            'A ledger row that fails to write for a non-duplication reason must still be admitted.');
        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'Precondition: the row genuinely failed to write.');
        Assert.areEqual(1, mockLogger.errorMessages.size(),
            'Losing exactly-once enforcement for a row must be reported.');
        Assert.isTrue(mockLogger.errorMessages[0].contains('other than duplication'),
            'The entry must distinguish a write failure from a detected replay.');
    }

    @IsTest
    static void anUnconfiguredJobIsStillGuarded() {
        // There is no opt-out for the guard as a whole, so a job nobody has configured must be
        // protected by default rather than exposed by default.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        insert new CursorBatch_Event_Ledger__c(
            Event_Key__c = candidate.eventKey,
            Channel__c = CursorBatchReplayGuard.CHANNEL_WORKER
        );

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'A replay must be blocked on a job that has no configuration record at all.');
    }

    @IsTest
    static void missingAgeConfigResolvesToTheDefault() {
        Assert.areEqual(CursorBatchReplayGuard.DEFAULT_MAX_EVENT_AGE_MINUTES,
            CursorBatchReplayGuard.resolveMaxEventAgeMinutes('NoSuchJobAnywhere'),
            'An unconfigured job must use the framework default threshold.');
    }

    // =====================================================================================
    // Aggregated reporting
    // =====================================================================================

    @IsTest
    static void manyRejectionsProduceOneLogEntry() {
        // Per-event logging is what turned the 2026-08-24 replay into an org-wide publish
        // allocation breach: 676,439 log events in one hour, 79.7% of the org's entire hourly
        // allocation. A guard that logs per blocked event would reproduce it exactly.
        CursorBatch_Job__c job = processingJob();
        List<CursorBatchReplayGuard.Candidate> candidates = new List<CursorBatchReplayGuard.Candidate>();
        for (Integer i = 1; i <= 50; i++) {
            CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, i, QUERY_ID);
            candidate.publishedAt = System.now().addHours(-3);
            candidates.add(candidate);
        }
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = new CursorBatchTestUtils.MockCursorBatchLogger();

        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER, mockLogger
        ).admit(candidates);

        Assert.areEqual(0, verdict.admittedKeys.size(), 'All 50 stale events must be blocked.');
        Assert.areEqual(1, mockLogger.errorMessages.size(),
            'Fifty rejections must produce one aggregated entry, not fifty.');
        Assert.isTrue(mockLogger.errorMessages[0].contains('50 ' + CursorBatchReplayGuard.REASON_STALE),
            'The aggregated entry must report the full count so the scale is visible.');
        Assert.isTrue(mockLogger.errorMessages[0].contains('and 45 more'),
            'The entry must sample keys rather than inline all fifty.');
    }

    @IsTest
    static void nothingBlockedEmitsNothing() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = new CursorBatchTestUtils.MockCursorBatchLogger();

        new CursorBatchReplayGuard(CursorBatchReplayGuard.CHANNEL_WORKER, mockLogger)
            .admit(new List<CursorBatchReplayGuard.Candidate>{ workerCandidate(job, 1, QUERY_ID) });

        Assert.areEqual(0, mockLogger.errorMessages.size(),
            'A clean batch must be silent; the guard runs on every delivery.');
    }

    // =====================================================================================
    // Key composition
    // =====================================================================================

    @IsTest
    static void completionKeyFormatIsPinned() {
        // Unchanged from the pre-ledger CursorBatch_Processed_Event__c key so operational
        // queries written against the old format keep working.
        Id jobId = processingJob().Id;
        Assert.areEqual(jobId + '#4242',
            CursorBatchReplayGuard.buildCompletionKey(jobId, '4242'),
            'The completion key must stay jobRecordId#replayId.');
    }

    @IsTest
    static void completionKeyIsNullWithoutBothComponents() {
        Id jobId = processingJob().Id;
        Assert.isNull(CursorBatchReplayGuard.buildCompletionKey(null, '1'),
            'No job means no identity to dedupe on.');
        Assert.isNull(CursorBatchReplayGuard.buildCompletionKey(jobId, null),
            'No ReplayId means no identity to dedupe on.');
    }

    @IsTest
    static void channelPrefixesKeepKeysDistinct() {
        Id jobId = processingJob().Id;
        String workerKey = CursorBatchReplayGuard.buildWorkerKey(jobId, QUERY_ID, 1);
        String coordinatorKey = CursorBatchReplayGuard.buildCoordinatorKey(jobId, 'SomeCoordinator');

        Assert.isTrue(workerKey.startsWith('W#'), 'Worker keys must be prefixed for their channel.');
        Assert.isTrue(coordinatorKey.startsWith('C#'), 'Coordinator keys must be prefixed for their channel.');
        Assert.areNotEqual(workerKey, coordinatorKey, 'Channels must not be able to collide on one key.');
    }

    @IsTest
    static void csvCallbacksDoNotCollideWithTheInitialDispatch() {
        // All three carry the same job record Id; only the class component separates them.
        Id jobId = processingJob().Id;
        Set<String> keys = new Set<String>{
            CursorBatchReplayGuard.buildCoordinatorKey(jobId, 'MyCsvCoordinator'),
            CursorBatchReplayGuard.buildCoordinatorKey(jobId, 'CSV_Ready'),
            CursorBatchReplayGuard.buildCoordinatorKey(jobId, 'CSV_Error')
        };
        Assert.areEqual(3, keys.size(),
            'A CSV job dispatch and its two callbacks must be three distinct identities.');
    }

    @IsTest
    static void oversizedKeyIsDigestedToFitTheField() {
        // A cursor queryId is opaque and of unbounded length, so the readable key can overflow
        // Event_Key__c. The digest must preserve both uniqueness and the channel prefix.
        Id jobId = processingJob().Id;
        String longQueryId = 'q'.repeat(400);
        String key = CursorBatchReplayGuard.buildWorkerKey(jobId, longQueryId, 1);
        String otherKey = CursorBatchReplayGuard.buildWorkerKey(jobId, longQueryId, 2);

        Assert.isTrue(key.length() <= 255, 'An oversized key must be reduced to fit Event_Key__c.');
        Assert.isTrue(key.startsWith('W#'), 'The digested key must keep its channel prefix.');
        Assert.areNotEqual(key, otherKey, 'Digesting must not collapse distinct shards onto one key.');
    }

    @IsTest
    static void oversizedKeyStillWritesToTheLedger() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, 'q'.repeat(400));

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isTrue(verdict.admittedKeys.contains(candidate.eventKey), 'A digested key must still be admissible.');
        Assert.areEqual(1, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'The oversized cursor queryId must be truncated to fit rather than failing the insert.');
    }

    // =====================================================================================
    // Degenerate input
    // =====================================================================================

    @IsTest
    static void nullAndEmptyBatchesAreNoOps() {
        CursorBatchReplayGuard.Verdict fromNull = guard(true).admit(null);
        CursorBatchReplayGuard.Verdict fromEmpty = guard(true).admit(
            new List<CursorBatchReplayGuard.Candidate>()
        );

        Assert.areEqual(0, fromNull.admittedKeys.size(), 'A null batch must admit nothing.');
        Assert.areEqual(0, fromEmpty.admittedKeys.size(), 'An empty batch must admit nothing.');
    }

    @IsTest
    static void candidateWithNoKeyIsIgnoredRatherThanBlocked() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate keyless = new CursorBatchReplayGuard.Candidate(
            null, job.Id, 'TestJob', System.now()
        );

        CursorBatchReplayGuard.Verdict verdict = guard(true).admit(
            new List<CursorBatchReplayGuard.Candidate>{ keyless }
        );

        Assert.areEqual(0, verdict.admittedKeys.size(), 'An unidentifiable event has no key to admit.');
        Assert.areEqual(0, verdict.blockedReasonsByKey.size(),
            'An unidentifiable event must not be reported as a replay; nothing was proven about it.');
    }

    @IsTest
    static void nullLoggerIsToleratedByTheConstructor() {
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        candidate.publishedAt = System.now().addHours(-3);

        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER, null
        ).admit(new List<CursorBatchReplayGuard.Candidate>{ candidate });

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'The guard must still function, and still report, when no logger was supplied.');
    }

    @IsTest
    static void nowOverrideDrivesTheAgeComparison() {
        // Pins the test seam itself: without it the staleness layer is only testable by waiting.
        CursorBatch_Job__c job = processingJob();
        CursorBatchReplayGuard.Candidate candidate = workerCandidate(job, 1, QUERY_ID);
        candidate.publishedAt = System.now();
        CursorBatchReplayGuard.nowOverride = System.now().addHours(5);

        CursorBatchReplayGuard.Verdict verdict = guard(false).admit(
            new List<CursorBatchReplayGuard.Candidate>{ candidate }
        );

        Assert.isFalse(verdict.admittedKeys.contains(candidate.eventKey),
            'Advancing the guard clock must make a fresh event read as stale.');
    }

    // =====================================================================================
    // Helpers
    // =====================================================================================

    private static CursorBatchReplayGuard guard(Boolean terminalJobGate) {
        return new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER, new CursorBatchTestUtils.MockCursorBatchLogger()
        ).withTerminalJobGate(terminalJobGate);
    }

    private static CursorBatch_Job__c processingJob() {
        return CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
    }

    private static CursorBatchReplayGuard.Candidate workerCandidate(
        CursorBatch_Job__c job,
        Integer workerNumber,
        String cursorQueryId
    ) {
        CursorBatchReplayGuard.Candidate candidate = new CursorBatchReplayGuard.Candidate(
            CursorBatchReplayGuard.buildWorkerKey(job.Id, cursorQueryId, workerNumber),
            job.Id,
            job.Job_Name__c,
            System.now()
        );
        candidate.cursorQueryId = cursorQueryId;
        candidate.workerNumber = workerNumber;
        candidate.replayId = String.valueOf(1000 + workerNumber);
        return candidate;
    }

    private static CursorBatch_Config__mdt configWithMaxEventAge(Integer maxAgeMinutes) {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 2, 20);
        config.Max_Event_Age_Minutes__c = maxAgeMinutes;
        return config;
    }
}
