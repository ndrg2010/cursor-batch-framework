/**
 * @description Handles CursorBatch_Worker__e Platform Events. Spawns cursor batch workers
 *              using dynamic instantiation. Reconstructs Database.Cursor from the queryId
 *              passed in each event. Uses instance methods for testability.
 *
 *              Logging: the framework's default logger (CursorBatchLogger.getDefault()) writes
 *              everything to System.debug, which is invisible after the debug log window
 *              expires and has no persistent paper trail for stuck-job forensics. This handler
 *              instead routes through CursorBatchLogger.resolveLogger(LOG_TAG), the framework's
 *              convention-based extension point: it looks up CursorBatchLoggerAdapter via
 *              Type.forName (Callable-enabled Nebula adapter living in the consumer namespace),
 *              tags it with LOG_TAG, and falls back to System.debug only if the adapter class
 *              cannot be loaded -- so this stays cross-package safe even if the framework is
 *              repackaged or the adapter is moved between namespaces. Both PE dispatch
 *              handlers (this class and CursorBatchCoordinatorTriggerHandler) share the same
 *              LOG_TAG so ops can pull "anything that went wrong during PE dispatch" in a
 *              single LogEntry__c tag filter rather than having to OR two separate tags.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchCoordinator
 * @see CursorBatchLogger
 * @see CursorBatchLoggerAdapter
 */
public virtual without sharing class CursorBatchWorkerTriggerHandler {
    
    /**
     * @description Shared tag attached to every LogEntry__c emitted from PE dispatch handlers.
     *              Kept identical in CursorBatchCoordinatorTriggerHandler so ops dashboards can
     *              filter both subscribers' logs with a single tag clause. @TestVisible so the
     *              pinned-value test can catch silent drift before LogEntry__c queries miss
     *              data.
     */
    @TestVisible
    private static final String LOG_TAG = 'CursorBatch Dispatch';

    private Map<String, Database.Cursor> cursorsByQueryId;
    private ICursorBatchLogger logger;
    
    /** Shards reported as failed on their own behalf, published together at the end of handle(). */
    private List<CursorBatch_WorkerComplete__e> failureReports;
    
    /**
     * @description Default constructor. Routes log output through Nebula Logger (via the
     *              framework's resolveLogger convention) instead of the System.debug default,
     *              so cursor-reconstruction failures and swallowed exceptions are recoverable
     *              from LogEntry__c after the transaction ends.
     */
    public CursorBatchWorkerTriggerHandler() {
        this.cursorsByQueryId = new Map<String, Database.Cursor>();
        this.logger = CursorBatchLogger.resolveLogger(LOG_TAG);
        this.failureReports = new List<CursorBatch_WorkerComplete__e>();
    }
    
    /**
     * @description Handles incoming Platform Events by creating and enqueueing workers.
     *
     *              Every event is put through CursorBatchReplayGuard before anything is
     *              enqueued. This handler used to enqueue unconditionally on every delivery,
     *              which is why the 2026-08-24 offset rewind turned ~51,000 redelivered events
     *              into 314,453 asynchronous jobs against a baseline of 10,000-15,000 per day.
     *              The guard runs once for the whole subscriber batch so its cost does not scale
     *              with batch size, and it records its ledger rows in this same transaction:
     *              because enqueued jobs only materialize on commit, the marker and the dispatch
     *              either both happen or neither does.
     * @param events CursorBatch_Worker__e events from the Platform Event trigger
     */
    public void handle(List<CursorBatch_Worker__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        Map<String, CursorBatch_Worker__e> eventsByKey = new Map<String, CursorBatch_Worker__e>();
        List<CursorBatchReplayGuard.Candidate> candidates = new List<CursorBatchReplayGuard.Candidate>();
        for (CursorBatch_Worker__e evt : events) {
            CursorBatchReplayGuard.Candidate candidate;
            try {
                candidate = buildCandidate(evt);
            } catch (Exception e) {
                // A malformed Job_Record_Id__c is the realistic cause. Fall through to
                // processEvent, which reports the same event's failure with full context.
                logger.logException('CursorBatchWorkerTriggerHandler: Could not identify event for job "' +
                    evt.Job_Name__c + '"; dispatching unguarded', e);
            }
            if (candidate == null) {
                // Nothing to key on. Dispatch rather than silently drop work the framework itself
                // published; processEvent has its own error handling.
                processEvent(evt);
                continue;
            }
            eventsByKey.put(candidate.eventKey, evt);
            candidates.add(candidate);
        }
        
        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER, logger
        ).withTerminalJobGate(true).admit(candidates);
        
        List<CursorBatchReplayGuard.Candidate> staleShards = new List<CursorBatchReplayGuard.Candidate>();
        for (CursorBatchReplayGuard.Candidate candidate : candidates) {
            // claim(), not a set lookup: candidates retains both entries when one batch carries
            // the same event twice, which is the ordinary shape of a redelivery burst. A
            // non-consuming check would dispatch the shard twice.
            if (verdict.claim(candidate.eventKey)) {
                processEvent(eventsByKey.get(candidate.eventKey));
            } else if (CursorBatchReplayGuard.REASON_STALE == verdict.blockedReasonsByKey.get(candidate.eventKey)) {
                staleShards.add(candidate);
            }
        }
        reportStaleShardsAsFailed(staleShards);
        publishFailureReports();
    }
    
    /**
     * @description Reports each shard the guard rejected as stale as a failed worker, by
     *              queueing the same completion event a worker would publish after exhausting
     *              its retries.
     *
     *              Without this, blocking is a worse outcome than the replay. Total_Workers__c
     *              still counts the rejected shard, so Workers_Finished__c + Failed_Workers__c
     *              can never reach it: the job sits in Processing forever, finish() never fires,
     *              and because isJobAlreadyRunning treats Processing as running, every future
     *              submission of that job name silently returns null. One dropped shard would
     *              retire the job permanently.
     *
     *              Only REASON_STALE is reconciled. JOB_TERMINAL and JOB_MISSING have no live job
     *              to report against, and DUPLICATE means the shard was already dispatched and
     *              will report on its own -- reporting it again would double-count.
     *
     *              Publishing rather than updating the job directly keeps the terminal-status
     *              transition, the parent mirror, and the finish() routing in
     *              CursorBatchCompletionHandler, which is the only place that logic should live.
     * @param staleShards Candidates rejected with REASON_STALE
     */
    private void reportStaleShardsAsFailed(List<CursorBatchReplayGuard.Candidate> staleShards) {
        for (CursorBatchReplayGuard.Candidate candidate : staleShards) {
            if (candidate.jobRecordId == null) {
                continue;
            }
            failureReports.add(CursorBatchCompletionHandler.buildFailureReport(
                candidate.jobRecordId,
                candidate.workerNumber,
                CursorBatchCompletionHandler.REPORTED_BY_REPLAY_GUARD,
                'Replay guard rejected worker #' + candidate.workerNumber +
                    ' as stale: the event was published ' + candidate.publishedAt +
                    ' and exceeded Max_Event_Age_Minutes__c. The shard did not run.'
            ));
        }
    }
    
    /**
     * @description Reports a shard that was admitted but never enqueued as a failed worker. Like a
     *              stale shard, a shard whose dispatch failed would otherwise leave
     *              Workers_Finished__c + Failed_Workers__c permanently short of Total_Workers__c.
     *
     *              Skipped when the event's job record Id is not a valid Id. The completion
     *              handler converts Job_Id__c to an Id, so a malformed value would throw there and
     *              roll back the whole subscriber batch, taking other jobs' completions with it.
     *              The failure has already been logged by the caller.
     * @param evt The worker event that could not be dispatched
     * @param reason Why the shard could not be enqueued
     */
    private void reportDispatchFailure(CursorBatch_Worker__e evt, String reason) {
        Id jobId = toIdOrNull(evt.Job_Record_Id__c);
        if (jobId == null) {
            return;
        }
        Integer workerNumber = evt.Worker_Number__c != null ? evt.Worker_Number__c.intValue() : null;
        failureReports.add(CursorBatchCompletionHandler.buildFailureReport(
            jobId,
            workerNumber,
            CursorBatchCompletionHandler.REPORTED_BY_DISPATCH,
            'Worker #' + workerNumber + ' was never enqueued, so the shard did not run: ' + reason
        ));
    }
    
    /**
     * @description Publishes every failure report queued in this transaction.
     */
    private void publishFailureReports() {
        CursorBatchCompletionHandler.publishFailureReports(failureReports, logger);
        failureReports.clear();
    }
    
    private static Id toIdOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Normalizes a worker event into a guard candidate. The cursor queryId is part
     *              of the identity so that a coordinator retry, which necessarily builds a new
     *              cursor, produces a new key and is allowed to fan out again.
     * @param evt CursorBatch_Worker__e event
     * @return Candidate for CursorBatchReplayGuard.admit, or null when the event lacks the fields
     *         to identify itself
     */
    private CursorBatchReplayGuard.Candidate buildCandidate(CursorBatch_Worker__e evt) {
        if (String.isBlank(evt.Job_Record_Id__c) || evt.Worker_Number__c == null) {
            return null;
        }
        Integer workerNumber = Integer.valueOf(evt.Worker_Number__c);
        String eventKey = CursorBatchReplayGuard.buildWorkerKey(
            evt.Job_Record_Id__c, evt.Cursor_Query_Id__c, workerNumber
        );
        CursorBatchReplayGuard.Candidate candidate = new CursorBatchReplayGuard.Candidate(
            eventKey, evt.Job_Record_Id__c, evt.Job_Name__c, evt.CreatedDate
        );
        candidate.cursorQueryId = evt.Cursor_Query_Id__c;
        candidate.workerNumber = workerNumber;
        Object replayId = evt.get('ReplayId');
        candidate.replayId = replayId != null ? String.valueOf(replayId) : null;
        return candidate;
    }
    
    /**
     * @description Processes a single event by reconstructing the cursor (for SOQL) or
     *              skipping reconstruction (for CSV) and enqueueing a worker. A shard that cannot
     *              be enqueued is reported as a failed worker rather than only logged, so its job
     *              can still reach a terminal status.
     * @param evt CursorBatch_Worker__e event containing worker parameters
     */
    private void processEvent(CursorBatch_Worker__e evt) {
        // Set as soon as the enqueue returns, so a failure while logging afterwards can never
        // report a shard that is in fact queued -- that would count it twice and could complete
        // the job while the worker is still running.
        Boolean enqueued = false;
        try {
            Database.Cursor cursor = null;
            
            if (evt.Processing_Type__c != CursorBatchContext.PROCESSING_TYPE_CSV) {
                String queryId = evt.Cursor_Query_Id__c;
                cursor = cursorsByQueryId.get(queryId);
                
                if (cursor == null) {
                    cursor = CursorBatchContext.reconstructCursor(queryId);
                    if (cursor == null) {
                        logger.logError('CursorBatchWorkerTriggerHandler: Failed to reconstruct cursor for queryId "' + queryId + '"');
                        reportDispatchFailure(evt, 'the cursor could not be reconstructed from queryId "' + queryId + '"');
                        return;
                    }
                    logger.logInfo('CursorBatchWorkerTriggerHandler: Reconstructed cursor for queryId "' + queryId + '"');
                    cursorsByQueryId.put(queryId, cursor);
                }
            }
            
            CursorBatchContext ctx = CursorBatchContext.fromEvent(evt, cursor);
            enqueueWorker(ctx);
            enqueued = true;
            logger.logInfo('CursorBatchWorkerTriggerHandler: Enqueued ' + ctx.workerClassName + ' #' + ctx.workerNum +
                ' (positions ' + ctx.startPosition + '-' + ctx.endPosition + ')');
            
        } catch (Exception e) {
            logger.logException('CursorBatchWorkerTriggerHandler: Error processing event for job "' + evt.Job_Name__c + '"', e);
            if (!enqueued) {
                reportDispatchFailure(evt, e.getTypeName() + ': ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Creates and enqueues a worker instance for the given context.
     * @param ctx CursorBatchContext containing worker execution parameters
     * @throws CursorBatchException When worker class name is blank
     */
    private void enqueueWorker(CursorBatchContext ctx) {
        String workerClassName = ctx.workerClassName;
        
        if (String.isBlank(workerClassName)) {
            throw new CursorBatchCoordinator.CursorBatchException('Worker class name not specified for job: ' + ctx.jobName);
        }
        
        CursorBatchWorker worker = CursorBatchContext.createWorkerInstance(workerClassName, ctx);
        
        if (!Test.isRunningTest()) {
            System.enqueueJob(worker);
        }
    }
    
}