/**
 * @description Handles CursorBatch_Coordinator__e Platform Events. Instantiates and enqueues
 *              coordinator queueables using dynamic instantiation. This ensures the coordinator
 *              runs as the dedicated trigger user (from PlatformEventSubscriberConfig), which is
 *              required for cursor access by workers running as the same user.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 * @see CursorBatchWorkerTriggerHandler
 */
public without sharing class CursorBatchCoordinatorTriggerHandler {
    
    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor initializing the logger.
     */
    public CursorBatchCoordinatorTriggerHandler() {
        this.logger = CursorBatchLogger.getDefault();
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
