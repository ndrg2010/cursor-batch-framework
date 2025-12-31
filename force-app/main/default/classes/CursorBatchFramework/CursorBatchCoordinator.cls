/**
 * @description Abstract base class for cursor-based batch coordinators. Executes a query,
 *              creates a Database.Cursor, caches it in Platform Cache, and publishes
 *              Platform Events to fan out parallel workers. Platform Events are used
 *              because queueable-to-queueable chaining is limited to one job.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchWorkerTriggerHandler
 */
public abstract inherited sharing class CursorBatchCoordinator implements Queueable, Database.AllowsCallouts {
    
    private static final Integer DEFAULT_WORKER_COUNT = 50;
    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer DEFAULT_TTL_HOURS = 8;
    private static final Integer PE_BATCH_SIZE = 200;
    
    protected String jobName;
    protected ICursorBatchLogger logger;
    protected ICursorBatchCacheService cacheService;
    
    /**
     * @description Protected no-arg constructor for reflection-based instantiation. When using
     *              this constructor, jobName must be set via initializeJobName() before finish().
     */
    protected CursorBatchCoordinator() {
        this.logger = CursorBatchLogger.getDefault();
        this.cacheService = new CursorBatchCacheServiceImpl();
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
     * @description Sets a custom logger implementation. Call from subclass constructor to
     *              integrate with Nebula Logger, Pharos, or other logging frameworks.
     * @param logger Custom ICursorBatchLogger implementation
     */
    @TestVisible
    protected void setLogger(ICursorBatchLogger logger) {
        this.logger = logger;
    }
    
    /**
     * @description Sets a custom cache service implementation for testing.
     * @param cacheService Custom ICursorBatchCacheService implementation
     */
    @TestVisible
    protected void setCacheService(ICursorBatchCacheService cacheService) {
        this.cacheService = cacheService;
    }
    
    /**
     * @description Submits the coordinator job. By default, checks both CursorBatch_Job__c records
     *              and AsyncApexJob to prevent duplicate jobs. Override isJobAlreadyRunning() to
     *              customize duplicate detection logic.
     */
    public void submit() {
        if (!isJobAlreadyRunning(jobName)) {
            System.enqueueJob(this);
        }
    }
    
    /**
     * @description Executes the coordinator: runs query, creates cursor, caches it, and fans
     *              out workers via Platform Events.
     * @param ctx Queueable context (unused; required by Queueable interface)
     * @throws CursorBatchException When no active config is found for the job name
     */
    public void execute(QueueableContext ctx) {
        try {
            CursorBatch_Config__mdt config = getConfig(jobName);
            if (config == null) {
                throw new CursorBatchException('No active config found for job: ' + jobName);
            }
            
            Integer workerCount = config.Parallel_Count__c != null 
                ? Integer.valueOf(config.Parallel_Count__c) 
                : DEFAULT_WORKER_COUNT;
            Integer pageSize = config.Page_Size__c != null 
                ? Integer.valueOf(config.Page_Size__c) 
                : DEFAULT_PAGE_SIZE;
            Integer ttlHours = config.Cache_TTL_Hours__c != null 
                ? Integer.valueOf(config.Cache_TTL_Hours__c) 
                : DEFAULT_TTL_HOURS;
            Integer ttlSeconds = ttlHours * 3600;
            
            String query = buildQuery();
            logger.logInfo('CursorBatchCoordinator query for ' + jobName + ': ' + query);
            
            Database.Cursor dbCursor = Database.getCursor(query);
            Integer totalRecords = dbCursor.getNumRecords();
            logger.logInfo('CursorBatchCoordinator totalRecords: ' + totalRecords);
            
            if (totalRecords == 0) {
                logger.logInfo('No records to process for ' + jobName + ', exiting.');
                onComplete();
                return;
            }
            
            Integer actualWorkerCount = Math.min(workerCount, totalRecords);
            Integer recordsPerWorker = (Integer) Math.ceil((Decimal) totalRecords / actualWorkerCount);
            
            logger.logInfo('Distributing ' + totalRecords + ' records across ' + actualWorkerCount + ' workers via Platform Events');
            
            fanOutWithPlatformEvents(dbCursor, actualWorkerCount, recordsPerWorker, totalRecords, pageSize, ttlSeconds);
            
            onComplete();
            
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinator error for ' + jobName, e);
            throw e;
        }
    }
    
    /**
     * @description Creates Platform Events to fan out parallel workers with cursor positions.
     * @param dbCursor Database cursor for record access
     * @param workerCount Number of parallel workers to create
     * @param recordsPerWorker Number of records assigned to each worker
     * @param totalRecords Total number of records in the cursor
     * @param pageSize Number of records to fetch per page
     * @param ttlSeconds Cache TTL in seconds for the cursor
     */
    private void fanOutWithPlatformEvents(
        Database.Cursor dbCursor,
        Integer workerCount,
        Integer recordsPerWorker,
        Integer totalRecords,
        Integer pageSize,
        Integer ttlSeconds
    ) {
        String cacheKey = cacheService.generateCacheKey(jobName);
        cacheService.cacheCursor(cacheKey, dbCursor);
        
        logger.logInfo('CursorBatchCoordinator cached cursor with key: ' + cacheKey);
        
        // Create job tracking record for completion callbacks
        CursorBatch_Job__c jobRecord = createJobRecord(workerCount, cacheKey);
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>();
        
        for (Integer i = 0; i < workerCount; i++) {
            Integer startPos = i * recordsPerWorker;
            Integer endPos = Math.min(startPos + recordsPerWorker, totalRecords);
            Integer workerNum = i + 1;
            
            events.add(new CursorBatch_Worker__e(
                Job_Name__c = jobName,
                Cache_Key__c = cacheKey,
                Start_Position__c = startPos,
                End_Position__c = endPos,
                Page_Size__c = pageSize,
                Worker_Number__c = workerNum,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = getWorkerClassName()
            ));
        }
        
        if (!events.isEmpty()) {
            publishEventBatches(events);
        }
    }
    
    /**
     * @description Creates a job tracking record for completion callbacks.
     * @param workerCount Total number of workers for this job
     * @param cacheKey Cache key used to store the cursor
     * @return Inserted CursorBatch_Job__c record
     */
    private CursorBatch_Job__c createJobRecord(Integer workerCount, String cacheKey) {
        CursorBatch_Job__c jobRecord = new CursorBatch_Job__c(
            Job_Name__c = jobName,
            Total_Workers__c = workerCount,
            Completed_Workers__c = 0,
            Failed_Workers__c = 0,
            Status__c = 'Running',
            Coordinator_Class__c = CursorBatchContext.getClassName(this),
            Cache_Key__c = cacheKey,
            Started_At__c = System.now()
        );
        insert jobRecord;
        logger.logInfo('CursorBatchCoordinator created job tracking record: ' + jobRecord.Id);
        return jobRecord;
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
        List<CursorBatch_Config__mdt> configs = [
            SELECT MasterLabel, Parallel_Count__c, Page_Size__c, Cache_TTL_Hours__c
            FROM CursorBatch_Config__mdt
            WHERE MasterLabel = :jobName
            AND Active__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
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
            'Status: ' + jobRecord.Status__c + ', Completed: ' + jobRecord.Completed_Workers__c + 
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
        List<CursorBatch_Job__c> runningJobs = [
            SELECT Id 
            FROM CursorBatch_Job__c 
            WHERE Job_Name__c = :jobName 
            AND Status__c = 'Running'
            LIMIT 1
        ];
        if (!runningJobs.isEmpty()) {
            logger.logInfo('CursorBatchCoordinator: Job "' + jobName + '" is already running (found CursorBatch_Job__c record)');
            return true;
        }
        
        // Check AsyncApexJob for running queueables of the same coordinator class
        String className = CursorBatchContext.getClassName(this);
        List<AsyncApexJob> asyncJobs = [
            SELECT Id 
            FROM AsyncApexJob 
            WHERE ApexClass.Name = :className 
            AND Status IN ('Queued', 'Holding', 'Preparing', 'Processing')
            LIMIT 1
        ];
        if (!asyncJobs.isEmpty()) {
            logger.logInfo('CursorBatchCoordinator: Job "' + jobName + '" is already running (found AsyncApexJob for ' + className + ')');
            return true;
        }
        
        return false;
    }
    
    /**
     * @description Exception class for cursor batch framework errors.
     */
    public class CursorBatchException extends Exception {}
}
