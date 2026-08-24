/**
 * @description Handles CursorBatch_Coordinator__e Platform Events. Instantiates and enqueues
 *              coordinator queueables using dynamic instantiation. This ensures the coordinator
 *              runs as the dedicated trigger user (from PlatformEventSubscriberConfig), which is
 *              required for cursor access by workers running as the same user.
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
 *              handlers (this class and CursorBatchWorkerTriggerHandler) share the same
 *              LOG_TAG so ops can pull "anything that went wrong during PE dispatch" in a
 *              single LogEntry__c tag filter rather than having to OR two separate tags.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 * @see CursorBatchWorkerTriggerHandler
 * @see CursorBatchLogger
 * @see CursorBatchLoggerAdapter
 */
public without sharing class CursorBatchCoordinatorTriggerHandler {
    
    /**
     * @description Shared tag attached to every LogEntry__c emitted from PE dispatch handlers.
     *              Kept identical in CursorBatchWorkerTriggerHandler so ops dashboards can
     *              filter both subscribers' logs with a single tag clause. @TestVisible so the
     *              pinned-value test can catch silent drift before LogEntry__c queries miss
     *              data.
     */
    @TestVisible
    private static final String LOG_TAG = 'CursorBatch Dispatch';

    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor. Routes log output through Nebula Logger (via the
     *              framework's resolveLogger convention) instead of the System.debug default,
     *              so swallowed exceptions are recoverable from LogEntry__c after the
     *              transaction ends.
     */
    public CursorBatchCoordinatorTriggerHandler() {
        this.logger = CursorBatchLogger.resolveLogger(LOG_TAG);
    }
    
    /**
     * @description Handles incoming Platform Events by creating and enqueueing coordinators.
     *
     *              Guarded by CursorBatchReplayGuard for the same reason as the worker channel.
     *              This channel was not the one the event bus rewound on 2026-08-24, but the
     *              exposure is the same shape and worse per event: a coordinator event carries a
     *              pre-created job record Id, so a redelivered one would re-run the coordinator
     *              against an existing job and fan out the entire job a second time.
     * @param events CursorBatch_Coordinator__e events from the Platform Event trigger
     */
    public void handle(List<CursorBatch_Coordinator__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        Map<String, CursorBatch_Coordinator__e> eventsByKey = new Map<String, CursorBatch_Coordinator__e>();
        List<CursorBatchReplayGuard.Candidate> candidates = new List<CursorBatchReplayGuard.Candidate>();
        for (CursorBatch_Coordinator__e evt : events) {
            CursorBatchReplayGuard.Candidate candidate;
            try {
                candidate = buildCandidate(evt);
            } catch (Exception e) {
                logger.logException('CursorBatchCoordinatorTriggerHandler: Could not identify event for job "' +
                    evt.Job_Name__c + '"; dispatching unguarded', e);
            }
            if (candidate == null) {
                processEvent(evt);
                continue;
            }
            eventsByKey.put(candidate.eventKey, evt);
            candidates.add(candidate);
        }
        
        CursorBatchReplayGuard.Verdict verdict = new CursorBatchReplayGuard(
            CursorBatchReplayGuard.CHANNEL_COORDINATOR, logger
        ).withTerminalJobGate(true).admit(candidates);
        
        for (CursorBatchReplayGuard.Candidate candidate : candidates) {
            // claim(), not a set lookup: candidates retains both entries when one batch carries
            // the same event twice, and dispatching a coordinator twice re-fans-out a whole job.
            if (verdict.claim(candidate.eventKey)) {
                processEvent(eventsByKey.get(candidate.eventKey));
            } else if (CursorBatchReplayGuard.REASON_STALE == verdict.blockedReasonsByKey.get(candidate.eventKey)) {
                failStaleJob(candidate);
            }
        }
    }
    
    /**
     * @description Marks a job Failed when the guard rejected its coordinator event as stale.
     *
     *              The coordinator never ran, so the job would otherwise sit in Preparing
     *              forever. That is worse than a visible failure: isJobAlreadyRunning treats
     *              Preparing as running, so every future submission of that job name would
     *              silently return null and the job would never run again.
     *
     *              Only REASON_STALE is reconciled. JOB_TERMINAL needs nothing, JOB_MISSING has
     *              no record to write, and DUPLICATE means the coordinator was already dispatched.
     *              Mirrors handleCsvError, which is the framework's existing shape for "this job
     *              cannot proceed".
     * @param candidate The rejected coordinator event
     */
    private void failStaleJob(CursorBatchReplayGuard.Candidate candidate) {
        if (candidate.jobRecordId == null) {
            return;
        }
        try {
            CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(candidate.jobRecordId);
            if (jobRecord == null || jobRecord.Completed_At__c != null) {
                return;
            }
            jobRecord.Status__c = 'Failed';
            jobRecord.Error_Message__c = 'Replay guard rejected the coordinator event as stale: it was ' +
                'published ' + candidate.publishedAt + ' and exceeded Max_Event_Age_Minutes__c. ' +
                'The job did not start.';
            jobRecord.Completed_At__c = System.now();
            jobRecord.Total_Workers__c = jobRecord.Total_Workers__c ?? 0;
            jobRecord.Workers_Finished__c = jobRecord.Workers_Finished__c ?? 0;
            jobRecord.Failed_Workers__c = jobRecord.Failed_Workers__c ?? 0;
            update jobRecord;
            CursorBatchCompletionHandler.routeFinishCallback(jobRecord, logger);
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinatorTriggerHandler: Could not fail the job whose ' +
                'coordinator event was rejected as stale, so it may stay stuck in Preparing', e);
        }
    }
    
    /**
     * @description Normalizes a coordinator event into a guard candidate.
     *
     *              Job_Name__c is not a job name on the CSV callback paths -- CSV_Ready carries
     *              the csvCursorQuery there and CSV_Error carries an error message -- so it is
     *              passed through as-is and the guard falls back to the job record's own
     *              Job_Name__c when it does not resolve to a config.
     * @param evt CursorBatch_Coordinator__e event
     * @return Candidate for CursorBatchReplayGuard.admit, or null when the event lacks the fields
     *         to identify itself
     */
    private CursorBatchReplayGuard.Candidate buildCandidate(CursorBatch_Coordinator__e evt) {
        if (String.isBlank(evt.Job_Record_Id__c) || String.isBlank(evt.Coordinator_Class__c)) {
            return null;
        }
        String eventKey = CursorBatchReplayGuard.buildCoordinatorKey(
            evt.Job_Record_Id__c, evt.Coordinator_Class__c
        );
        CursorBatchReplayGuard.Candidate candidate = new CursorBatchReplayGuard.Candidate(
            eventKey, evt.Job_Record_Id__c, evt.Job_Name__c, evt.CreatedDate
        );
        Object replayId = evt.get('ReplayId');
        candidate.replayId = replayId != null ? String.valueOf(replayId) : null;
        return candidate;
    }
    
    /**
     * @description Processes a single event by instantiating and enqueueing a coordinator.
     *              Routes CSV_Ready callbacks to CursorBatchCsvCallbackCoordinator and
     *              CSV_Error callbacks to failure handling.
     * @param evt CursorBatch_Coordinator__e event containing coordinator parameters
     */
    private void processEvent(CursorBatch_Coordinator__e evt) {
        try {
            String coordinatorClassName = evt.Coordinator_Class__c;
            
            if (String.isBlank(coordinatorClassName)) {
                logger.logError('CursorBatchCoordinatorTriggerHandler: Coordinator class name not specified for job "' + evt.Job_Name__c + '"');
                return;
            }
            
            if (coordinatorClassName == 'CSV_Ready') {
                handleCsvCallback(evt);
                return;
            }
            
            if (coordinatorClassName == 'CSV_Error') {
                handleCsvError(evt);
                return;
            }
            
            CursorBatchCoordinator coordinator = createCoordinatorInstance(
                coordinatorClassName, 
                evt.Job_Name__c, 
                evt.Job_Record_Id__c
            );
            
            if (coordinator == null) {
                return;
            }
            
            enqueueCoordinator(coordinator, evt);
            
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinatorTriggerHandler: Error processing event for job "' + evt.Job_Name__c + '"', e);
        }
    }
    
    /**
     * @description Handles a CSV_Ready callback from the middleware. The middleware has finished
     *              indexing the file and the csvCursorQuery is available for pagination. Only
     *              processes jobs in Extracting File status (set by executeCsvInit). Computes
     *              query duration as elapsed time from Started_At__c to event CreatedDate.
     * @param evt Platform Event where Job_Name__c contains the csvCursorQuery
     */
    private void handleCsvCallback(CursorBatch_Coordinator__e evt) {
        String csvCursorQuery = evt.Job_Name__c;
        Id jobId;
        try {
            jobId = Id.valueOf(evt.Job_Record_Id__c);
        } catch (Exception e) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: CSV_Ready with invalid job record ID: ' + evt.Job_Record_Id__c);
            return;
        }
        
        logger.logInfo('CursorBatchCoordinatorTriggerHandler: CSV_Ready callback for job record ' +
            jobId + ', csvCursorQuery=' + csvCursorQuery);
        
        // Lock the job record to prevent duplicate callback processing (TOCTOU guard).
        List<CursorBatch_Job__c> jobs = [
            SELECT Id, Status__c, Cursor_Query_Id__c, Started_At__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobId
            FOR UPDATE
        ];
        if (jobs.isEmpty()) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: CSV_Ready callback for missing job record: ' + jobId);
            return;
        }
        
        CursorBatch_Job__c jobRecord = jobs[0];
        if (jobRecord.Status__c != 'Extracting File') {
            logger.logInfo('CursorBatchCoordinatorTriggerHandler: Ignoring CSV_Ready for job ' +
                jobId + ' (status=' + jobRecord.Status__c + ')');
            return;
        }
        
        Long queryDurationMs = 0;
        if (jobRecord.Started_At__c != null) {
            queryDurationMs = evt.CreatedDate.getTime() - jobRecord.Started_At__c.getTime();
        }
        
        CursorBatchCsvCallbackCoordinator coordinator = new CursorBatchCsvCallbackCoordinator(csvCursorQuery, queryDurationMs);
        coordinator.setJobRecordId(jobId);
        
        if (!Test.isRunningTest()) {
            System.enqueueJob(coordinator);
        }
    }
    
    /**
     * @description Handles a CSV_Error callback from the middleware. Marks the job as Failed
     *              with the error message carried in Job_Name__c.
     * @param evt Platform Event where Job_Name__c contains the error message
     */
    private void handleCsvError(CursorBatch_Coordinator__e evt) {
        String errorMessage = evt.Job_Name__c;
        Id jobId;
        try {
            jobId = Id.valueOf(evt.Job_Record_Id__c);
        } catch (Exception e) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: CSV_Error with invalid job record ID: ' + evt.Job_Record_Id__c);
            return;
        }
        
        logger.logError('CursorBatchCoordinatorTriggerHandler: CSV_Error for job ' + jobId + ': ' + errorMessage);
        
        CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobId);
        if (jobRecord != null) {
            jobRecord.Status__c = 'Failed';
            jobRecord.Error_Message__c = 'CSV middleware error: ' + errorMessage;
            jobRecord.Completed_At__c = System.now();
            update jobRecord;
            CursorBatchCompletionHandler.routeFinishCallback(jobRecord, logger);
        }
    }
    
    /**
     * @description Creates a coordinator instance via reflection and initializes it with job context.
     * @param className Fully qualified API name of the coordinator class
     * @param jobName Job name for initialization
     * @param jobRecordId ID of the pre-created job record
     * @return Initialized CursorBatchCoordinator instance, or null on error
     */
    private CursorBatchCoordinator createCoordinatorInstance(String className, String jobName, String jobRecordId) {
        Type coordinatorType = Type.forName(className);
        if (coordinatorType == null) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: Coordinator class not found: ' + className);
            return null;
        }
        
        Object instance = coordinatorType.newInstance();
        if (!(instance instanceof CursorBatchCoordinator)) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: Class "' + className + '" must extend CursorBatchCoordinator');
            return null;
        }
        
        CursorBatchCoordinator coordinator = (CursorBatchCoordinator) instance;
        coordinator.initializeJobName(jobName);
        coordinator.setJobRecordId(Id.valueOf(jobRecordId));
        
        return coordinator;
    }
    
    /**
     * @description Enqueues the coordinator, optionally with a delay.
     * @param coordinator Initialized coordinator instance
     * @param evt Platform Event containing delay configuration
     */
    private void enqueueCoordinator(CursorBatchCoordinator coordinator, CursorBatch_Coordinator__e evt) {
        Integer delayMinutes = evt.Delay_Minutes__c != null ? Integer.valueOf(evt.Delay_Minutes__c) : null;
        
        if (!Test.isRunningTest()) {
            if (delayMinutes != null && delayMinutes > 0) {
                System.enqueueJob(coordinator, delayMinutes);
                logger.logInfo('CursorBatchCoordinatorTriggerHandler: Enqueued ' + evt.Coordinator_Class__c + 
                    ' for job "' + evt.Job_Name__c + '" with ' + delayMinutes + ' min delay');
            } else {
                System.enqueueJob(coordinator);
                logger.logInfo('CursorBatchCoordinatorTriggerHandler: Enqueued ' + evt.Coordinator_Class__c + 
                    ' for job "' + evt.Job_Name__c + '"');
            }
        }
    }
}
