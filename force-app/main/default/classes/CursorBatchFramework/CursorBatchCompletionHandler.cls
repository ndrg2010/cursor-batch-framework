/**
 * @description Handles CursorBatch_WorkerComplete__e Platform Events. Updates job tracking
 *              records and invokes coordinator callbacks when all workers have completed.
 *
 *              Idempotency runs through CursorBatchReplayGuard for every job, not just the
 *              stateful ones. It used to be limited to jobs with a state reducer -- 7 of 62
 *              configurations in the org that hit the 2026-08-24 redelivery -- and its marker
 *              rows were deleted the moment a job completed, so even the protected jobs were
 *              defenceless against a replay arriving after completion. The guard's ledger is
 *              retained by age instead, and is written in this same transaction as the counter
 *              updates so a rollback takes both.
 * @group CursorBatchFramework
 * @see CursorBatchReplayGuard
 * @see CursorBatchWorkerFinalizer
 * @see CursorBatchCoordinator
 */
public without sharing class CursorBatchCompletionHandler {
    
    /** Maximum length of CursorBatch_Job__c.Error_Message__c (LongTextArea). Used to truncate appended errors. */
    public static final Integer ERROR_MESSAGE_MAX_LENGTH = 32768;
    
    /** Tag used when a job has no Logger_Tag__c, so terminal entries are never emitted untagged. */
    public static final String DEFAULT_LOG_TAG = 'CursorBatch Completion';
    
    /** Cap on error text embedded in a terminal summary; the full text remains on the job record. */
    private static final Integer TERMINAL_SUMMARY_ERROR_MAX_LENGTH = 4000;
    
    /** Distinct worker errors sampled into the batch failure summary before it is truncated. */
    private static final Integer WORKER_FAILURE_SAMPLE_LIMIT = 5;
    
    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor. Resolves the org's logger adapter rather than the
     *              System.debug default, so the class that decides terminal job status reports
     *              through the same logging framework as the rest of the framework.
     */
    public CursorBatchCompletionHandler() {
        this.logger = CursorBatchLogger.resolveLogger(DEFAULT_LOG_TAG);
    }
    
    /**
     * @description Overrides the logger so tests can assert on emitted entries.
     * @param logger Logger to use
     */
    @TestVisible
    private void setLogger(ICursorBatchLogger logger) {
        this.logger = logger;
    }
    
    /**
     * @description Handles worker completion events by updating tracking records and invoking
     *              callbacks when all workers finish.
     *
     *              Every event passes through CursorBatchReplayGuard first, so a redelivered
     *              completion cannot apply its counters or its state delta a second time. The
     *              guard's ledger write and the counter updates share this transaction: a
     *              rollback takes both, leaving the events legitimately eligible for redelivery,
     *              rather than committing the effect and losing the marker.
     *
     *              Only the guard's exactly-once layer is enabled here; the job-state and
     *              staleness layers are both off. Delivery order across batches is not
     *              guaranteed, so a non-final page event can legitimately arrive after the last
     *              worker's final event has already pushed the job terminal, and a completion
     *              event is a report rather than a dispatch -- blocking one discards the record
     *              that work already happened, and is the one rejection nothing can reconcile.
     *              The ledger is exact, so it needs no heuristic help, and the duplicate finish()
     *              a late event might otherwise cause is prevented by the completion transition
     *              check further down.
     * @param events CursorBatch_WorkerComplete__e events from the Platform Event trigger
     */
    public void handle(List<CursorBatch_WorkerComplete__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        // Group events by Job ID
        Map<Id, List<CursorBatch_WorkerComplete__e>> eventsByJob = new Map<Id, List<CursorBatch_WorkerComplete__e>>();
        for (CursorBatch_WorkerComplete__e evt : events) {
            Id jobId = evt.Job_Id__c;
            if (!eventsByJob.containsKey(jobId)) {
                eventsByJob.put(jobId, new List<CursorBatch_WorkerComplete__e>());
            }
            eventsByJob.get(jobId).add(evt);
        }
        
        // Query job records
        Map<Id, CursorBatch_Job__c> jobsMap = CursorBatchSelector.getJobsByIds(eventsByJob.keySet());
        
        CursorBatchReplayGuard.Verdict verdict = runReplayGuard(eventsByJob, jobsMap);
        
        // One entry per job Id (no duplicate job records in list).
        List<CursorBatch_Job__c> jobsToUpdate = new List<CursorBatch_Job__c>();
        List<CursorBatch_Job__c> completedJobs = new List<CursorBatch_Job__c>();
        
        for (Id jobId : eventsByJob.keySet()) {
            CursorBatch_Job__c job = jobsMap.get(jobId);
            if (job == null) {
                logger.logError('CursorBatchCompletionHandler: Job not found: ' + jobId);
                continue;
            }
            
            List<CursorBatch_WorkerComplete__e> jobEvents = eventsByJob.get(jobId);
            Integer batchSuccessCount = 0;  // Tracks page/batch completions
            Integer workersFinishedCount = 0;  // Tracks distinct workers that finished all pages
            Integer failCount = 0;
            Integer totalRetries = 0;
            // Collected and reported as one entry after the loop rather than one per event. A
            // logging adapter that persists entries costs DML per entry, and this loop runs over a
            // whole platform-event batch, so per-event logging would scale log volume and DML with
            // the subscriber batch size. Each worker failure is already reported individually by
            // CursorBatchWorkerFinalizer in its own transaction; this is the batch summary.
            List<String> workerFailures = new List<String>();
            
            for (CursorBatch_WorkerComplete__e evt : jobEvents) {
                String eventKey = getEventKey(evt);
                // claim(), not a set lookup: one batch can carry the same event twice, and a
                // non-consuming check would count its counters and its state delta twice.
                if (String.isNotBlank(eventKey) && !verdict.claim(eventKey)) {
                    continue; // Replay, or a duplicate within this batch
                }
                
                // Aggregate worker retry counts
                if (evt.Retry_Count__c != null && evt.Retry_Count__c > 0) {
                    totalRetries += Integer.valueOf(evt.Retry_Count__c);
                }
                
                if (evt.Success__c) {
                    batchSuccessCount++;
                    if (String.isNotBlank(evt.State_Delta__c)) {
                        try {
                            String newStateJson = CursorBatchStateManager.reduceState(job, evt.State_Delta__c);
                            if (newStateJson != null && newStateJson.length() > CursorBatchStateManager.STATE_JSON_MAX_LENGTH) {
                                logger.logError('CursorBatchCompletionHandler: State exceeded field limit for job ' + job.Job_Name__c + ', skipping delta');
                            } else {
                                job.State_JSON__c = newStateJson;
                            }
                        } catch (Exception e) {
                            logger.logException('CursorBatchCompletionHandler: State reduction failed for job ' + job.Job_Name__c + (String.isNotBlank(eventKey) ? ', eventKey=' + eventKey : '') + ', skipping delta', e);
                        }
                    }
                    // Only count toward Workers_Finished if this is the final page
                    if (evt.Is_Final__c == true) {
                        workersFinishedCount++;
                    }
                } else {
                    failCount++;
                    // Capture first error only (similar to AsyncApexJob.ExtendedStatus)
                    if (job.Error_Message__c == null && String.isNotBlank(evt.Error_Message__c)) {
                        job.Error_Message__c = evt.Error_Message__c;
                    }
                    workerFailures.add(
                        String.isNotBlank(evt.Error_Message__c) ? evt.Error_Message__c : 'No error detail reported'
                    );
                }
                
            }
            
            logWorkerFailures(job, workerFailures);
            
            // Initialize fields if null
            if (job.Completed_Batches__c == null) {
                job.Completed_Batches__c = 0;
            }
            if (job.Workers_Finished__c == null) {
                job.Workers_Finished__c = 0;
            }
            // Defensive rather than load-bearing: the field defaults to 0, so it is null only if
            // something explicitly nulled it. Guarded anyway because
            // CursorBatchWorkerCompleteTrigger has no try/catch, so an NPE here would roll back
            // the whole subscriber batch rather than failing this one job -- the two counters
            // above are guarded for the same reason.
            if (job.Failed_Workers__c == null) {
                job.Failed_Workers__c = 0;
            }
            
            job.Completed_Batches__c += batchSuccessCount;
            job.Workers_Finished__c += workersFinishedCount;
            job.Failed_Workers__c += failCount;
            
            // Track total worker retries across the job
            if (job.Total_Worker_Retries__c == null) {
                job.Total_Worker_Retries__c = 0;
            }
            job.Total_Worker_Retries__c += totalRetries;
            
            // Check if all workers are done (using Workers_Finished + Failed, not batch count).
            // Completion is a transition, not a standing condition: only the batch that moves the
            // job across the threshold completes it. Testing the condition alone would re-complete
            // an already-terminal job on every later batch — a page event redelivered after the
            // last worker's final event has been counted still satisfies it — invoking the finish
            // callback more than once and duplicating whatever it chains to.
            Decimal totalDone = job.Workers_Finished__c + job.Failed_Workers__c;
            Decimal doneBeforeThisBatch = totalDone - workersFinishedCount - failCount;
            if (doneBeforeThisBatch < job.Total_Workers__c && totalDone >= job.Total_Workers__c) {
                // Preserve Cancelled status if job was killed (don't overwrite with completion status)
                if (job.Status__c != 'Cancelled') {
                    if (job.Failed_Workers__c == 0) {
                        job.Status__c = 'Completed';
                    } else if (job.Workers_Finished__c > 0) {
                        job.Status__c = 'Completed with Errors';
                    } else {
                        job.Status__c = 'Failed';
                    }
                }
                if (job.Completed_At__c == null) {
                    job.Completed_At__c = System.now();
                }
                completedJobs.add(job);
            }
            
            jobsToUpdate.add(job);
        }
        
        if (!jobsToUpdate.isEmpty()) {
            update jobsToUpdate;
        }
        
        // Invoke callbacks for completed jobs using 4-path finish logic.
        // Skip the finish callback for cancelled jobs (kill switch activated), but still
        // update the parent's Last_Job_Status__c so the parent reflects the terminal state.
        for (CursorBatch_Job__c job : completedJobs) {
            if (job.Status__c != 'Cancelled') {
                routeFinishCallback(job, logger);
            } else {
                updateParentLastStatus(job, logger);
                logTerminalStatus(job, logger);
            }
        }
    }
    
    /**
     * @description Reports every worker failure seen for one job in this platform-event batch as a
     *              single entry. One entry per event would make both log volume and DML scale with
     *              the subscriber batch size, which is a tuning knob rather than a constant, and a
     *              wide fan-out job that fails everywhere would bury the job-level outcome under
     *              hundreds of near-identical entries.
     * @param job The job whose workers failed
     * @param failureMessages Error text from each failed event, in the order received
     */
    private void logWorkerFailures(CursorBatch_Job__c job, List<String> failureMessages) {
        if (failureMessages == null || failureMessages.isEmpty()) {
            return;
        }
        
        List<String> distinctMessages = new List<String>();
        Set<String> seen = new Set<String>();
        for (String message : failureMessages) {
            if (seen.add(message)) {
                distinctMessages.add(message);
            }
        }
        
        Set<String> tags = new Set<String>{ CursorBatchLogger.TAG_WORKER_FAILURE };
        String codeTag = CursorBatchLogger.failureCodeTag(distinctMessages[0]);
        if (codeTag != null) {
            tags.add(codeTag);
        }
        
        String summary = 'Job: ' + job.Job_Name__c + ' (' + job.Id + '), ' +
            failureMessages.size() + ' worker failure(s) in this event batch';
        Integer sampled = Math.min(distinctMessages.size(), WORKER_FAILURE_SAMPLE_LIMIT);
        for (Integer i = 0; i < sampled; i++) {
            summary += '\n- ' + distinctMessages[i];
        }
        if (distinctMessages.size() > sampled) {
            summary += '\n- ...and ' + (distinctMessages.size() - sampled) + ' more distinct error(s)';
        }
        
        CursorBatchLogger.withScopeTags(logger, resolveJobTag(job), tags)
            .logError(CursorBatchLogger.scoped(CursorBatchLogger.SCOPE_WORKER_FAILED, summary));
    }
    
    /**
     * @description Runs the replay guard over every event in this batch.
     *
     *              The job records have already been queried for the counter update, so their
     *              names are passed through on each candidate and the guard does not need a
     *              second query. The job-state layer stays off; see handle() for why.
     * @param eventsByJob Events grouped by job Id
     * @param jobsMap Job records already queried for this batch
     * @return Verdict naming which events may be counted
     */
    private CursorBatchReplayGuard.Verdict runReplayGuard(
        Map<Id, List<CursorBatch_WorkerComplete__e>> eventsByJob,
        Map<Id, CursorBatch_Job__c> jobsMap
    ) {
        List<CursorBatchReplayGuard.Candidate> candidates = new List<CursorBatchReplayGuard.Candidate>();
        for (Id jobId : eventsByJob.keySet()) {
            CursorBatch_Job__c job = jobsMap.get(jobId);
            for (CursorBatch_WorkerComplete__e evt : eventsByJob.get(jobId)) {
                String eventKey = getEventKey(evt);
                if (String.isBlank(eventKey)) {
                    // No ReplayId means no identity to dedupe on, which is the case in tests
                    // where events are constructed rather than published. Such events are
                    // counted, matching the pre-guard behaviour.
                    continue;
                }
                CursorBatchReplayGuard.Candidate candidate = new CursorBatchReplayGuard.Candidate(
                    eventKey, jobId, job?.Job_Name__c, evt.CreatedDate
                );
                candidate.replayId = getReplayIdString(evt);
                candidates.add(candidate);
            }
        }
        
        return new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_WORKER_COMPLETE, logger
        ).withTerminalJobGate(false).withStalenessGate(false).admit(candidates);
    }
    
    private static String getEventKey(CursorBatch_WorkerComplete__e evt) {
        return CursorBatchReplayGuard.buildCompletionKey(evt.Job_Id__c, getReplayIdString(evt));
    }
    
    private static String getReplayIdString(CursorBatch_WorkerComplete__e evt) {
        Object replayId = evt.get('ReplayId');
        return replayId != null ? String.valueOf(replayId) : null;
    }
    
    
    /**
     * @description Routes the finish callback for a completed job using 4-path logic.
     *              Called by both the completion handler (when workers finish) and the
     *              coordinator (when cursor returns 0 records). This ensures consistent
     *              finish behavior regardless of whether records were processed.
     *              
     *              4-path logic:
     *              1. If Chain_To_Job__c is set → chain to another CursorJob by name
     *              2. Else if Chain_To_Class__c is set → invoke the chain via Callable
     *              3. Else if Query_Builder_Class__c is set (CursorJob) → call worker.finish()
     *              4. Else → call coordinator.finish()
     *              
     *              Wrapped in try-catch to ensure exceptions are logged and don't silently
     *              crash the caller. Falls back to coordinator.finish() on error.
     *              
     *              A failure in the finish callback is recorded on the job record itself
     *              (Error_Message__c, and Status__c upgraded to 'Completed with Errors') so the
     *              job does not sit in a green terminal state with the failure visible only in
     *              a debug log.
     * @param job The completed job record
     * @param logger Logger instance for error reporting
     */
    public static void routeFinishCallback(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        updateParentLastStatus(job, logger);
        Exception finishError = null;
        try {
            finishError = routeFinishCallbackInternal(job, logger);
        } catch (Exception e) {
            finishError = e;
            logger.logException(CursorBatchLogger.scoped(
                CursorBatchLogger.SCOPE_JOB_FINISH_FAILED,
                'Error routing the finish callback for job ' + job.Job_Name__c + ' (' + job.Id + ')'
            ), e);
            try {
                CursorBatchCoordinator.invokeFinishCallback(job.Coordinator_Class__c, job.Job_Name__c, job, logger);
            } catch (Exception fallbackEx) {
                logger.logException(CursorBatchLogger.scoped(
                    CursorBatchLogger.SCOPE_JOB_FINISH_FAILED,
                    'Fallback coordinator.finish() also failed for job ' + job.Job_Name__c + ' (' + job.Id + ')'
                ), fallbackEx);
            }
        }
        if (finishError != null) {
            recordFinishFailure(job, finishError, logger);
        }
        // Emitted last so the entry reports the status the job actually ended on:
        // recordFinishFailure can upgrade 'Completed' to 'Completed with Errors'.
        logTerminalStatus(job, logger);
    }
    
    /**
     * @description Emits one entry per job describing how it ended, at ERROR level for
     *              'Failed' and 'Completed with Errors' and INFO otherwise. This is what gives
     *              subscribers a single, job-level signal; without it a failing job produced only
     *              per-worker errors and an INFO line that read the same whether the job succeeded
     *              or not.
     *
     *              Wrapped in try/catch because logging adapters commonly persist entries with
     *              DML. On the platform-event path this method runs after the terminal job update
     *              in the same transaction, so an escaping adapter failure would roll that update
     *              back and leave the job non-terminal.
     * @param job The job in its terminal state
     * @param logger Logger to emit through; a taggable adapter is re-resolved with scope tags
     */
    public static void logTerminalStatus(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        if (job == null || logger == null) {
            return;
        }
        try {
            String status = job.Status__c;
            Boolean isError = (status == 'Failed' || status == 'Completed with Errors');
            String scopeTag = terminalScopeTag(status);
            
            ICursorBatchLogger target = logger;
            if (scopeTag != null) {
                Set<String> tags = new Set<String>{ scopeTag };
                // The platform failure code travels to the job record inside Error_Message__c,
                // so the terminal entry can carry it without knowing how the job failed.
                String codeTag = CursorBatchLogger.failureCodeTag(
                    (String) job.getPopulatedFieldsAsMap().get('Error_Message__c')
                );
                if (codeTag != null) {
                    tags.add(codeTag);
                }
                target = CursorBatchLogger.withScopeTags(logger, resolveJobTag(job), tags);
            }
            
            String summary = CursorBatchLogger.scoped(terminalScope(status), buildTerminalSummary(job));
            if (isError) {
                target.logError(summary);
            } else {
                target.logInfo(summary);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[CursorBatch] Terminal status logging failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Maps a terminal status to its scope token.
     * @param status CursorBatch_Job__c.Status__c value
     * @return Scope token for the message prefix
     */
    private static String terminalScope(String status) {
        if (status == 'Failed') {
            return CursorBatchLogger.SCOPE_JOB_FAILED;
        }
        if (status == 'Completed with Errors') {
            return CursorBatchLogger.SCOPE_JOB_COMPLETED_WITH_ERRORS;
        }
        if (status == 'Cancelled') {
            return CursorBatchLogger.SCOPE_JOB_CANCELLED;
        }
        return CursorBatchLogger.SCOPE_JOB_COMPLETED;
    }
    
    /**
     * @description Maps a terminal status to its scope tag. Only error outcomes are tagged;
     *              a clean completion needs no filterable marker.
     * @param status CursorBatch_Job__c.Status__c value
     * @return Scope tag, or null when the outcome is not an error
     */
    private static String terminalScopeTag(String status) {
        if (status == 'Failed') {
            return CursorBatchLogger.TAG_JOB_FAILURE;
        }
        if (status == 'Completed with Errors') {
            return CursorBatchLogger.TAG_JOB_PARTIAL_FAILURE;
        }
        return null;
    }
    
    /**
     * @description Builds the terminal summary. Reads through getPopulatedFieldsAsMap so a job
     *              record queried with a narrower field set (or built in memory) cannot throw
     *              while logging; missing fields are simply omitted.
     * @param job The job in its terminal state
     * @return Human-readable one-job summary, with the error text appended when present
     */
    @TestVisible
    private static String buildTerminalSummary(CursorBatch_Job__c job) {
        Map<String, Object> fields = job.getPopulatedFieldsAsMap();
        
        List<String> parts = new List<String>{
            'Job: ' + fields.get('Job_Name__c') + ' (' + job.Id + ')',
            'Status: ' + fields.get('Status__c'),
            'Workers finished: ' + countOrZero(fields.get('Workers_Finished__c')) +
                ', failed: ' + countOrZero(fields.get('Failed_Workers__c')) +
                ' of ' + countOrZero(fields.get('Total_Workers__c'))
        };
        if (fields.get('Total_Records__c') != null) {
            parts.add('Records: ' + fields.get('Total_Records__c'));
        }
        if (fields.get('Total_Worker_Retries__c') != null) {
            parts.add('Worker retries: ' + fields.get('Total_Worker_Retries__c'));
        }
        if (String.isNotBlank((String) fields.get('Query__c'))) {
            parts.add('Query: ' + (String) fields.get('Query__c'));
        }
        
        String summary = String.join(parts, ' | ');
        
        String errorMessage = (String) fields.get('Error_Message__c');
        if (String.isNotBlank(errorMessage)) {
            if (errorMessage.length() > TERMINAL_SUMMARY_ERROR_MAX_LENGTH) {
                errorMessage = errorMessage.left(TERMINAL_SUMMARY_ERROR_MAX_LENGTH) + '... (truncated)';
            }
            summary += '\nError: ' + errorMessage;
        }
        return summary;
    }
    
    private static String countOrZero(Object value) {
        return String.valueOf(value == null ? 0 : value);
    }
    
    /**
     * @description Resolves the tag for a job's log entries from its configured Logger_Tag__c,
     *              falling back to DEFAULT_LOG_TAG. The fallback matters because resolveLogger
     *              skips tagging entirely on a blank tag, which would leave terminal entries
     *              untagged and hard to find.
     * @param job The job being logged
     * @return Tag to apply
     */
    private static String resolveJobTag(CursorBatch_Job__c job) {
        return resolveJobTag(job?.Job_Name__c);
    }
    
    /**
     * @description Resolves the tag for a job's log entries from its configured Logger_Tag__c,
     *              falling back to DEFAULT_LOG_TAG. Exposed so the finalizers apply the same
     *              policy when they emit scoped failures.
     * @param jobName Job name (CursorBatch_Config__mdt.MasterLabel)
     * @return Tag to apply
     */
    public static String resolveJobTag(String jobName) {
        if (String.isBlank(jobName)) {
            return DEFAULT_LOG_TAG;
        }
        try {
            CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig(jobName);
            if (config != null && String.isNotBlank(config.Logger_Tag__c)) {
                return config.Logger_Tag__c;
            }
        } catch (Exception e) {
            // Config lookup must never break logging; the default tag is good enough.
        }
        return DEFAULT_LOG_TAG;
    }
    
    /**
     * @description Returns a logger tagged for a chaining failure so it is distinguishable from
     *              the job's own failure and from a worker failure.
     * @param job The job whose chain failed
     * @param logger Logger the caller would otherwise have used
     * @return Logger to emit the chain failure through
     */
    private static ICursorBatchLogger chainLogger(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        return CursorBatchLogger.withScopeTags(
            logger,
            resolveJobTag(job),
            new Set<String>{ CursorBatchLogger.TAG_JOB_CHAIN_FAILURE }
        );
    }
    
    /**
     * @description Returns a logger tagged for a job-level finish() failure. Exposed because the
     *              callback is invoked from CursorBatchWorker and CursorBatchCoordinator, and both
     *              need the same tag policy: the failure happens once per job, not per worker, and
     *              must not be mistaken for a worker page failure.
     * @param job The job whose finish() callback threw
     * @param logger Logger the caller would otherwise have used
     * @return Logger to emit the finish failure through
     */
    public static ICursorBatchLogger finishFailureLogger(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        return CursorBatchLogger.withScopeTags(
            logger,
            resolveJobTag(job),
            new Set<String>{ CursorBatchLogger.TAG_JOB_FINISH_FAILURE }
        );
    }
    
    /**
     * @description Records a finish-callback failure on the job record. The job row was already
     *              committed as terminal before the callback ran, so without this the failure is
     *              only visible in a debug log. Appends to Error_Message__c rather than
     *              overwriting so a worker error captured during event handling is preserved, and
     *              only upgrades a clean 'Completed' status — 'Failed' and 'Completed with Errors'
     *              already signal a problem and must not be downgraded.
     *              Records only; it deliberately does not log. Every path that returns a finish()
     *              exception has already logged it with a stack trace, and logTerminalStatus
     *              reports the resulting status right after, so logging here would duplicate both.
     *              Wrapped in try/catch so a failure to record can never break the platform-event
     *              transaction.
     * @param job The completed job record (mutated in memory so the parent mirror stays in sync)
     * @param finishError The exception thrown by the finish callback
     * @param logger Logger instance for error reporting
     */
    private static void recordFinishFailure(CursorBatch_Job__c job, Exception finishError, ICursorBatchLogger logger) {
        if (job == null || job.Id == null) {
            return;
        }
        try {
            String finishMessage = 'finish() failed: ' + CursorBatchLogger.formatExceptionMessage(finishError);
            String combined = String.isBlank(job.Error_Message__c)
                ? finishMessage
                : job.Error_Message__c + '\n\n' + finishMessage;
            if (combined.length() > ERROR_MESSAGE_MAX_LENGTH) {
                combined = combined.left(ERROR_MESSAGE_MAX_LENGTH);
            }
            
            CursorBatch_Job__c jobUpdate = new CursorBatch_Job__c(Id = job.Id, Error_Message__c = combined);
            Boolean statusUpgraded = (job.Status__c == 'Completed');
            if (statusUpgraded) {
                jobUpdate.Status__c = 'Completed with Errors';
            }
            update jobUpdate;
            
            job.Error_Message__c = combined;
            if (statusUpgraded) {
                // The parent was mirrored before the callback ran, so it still reads 'Completed'.
                job.Status__c = 'Completed with Errors';
                updateParentLastStatus(job, logger);
            }
        } catch (Exception e) {
            logger.logException('CursorBatchCompletionHandler: Failed to record finish() failure on job ' + job.Job_Name__c, e);
        }
    }
    
    /**
     * @description Best-effort write of the terminal Status__c onto the linked
     *              CursorBatch_Job_Parent__c.Last_Job_Status__c. No-op when the job has no
     *              parent. Wrapped in try/catch so parent-side FLS, sharing, or validation
     *              issues never bubble up and block the finish callback.
     * @param job The completed job record (must have Job_Parent__c populated by the selector)
     * @param logger Logger instance for error reporting
     */
    private static void updateParentLastStatus(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        if (job == null || job.Job_Parent__c == null) {
            return;
        }
        try {
            update new CursorBatch_Job_Parent__c(
                Id = job.Job_Parent__c,
                Last_Job_Status__c = job.Status__c
            );
        } catch (Exception e) {
            logger.logException('CursorBatchCompletionHandler: Failed to update parent Last_Job_Status__c for ' + job.Job_Name__c, e);
        }
    }
    
    /**
     * @description Internal implementation of the 4-path finish callback logic.
     * @param job The completed job record
     * @param logger Logger instance for routing
     * @return The exception raised by the selected path, or null when it completed
     */
    private static Exception routeFinishCallbackInternal(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig(job.Job_Name__c);
        
        // Path 1: Chain_To_Job is set - chain to another CursorJob by name
        if (config != null && String.isNotBlank(config.Chain_To_Job__c)) {
            try {
                CursorJob.run(config.Chain_To_Job__c);
                logger.logInfo('CursorBatchCompletionHandler: Chained to job ' + config.Chain_To_Job__c);
            } catch (Exception e) {
                chainLogger(job, logger).logException(CursorBatchLogger.scoped(
                    CursorBatchLogger.SCOPE_JOB_CHAIN_FAILED,
                    'Job: ' + job.Job_Name__c + ' (' + job.Id + ') failed to chain to job ' + config.Chain_To_Job__c
                ), e);
                return e;
            }
            return null;
        }
        
        // Path 2: Chain_To_Class is set - invoke the chain directly
        if (config != null && String.isNotBlank(config.Chain_To_Class__c)) {
            return invokeChain(config.Chain_To_Class__c, config.Chain_To_Method__c, job, logger);
        }
        
        // Path 3: CursorJob (SOQL with query builder, or CSV) - call worker.finish()
        if (config != null && (String.isNotBlank(config.Query_Builder_Class__c) || config.Processing_Type__c == CursorBatchContext.PROCESSING_TYPE_CSV)) {
            String workerClass = config.Worker_Class__c;
            if (String.isNotBlank(workerClass)) {
                return CursorBatchWorker.invokeFinishCallback(workerClass, job, logger);
            }
            return null;
        }
        
        // Path 4: Custom coordinator - call coordinator.finish()
        return CursorBatchCoordinator.invokeFinishCallback(job.Coordinator_Class__c, job.Job_Name__c, job, logger);
    }
    
    /**
     * @description Invokes the chain class/method using Callable interface.
     * @param chainClass The class to chain to
     * @param chainMethod The method to call (defaults to 'run' if blank)
     * @param job The completed job record (passed for context)
     * @param logger Logger for error reporting
     * @return The exception thrown by the chain, or null when it completed (or was skipped
     *         because the class could not be resolved)
     */
    private static Exception invokeChain(String chainClass, String chainMethod, CursorBatch_Job__c job, ICursorBatchLogger logger) {
        String methodToCall = String.isNotBlank(chainMethod) ? chainMethod : 'run';
        
        try {
            Type chainType = Type.forName(chainClass);
            if (chainType == null) {
                logger.logError('CursorBatchCompletionHandler: Chain class not found: ' + chainClass);
                return null;
            }
            
            Object instance = chainType.newInstance();
            
            // Try Callable interface first
            if (instance instanceof Callable) {
                Callable callableInstance = (Callable) instance;
                callableInstance.call(methodToCall, new Map<String, Object>{ 'jobRecord' => job });
                logger.logInfo('CursorBatchCompletionHandler: Chained to ' + chainClass + '.' + methodToCall + '()');
                return null;
            }
            
            // Fallback: Check if it's a CursorJob chaining to another CursorJob
            // This handles CursorJob.run('NextJobName') pattern
            if (chainClass == 'CursorJob' && methodToCall == 'run') {
                // For CursorJob, we need the job name - this scenario requires explicit config
                logger.logError('CursorBatchCompletionHandler: Chain to CursorJob requires Callable implementation in ' + chainClass);
                return null;
            }
            
            logger.logError('CursorBatchCompletionHandler: Chain class ' + chainClass + ' must implement Callable interface');
            
        } catch (Exception e) {
            chainLogger(job, logger).logException(CursorBatchLogger.scoped(
                CursorBatchLogger.SCOPE_JOB_CHAIN_FAILED,
                'Job: ' + job.Job_Name__c + ' (' + job.Id + ') failed invoking chain ' +
                    chainClass + '.' + methodToCall + '()'
            ), e);
            return e;
        }
        return null;
    }
}