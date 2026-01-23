/**
 * @description Abstract base class for cursor-based batch coordinators. Executes a query,
 *              creates a Database.Cursor, extracts its queryId for cross-transaction access,
 *              and publishes Platform Events to fan out parallel workers. Platform Events
 *              are used because queueable-to-queueable chaining is limited to one job.
 * 
 *              The coordinator itself is routed through a Platform Event (CursorBatch_Coordinator__e)
 *              to ensure it runs as the dedicated trigger user. This is required because
 *              Database.Cursor is only accessible by the user who created it, and workers
 *              run as the trigger user.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchWorkerTriggerHandler
 * @see CursorBatchCoordinatorTriggerHandler
 */
public abstract without sharing class CursorBatchCoordinator implements Queueable, Database.AllowsCallouts {
    
    private static final Integer DEFAULT_WORKER_COUNT = 50;
    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer PE_BATCH_SIZE = 200;
    
    // Shared constants for retry logic
    public static final Integer DEFAULT_COORDINATOR_MAX_RETRIES = 3;
    public static final Integer DEFAULT_WORKER_MAX_RETRIES = 3;
    public static final Integer DEFAULT_WORKER_RETRY_DELAY = 1;
    public static final Integer MAX_DELAY_MINUTES = 10;
    
    protected String jobName;
    protected ICursorBatchLogger logger;
    
    /**
     * @description Job record ID for this coordinator instance. Set by submit() for fresh jobs
     *              or by setJobRecordId() for retry scenarios (called by finalizer).
     */
    private Id jobRecordId;
    
    /**
     * @description Protected no-arg constructor for reflection-based instantiation. When using
     *              this constructor, jobName must be set via initializeJobName() before finish().
     */
    protected CursorBatchCoordinator() {
        this.logger = CursorBatchLogger.getDefault();
    }
    
    /**
     * @description Constructs coordinator with job name for configuration lookup. Uses the
     *              default CursorBatchLogger; call setLogger() in subclass to customize.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     */
    protected CursorBatchCoordinator(String jobName) {
        this();
        this.jobName = jobName;
    }
    
    /**
     * @description Initializes the job name after reflection-based instantiation. Called by
     *              CursorBatchCompletionHandler when invoking the finish() callback.
     * @param jobName Job identifier from the job record
     */
    public void initializeJobName(String jobName) {
        this.jobName = jobName;
    }
    
    /**
     * @description Sets the job record ID for retry scenarios. Called by the finalizer when
     *              re-enqueueing a coordinator after a failure.
     * @param jobId ID of existing CursorBatch_Job__c record to reuse
     */
    public void setJobRecordId(Id jobId) {
        this.jobRecordId = jobId;
    }
    
    /**
     * @description Sets a custom logger implementation. Call from subclass constructor to
     *              integrate with Nebula Logger, Pharos, or other logging frameworks.
     * @param logger Custom ICursorBatchLogger implementation
     */
    @TestVisible
    protected void setLogger(ICursorBatchLogger logger) {
        this.logger = logger;
    }
    
    /**
     * @description Submits the coordinator job. Creates the job record and publishes a Platform Event
     *              to route execution through the trigger, ensuring the coordinator runs as the
     *              dedicated trigger user. This is required for cursor access by workers.
     *              By default, checks both CursorBatch_Job__c records and AsyncApexJob to prevent 
     *              duplicate jobs. Override isJobAlreadyRunning() to customize duplicate detection logic.
     */
    public void submit() {
        if (!isJobAlreadyRunning(jobName)) {
            createJobRecord();
            publishCoordinatorEvent(null);
        }
    }
    
    /**
     * @description Submits the coordinator job with a delay. Creates the job record and publishes a
     *              Platform Event to route execution through the trigger with the specified delay.
     * @param delayMinutes Number of minutes to delay before execution (1-10 supported by platform)
     */
    public void submitWithDelay(Integer delayMinutes) {
        if (!isJobAlreadyRunning(jobName)) {
            createJobRecord();
            publishCoordinatorEvent(delayMinutes);
        }
    }
    
    /**
     * @description Publishes a CursorBatch_Coordinator__e Platform Event to trigger coordinator
     *              execution. The trigger runs as the dedicated user configured in the
     *              PlatformEventSubscriberConfig, ensuring the cursor is created by that user.
     * @param delayMinutes Optional delay in minutes for deferred execution; null for immediate
     */
    private void publishCoordinatorEvent(Integer delayMinutes) {
        CursorBatch_Coordinator__e evt = new CursorBatch_Coordinator__e(
            Job_Name__c = jobName,
            Coordinator_Class__c = CursorBatchContext.getClassName(this),
            Job_Record_Id__c = jobRecordId,
            Delay_Minutes__c = delayMinutes
        );
        
        Database.SaveResult result = EventBus.publish(evt);
        if (!result.isSuccess()) {
            for (Database.Error err : result.getErrors()) {
                logger.logError('CursorBatchCoordinator: Failed to publish coordinator event: ' + err.getMessage());
            }
        } else {
            String delayMsg = delayMinutes != null ? ' with ' + delayMinutes + ' min delay' : '';
            logger.logInfo('CursorBatchCoordinator: Published coordinator event for ' + jobName + delayMsg);
        }
    }
    
    /**
     * @description Executes the coordinator: runs query, creates cursor, extracts queryId, and
     *              fans out workers via Platform Events.
     * @param ctx Queueable context (unused; required by Queueable interface)
     * @throws CursorBatchException When no active config is found or job record is missing
     */
    public void execute(QueueableContext ctx) {
        try {
            // Fetch the job record created by submit() or set by finalizer
            CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobRecordId);
            if (jobRecord == null) {
                throw new CursorBatchException('Job record not found: ' + jobRecordId);
            }
            
            CursorBatch_Config__mdt config = getConfig(jobName);
            if (config == null) {
                throw new CursorBatchException('No active config found for job: ' + jobName);
            }
            
            Integer workerCount = getConfigIntOrDefault(config.Parallel_Count__c, DEFAULT_WORKER_COUNT);
            Integer pageSize = getConfigIntOrDefault(config.Page_Size__c, DEFAULT_PAGE_SIZE);
            
            // On retry, use stored query from job record (buildQuery() may fail if coordinator
            // state wasn't reconstructed). Fresh runs have Query__c set by createJobRecord().
            String query = String.isNotBlank(jobRecord.Query__c) 
                ? jobRecord.Query__c 
                : buildQuery();
            logger.logInfo('CursorBatchCoordinator query for ' + jobName + ': ' + query);
            
            // Attach finalizer BEFORE the cursor query so it can handle timeouts
            // Pass query so it's available in failure logs (DML would rollback on uncatchable exception)
            attachFinalizer(jobRecord.Id, query);
            
            Long queryStartTime = System.currentTimeMillis();
            Database.Cursor dbCursor = Database.getCursor(query);
            Integer totalRecords = dbCursor.getNumRecords();
            Long queryDurationMs = System.currentTimeMillis() - queryStartTime;
            logger.logInfo('CursorBatchCoordinator cursor query took ' + queryDurationMs + 'ms, totalRecords: ' + totalRecords);
            
            if (totalRecords == 0) {
                logger.logInfo('No records to process for ' + jobName + ', exiting.');
                jobRecord.Status__c = 'Completed';
                jobRecord.Completed_At__c = System.now();
                jobRecord.Total_Records__c = 0;
                jobRecord.Query_Duration_Ms__c = queryDurationMs;
                update jobRecord;
                onComplete();
                finish(jobRecord);
                return;
            }
            
            // Calculate workers needed based on pageSize - each worker handles one page worth of records
            // e.g., 50 records / 15 pageSize = 4 workers (3 process 15 each, last gets 5)
            Integer minWorkersNeeded = (Integer) Math.ceil((Decimal) totalRecords / pageSize);
            Integer actualWorkerCount = Math.min(minWorkersNeeded, workerCount);
            
            // When not constrained by config, use pageSize per worker for optimal batching
            // When constrained, distribute evenly across available workers
            Integer recordsPerWorker = (actualWorkerCount >= minWorkersNeeded) 
                ? pageSize 
                : (Integer) Math.ceil((Decimal) totalRecords / actualWorkerCount);
            
            // Extract queryId from cursor for cross-transaction access
            String cursorQueryId = extractCursorQueryId(dbCursor);
            logger.logInfo('CursorBatchCoordinator extracted cursor queryId: ' + cursorQueryId);
            
            // Fan out workers and get accurate batch count (calculated during actual worker assignment)
            Integer actualTotalBatches = fanOutWithPlatformEvents(cursorQueryId, jobRecord.Id, actualWorkerCount, recordsPerWorker, totalRecords, pageSize);
            
            logger.logInfo('Distributing ' + totalRecords + ' records across ' + actualWorkerCount + ' workers (' + actualTotalBatches + ' batches) via Platform Events');
            
            // Update job record with cursor details and Processing status (using accurate batch count)
            updateJobRecordAfterCursor(jobRecord, actualWorkerCount, cursorQueryId, totalRecords, queryDurationMs, actualTotalBatches);
            
            onComplete();
            
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinator error for ' + jobName, e);
            throw e;
        }
    }
    
    /**
     * @description Creates the job record with Preparing status. Called from submit() to ensure
     *              the record is committed before the queueable executes, surviving any rollback.
     *              Writes the query immediately so it's visible before the cursor returns.
     */
    private void createJobRecord() {
        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = jobName,
            Status__c = 'Preparing',
            Coordinator_Class__c = CursorBatchContext.getClassName(this),
            Started_At__c = System.now(),
            Query__c = buildQuery(),
            Total_Cursor_Retries__c = 0,
            Total_Workers__c = 0,
            Total_Batches__c = 0,
            Completed_Batches__c = 0,
            Workers_Finished__c = 0,
            Failed_Workers__c = 0,
            Total_Worker_Retries__c = 0
        );
        insert job;
        this.jobRecordId = job.Id;
        logger.logInfo('CursorBatchCoordinator created job record in submit: ' + job.Id);
    }
    
    /**
     * @description Attaches the coordinator finalizer to handle cursor query failures.
     *              Handles the case where System.attachFinalizer() is not allowed outside
     *              a valid Queueable execution context (e.g., direct test calls).
     * @param jobRecordId ID of the job record for the finalizer
     * @param query The SOQL query string for logging in failure scenarios
     */
    private void attachFinalizer(Id jobRecordId, String query) {
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecordId,
            jobName,
            CursorBatchContext.getClassName(this),
            logger,
            query
        );
        try {
            System.attachFinalizer(finalizer);
            logger.logInfo('CursorBatchCoordinator attached finalizer for job: ' + jobRecordId);
        } catch (System.HandledException e) {
            // System.attachFinalizer is not allowed outside a Queueable context
            // This can happen in tests that call execute() directly instead of via submit()
            logger.logInfo('CursorBatchCoordinator: Finalizer not attached (not in Queueable context)');
        }
    }
    
    /**
     * @description Updates the job record after successful cursor creation.
     * @param jobRecord Job record to update
     * @param workerCount Total number of workers for this job
     * @param cursorQueryId The queryId for cursor reconstruction
     * @param totalRecords Total number of records in the cursor query result set
     * @param queryDurationMs Time in milliseconds to execute the cursor query
     * @param totalBatches Expected total number of batch/page executions
     */
    private void updateJobRecordAfterCursor(
        CursorBatch_Job__c jobRecord, 
        Integer workerCount, 
        String cursorQueryId, 
        Integer totalRecords,
        Long queryDurationMs,
        Integer totalBatches
    ) {
        jobRecord.Total_Workers__c = workerCount;
        jobRecord.Total_Records__c = totalRecords;
        jobRecord.Cursor_Query_Id__c = cursorQueryId;
        jobRecord.Query_Duration_Ms__c = queryDurationMs;
        jobRecord.Total_Batches__c = totalBatches;
        jobRecord.Status__c = 'Processing';
        update jobRecord;
        logger.logInfo('CursorBatchCoordinator updated job to Processing status: ' + jobRecord.Id);
    }
    
    /**
     * @description Extracts the queryId from a Database.Cursor for cross-transaction storage.
     *              The queryId can be used to reconstruct the cursor via JSON deserialization.
     * @param cursor The Database.Cursor to extract the queryId from
     * @return The queryId string that uniquely identifies this cursor
     */
    private String extractCursorQueryId(Database.Cursor cursor) {
        String cursorJson = JSON.serialize(cursor);
        Map<String, Object> cursorMap = (Map<String, Object>) JSON.deserializeUntyped(cursorJson);
        return (String) cursorMap.get('queryId');
    }
    
    /**
     * @description Creates and publishes Platform Events to fan out parallel workers.
     *              Returns the actual total batch count calculated during worker assignment.
     * @param cursorQueryId The queryId for cursor reconstruction
     * @param jobRecordId Job tracking record Id
     * @param workerCount Number of parallel workers to create
     * @param recordsPerWorker Number of records assigned to each worker
     * @param totalRecords Total number of records in the cursor
     * @param pageSize Number of records to fetch per page
     * @return Actual total batch count (sum of pages across all workers)
     */
    private Integer fanOutWithPlatformEvents(
        String cursorQueryId,
        Id jobRecordId,
        Integer workerCount,
        Integer recordsPerWorker,
        Integer totalRecords,
        Integer pageSize
    ) {
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>();
        Integer actualTotalBatches = 0;
        
        // Diagnostic: Log sharding calculation
        logger.logInfo('Sharding calc: totalRecords=' + totalRecords + ', workerCount=' + workerCount + ', recordsPerWorker=' + recordsPerWorker + ', pageSize=' + pageSize);
        
        for (Integer i = 0; i < workerCount; i++) {
            Integer startPos = i * recordsPerWorker;
            // Skip workers that would start beyond the dataset - this can happen when
            // ceil(totalRecords/workerCount) * workerCount > totalRecords
            if (startPos >= totalRecords) {
                break;
            }
            Integer endPos = Math.min(startPos + recordsPerWorker, totalRecords);
            Integer workerNum = i + 1;
            
            // Calculate actual pages this worker will process (accounts for last worker having fewer records)
            Integer workerRecords = endPos - startPos;
            Integer workerPages = (Integer) Math.ceil((Decimal) workerRecords / pageSize);
            actualTotalBatches += workerPages;
            
            // Diagnostic: Log each worker's assigned range
            logger.logInfo('PE Worker #' + workerNum + ': range [' + startPos + ', ' + endPos + '), pages=' + workerPages + ', pageSize=' + pageSize);
            
            events.add(new CursorBatch_Worker__e(
                Job_Name__c = jobName,
                Cursor_Query_Id__c = cursorQueryId,
                Start_Position__c = startPos,
                End_Position__c = endPos,
                Page_Size__c = pageSize,
                Worker_Number__c = workerNum,
                Job_Record_Id__c = jobRecordId,
                Worker_Class__c = getWorkerClassName()
            ));
        }
        
        if (!events.isEmpty()) {
            publishEventBatches(events);
        }
        
        return actualTotalBatches;
    }
    
    /**
     * @description Publishes Platform Events in batches of 200 for worker fanout.
     * @param events List of CursorBatch_Worker__e events to publish
     */
    private void publishEventBatches(List<CursorBatch_Worker__e> events) {
        // EventBus.publish handles up to 2000 events, but we batch at 200 for safety
        for (Integer i = 0; i < events.size(); i += PE_BATCH_SIZE) {
            List<CursorBatch_Worker__e> batch = new List<CursorBatch_Worker__e>();
            for (Integer j = i; j < Math.min(i + PE_BATCH_SIZE, events.size()); j++) {
                batch.add(events[j]);
            }
            
            for (Database.SaveResult result : EventBus.publish(batch)) {
                if (!result.isSuccess()) {
                    for (Database.Error err : result.getErrors()) {
                        logger.logError('CursorBatchCoordinator PE publish error: ' + err.getMessage());
                    }
                }
            }
        }
        
        logger.logInfo('CursorBatchCoordinator published ' + events.size() + ' worker events for ' + jobName);
    }
    
    /**
     * @description Test-only configuration that overrides getConfig() behavior when set.
     */
    @TestVisible
    private static CursorBatch_Config__mdt testConfig;
    
    /**
     * @description Retrieves the cursor batch configuration for a job.
     * @param jobName Job name to look up
     * @return CursorBatch_Config__mdt record or null if not found
     */
    public static CursorBatch_Config__mdt getConfig(String jobName) {
        if (Test.isRunningTest() && testConfig != null) {
            return testConfig;
        }
        return CursorBatchSelector.getConfigByJobName(jobName);
    }
    
    /**
     * @description Gets the maximum worker retries from config or returns default.
     * @param jobName Job name to look up configuration
     * @return Maximum number of retry attempts for worker pages
     */
    public static Integer getWorkerMaxRetries(String jobName) {
        CursorBatch_Config__mdt config = getConfig(jobName);
        return getConfigIntOrDefault(config?.Worker_Max_Retries__c, DEFAULT_WORKER_MAX_RETRIES);
    }
    
    /**
     * @description Gets the worker retry base delay from config or returns default.
     * @param jobName Job name to look up configuration
     * @return Base delay in minutes for exponential backoff
     */
    public static Integer getWorkerRetryDelay(String jobName) {
        CursorBatch_Config__mdt config = getConfig(jobName);
        return getConfigIntOrDefault(config?.Worker_Retry_Delay__c, DEFAULT_WORKER_RETRY_DELAY);
    }
    
    /**
     * @description Gets the maximum coordinator retries from config or returns default.
     * @param jobName Job name to look up configuration
     * @return Maximum number of retry attempts for the coordinator
     */
    public static Integer getCoordinatorMaxRetries(String jobName) {
        CursorBatch_Config__mdt config = getConfig(jobName);
        return getConfigIntOrDefault(config?.Coordinator_Max_Retries__c, DEFAULT_COORDINATOR_MAX_RETRIES);
    }
    
    /**
     * @description Helper to extract integer config value or return default.
     * @param value Decimal config field value (may be null)
     * @param defaultVal Default value if null
     * @return Integer value or default
     */
    private static Integer getConfigIntOrDefault(Decimal value, Integer defaultVal) {
        return value != null ? Integer.valueOf(value) : defaultVal;
    }
    
    /**
     * @description Calculates the retry delay using exponential backoff or suggested delay.
     * @param jobName Job name to look up configuration
     * @param retryCount Current retry attempt count
     * @param suggestedDelay Caller-suggested delay, or null for exponential backoff
     * @return Delay in minutes (capped at MAX_DELAY_MINUTES)
     */
    public static Integer calculateRetryDelay(String jobName, Integer retryCount, Integer suggestedDelay) {
        if (suggestedDelay != null) {
            return Math.min(suggestedDelay, MAX_DELAY_MINUTES);
        }
        Integer baseDelay = getWorkerRetryDelay(jobName);
        Integer exponentialDelay = (Integer)(baseDelay * Math.pow(2, retryCount));
        return Math.min(exponentialDelay, MAX_DELAY_MINUTES);
    }
    
    /**
     * @description Builds the SOQL query string for cursor creation. Must use inline values
     *              (no bind variables) for Database.Cursor compatibility.
     * @return Complete SOQL query string
     */
    public abstract String buildQuery();
    
    /**
     * @description Returns the API name of the worker class to instantiate for processing. The
     *              class must extend CursorBatchWorker and have a public no-arg constructor.
     * @return Fully qualified API name of the worker class
     */
    public abstract String getWorkerClassName();
    
    /**
     * @description Called when coordinator completes worker fanout. Override for custom logic.
     */
    public virtual void onComplete() {
        logger.logInfo('CursorBatchCoordinator (' + jobName + ') completed fanout.');
    }
    
    /**
     * @description Called when all workers have completed. Override to chain to another job,
     *              send notifications, or perform cleanup. Similar to the HyperBatch chain() pattern.
     * @param jobRecord Job tracking record with completion status and worker counts
     */
    public virtual void finish(CursorBatch_Job__c jobRecord) {
        logger.logInfo('CursorBatchCoordinator (' + jobName + ') all workers completed. ' +
            'Status: ' + jobRecord.Status__c + ', Workers Finished: ' + jobRecord.Workers_Finished__c + 
            ', Failed: ' + jobRecord.Failed_Workers__c);
    }
    
    /**
     * @description Checks if the job is already running by querying both the CursorBatch_Job__c
     *              tracking records and the AsyncApexJob table for running queueables. Override
     *              to customize duplicate detection logic.
     * @param jobName Job name to check
     * @return True if job is currently running; false otherwise
     */
    protected virtual Boolean isJobAlreadyRunning(String jobName) {
        // Check custom job tracking record for running jobs with the same name
        List<CursorBatch_Job__c> runningJobs = CursorBatchSelector.getRunningJobsByName(jobName);
        if (!runningJobs.isEmpty()) {
            logger.logInfo('CursorBatchCoordinator: Job "' + jobName + '" is already running (found CursorBatch_Job__c record)');
            return true;
        }
        
        // Check AsyncApexJob for running queueables of the same coordinator class
        String className = CursorBatchContext.getClassName(this);
        List<AsyncApexJob> asyncJobs = CursorBatchSelector.getRunningAsyncJobsByClass(className);
        if (!asyncJobs.isEmpty()) {
            logger.logInfo('CursorBatchCoordinator: Job "' + jobName + '" is already running (found AsyncApexJob for ' + className + ')');
            return true;
        }
        
        return false;
    }
    
    /**
     * @description Invokes the coordinator's finish() callback method via reflection.
     *              Used by CursorBatchCompletionHandler and CursorBatchCoordinatorFinalizer
     *              to notify the coordinator when all workers complete or when the job fails.
     * @param coordinatorClassName Fully qualified name of the coordinator class
     * @param jobName Job name for initialization
     * @param jobRecord Job record containing completion details
     * @param logger Logger instance for error reporting
     */
    public static void invokeFinishCallback(
        String coordinatorClassName, 
        String jobName, 
        CursorBatch_Job__c jobRecord, 
        ICursorBatchLogger logger
    ) {
        if (String.isBlank(coordinatorClassName)) {
            return;
        }
        
        try {
            Type coordType = Type.forName(coordinatorClassName);
            if (coordType == null) {
                logger.logError('CursorBatchCoordinator: Coordinator class not found: ' + coordinatorClassName);
                return;
            }
            
            Object instance = coordType.newInstance();
            if (!(instance instanceof CursorBatchCoordinator)) {
                logger.logError('CursorBatchCoordinator: Class ' + coordinatorClassName + ' must extend CursorBatchCoordinator');
                return;
            }
            
            CursorBatchCoordinator coordinator = (CursorBatchCoordinator) instance;
            coordinator.initializeJobName(jobName);
            coordinator.finish(jobRecord);
            
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinator: Error invoking finish() for ' + coordinatorClassName, e);
        }
    }
    
    /**
     * @description Exception class for cursor batch framework errors.
     */
    public class CursorBatchException extends Exception {}
}