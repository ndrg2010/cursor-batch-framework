/**
 * @description Handles CursorBatch_Coordinator__e Platform Events. Instantiates and enqueues
 *              coordinator queueables using dynamic instantiation. This ensures the coordinator
 *              runs as the dedicated trigger user (from PlatformEventSubscriberConfig), which is
 *              required for cursor access by workers running as the same user.
 *
 *              Error handling: any exception from class resolution, instantiation, or
 *              System.enqueueJob is caught in processEvent. Salesforce's PE retry is bypassed
 *              by design (the catch does not re-throw), so the corresponding CursorBatch_Job__c
 *              row would otherwise sit in Preparing forever. To prevent that, the catch now
 *              invokes markJobAsFailed which flips the row to Failed with the original
 *              exception captured in Error_Message__c -- see SL-146 / the stuck-watchdog
 *              ticket for the root-cause writeup.
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
     *              so swallowed exceptions and write-back failures are recoverable from
     *              LogEntry__c after the transaction ends.
     */
    public CursorBatchCoordinatorTriggerHandler() {
        this.logger = CursorBatchLogger.resolveLogger(LOG_TAG);
    }
    
    /**
     * @description Handles incoming Platform Events by creating and enqueueing coordinators.
     * @param events CursorBatch_Coordinator__e events from the Platform Event trigger
     */
    public void handle(List<CursorBatch_Coordinator__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        for (CursorBatch_Coordinator__e evt : events) {
            processEvent(evt);
        }
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
            markJobAsFailed(evt.Job_Record_Id__c, evt.Job_Name__c, e);
        }
    }

    /**
     * @description Best-effort write-back invoked from the catch in processEvent. Flips the
     *              corresponding CursorBatch_Job__c row to Status__c='Failed' with the original
     *              exception's type, message, and stack trace recorded in Error_Message__c, and
     *              stamps Completed_At__c. Without this, the row would sit in Preparing
     *              indefinitely with no surface-level error -- the PE retry mechanism is
     *              already bypassed by this handler's swallow-and-log pattern, so without
     *              writing back, ops have no visible record of why the job is stuck.
     *
     *              Wrapped in its own try/catch so a failure during the write-back (e.g. the
     *              job record was already deleted, or DML governor limits were hit by the
     *              caller before this point) does not mask the original exception. The catch
     *              here only logs to Nebula -- by design, this entire method must be
     *              non-throwing.
     *
     * @param jobRecordIdString The CursorBatch_Job__c Id carried on the platform event.
     * @param jobName The job's logical name, for log context only.
     * @param originalException The exception caught in processEvent that triggered this call.
     */
    private void markJobAsFailed(String jobRecordIdString, String jobName, Exception originalException) {
        Id jobId;
        try {
            jobId = Id.valueOf(jobRecordIdString);
        } catch (Exception idEx) {
            logger.logError(
                'CursorBatchCoordinatorTriggerHandler: Cannot mark job "' + jobName +
                '" as Failed -- invalid Job_Record_Id__c on the platform event: "' +
                jobRecordIdString + '"'
            );
            return;
        }
        try {
            CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobId);
            if (jobRecord == null) {
                logger.logError(
                    'CursorBatchCoordinatorTriggerHandler: Cannot mark job "' + jobName +
                    '" as Failed -- no CursorBatch_Job__c found for Id ' + jobId
                );
                return;
            }
            jobRecord.Status__c = 'Failed';
            jobRecord.Error_Message__c = buildHandlerFailureMessage(originalException);
            jobRecord.Completed_At__c = System.now();
            update jobRecord;
        } catch (Exception writebackEx) {
            logger.logException(
                'CursorBatchCoordinatorTriggerHandler: Write-back to mark CursorBatch_Job__c ' + jobId +
                ' (' + jobName + ') as Failed itself threw an exception; original failure was: ' +
                originalException.getTypeName() + ' / ' + originalException.getMessage(),
                writebackEx
            );
        }
    }

    /**
     * @description Builds the multi-line Error_Message__c body recorded by markJobAsFailed.
     *              Prefixed with a stable substring so ops searches and tests can recognise
     *              handler-caught failures distinctly from worker errors. Capped at 32,768
     *              characters to match the Error_Message__c field length.
     */
    private static String buildHandlerFailureMessage(Exception ex) {
        String message = 'CursorBatchCoordinatorTriggerHandler caught an exception while dispatching the coordinator.\n\n' +
            'Type: ' + ex.getTypeName() + '\n' +
            'Message: ' + ex.getMessage();
        String stack = ex.getStackTraceString();
        if (String.isNotBlank(stack)) {
            message += '\n\nStack trace:\n' + stack;
        }
        if (message.length() > 32768) {
            return message.substring(0, 32768);
        }
        return message;
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
     *
     *              The routeFinishCallback invocation at the end is wrapped in its own
     *              try/catch by design. Without that wrapper, a throw from the completion
     *              handler (governor limit hit, future regression in the unlocked package,
     *              bad Coordinator_Class__c metadata, etc.) would escape this method,
     *              propagate to processEvent's catch, and trigger markJobAsFailed -- which
     *              re-queries the row and OVERWRITES Error_Message__c with the generic
     *              handler-dispatch blurb, destroying the CSV diagnostic that callers
     *              actually need. By the time we call routeFinishCallback the row is
     *              already committed to Failed with the verbatim middleware message, so
     *              the callback is strictly best-effort downstream cleanup.
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
            try {
                CursorBatchCompletionHandler.routeFinishCallback(jobRecord, logger);
            } catch (Exception callbackEx) {
                // Must not propagate -- see method docblock. The row is already correctly
                // marked Failed with the CSV detail and any subsequent overwrite would lose
                // that detail.
                logger.logException(
                    'CursorBatchCoordinatorTriggerHandler: routeFinishCallback threw after a CSV_Error ' +
                    'write-back for job ' + jobId + '; suppressing so the CSV middleware error ' +
                    'detail on Error_Message__c is preserved.',
                    callbackEx
                );
            }
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