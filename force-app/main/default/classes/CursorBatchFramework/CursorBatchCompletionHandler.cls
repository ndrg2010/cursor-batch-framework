/**
 * @description Handles CursorBatch_WorkerComplete__e Platform Events. Updates job tracking
 *              records and invokes coordinator callbacks when all workers have completed.
 * @group CursorBatchFramework
 * @see CursorBatchWorkerFinalizer
 * @see CursorBatchCoordinator
 */
public inherited sharing class CursorBatchCompletionHandler {
    
    private ICursorBatchLogger logger;
    private ICursorBatchCacheService cacheService;
    
    /**
     * @description Default constructor initializing the default logger and cache service.
     */
    public CursorBatchCompletionHandler() {
        this.logger = CursorBatchLogger.getDefault();
        this.cacheService = new CursorBatchCacheServiceImpl();
    }
    
    /**
     * @description Sets a custom cache service implementation for testing.
     * @param cacheService Custom ICursorBatchCacheService implementation
     */
    @TestVisible
    private void setCacheService(ICursorBatchCacheService cacheService) {
        this.cacheService = cacheService;
    }
    
    /**
     * @description Handles worker completion events by updating tracking records and invoking
     *              callbacks when all workers finish.
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
        Map<Id, CursorBatch_Job__c> jobsMap = new Map<Id, CursorBatch_Job__c>([
            SELECT Id, Job_Name__c, Total_Workers__c, Completed_Workers__c, Failed_Workers__c,
                   Status__c, Coordinator_Class__c, Error_Message__c, Cache_Key__c
            FROM CursorBatch_Job__c
            WHERE Id IN :eventsByJob.keySet()
            FOR UPDATE
        ]);
        
        List<CursorBatch_Job__c> jobsToUpdate = new List<CursorBatch_Job__c>();
        List<CursorBatch_Job__c> completedJobs = new List<CursorBatch_Job__c>();
        
        for (Id jobId : eventsByJob.keySet()) {
            CursorBatch_Job__c job = jobsMap.get(jobId);
            if (job == null) {
                logger.logError('CursorBatchCompletionHandler: Job not found: ' + jobId);
                continue;
            }
            
            List<CursorBatch_WorkerComplete__e> jobEvents = eventsByJob.get(jobId);
            Integer successCount = 0;
            Integer failCount = 0;
            
            for (CursorBatch_WorkerComplete__e evt : jobEvents) {
                if (evt.Success__c) {
                    successCount++;
                } else {
                    failCount++;
                    // Capture first error only (similar to AsyncApexJob.ExtendedStatus)
                    if (job.Error_Message__c == null && String.isNotBlank(evt.Error_Message__c)) {
                        job.Error_Message__c = evt.Error_Message__c;
                    }
                    logger.logError('CursorBatchCompletionHandler: Worker failed for job ' + 
                        job.Job_Name__c + ': ' + evt.Error_Message__c);
                }
            }
            
            job.Completed_Workers__c += successCount;
            job.Failed_Workers__c += failCount;
            
            // Check if all workers are done
            Decimal totalDone = job.Completed_Workers__c + job.Failed_Workers__c;
            if (totalDone >= job.Total_Workers__c) {
                job.Status__c = job.Failed_Workers__c > 0 ? 'Failed' : 'Complete';
                job.Completed_At__c = System.now();
                completedJobs.add(job);
                logger.logInfo('CursorBatchCompletionHandler: Job ' + job.Job_Name__c + ' completed. ' +
                    'Status: ' + job.Status__c + ', Success: ' + job.Completed_Workers__c + ', Failed: ' + job.Failed_Workers__c);
            }
            
            jobsToUpdate.add(job);
        }
        
        if (!jobsToUpdate.isEmpty()) {
            update jobsToUpdate;
        }
        
        // Invoke callbacks and clean up cache for completed jobs
        for (CursorBatch_Job__c job : completedJobs) {
            cleanupCache(job);
            invokeCallback(job);
        }
    }
    
    /**
     * @description Removes the cached cursor for a completed job to free Platform Cache capacity.
     * @param job Job record containing the cache key
     */
    private void cleanupCache(CursorBatch_Job__c job) {
        if (String.isNotBlank(job.Cache_Key__c)) {
            cacheService.removeCursor(job.Cache_Key__c);
        }
    }
    
    /**
     * @description Invokes the coordinator's finish() callback method via reflection.
     * @param job Job record containing coordinator class name and completion details
     */
    private void invokeCallback(CursorBatch_Job__c job) {
        String coordinatorClass = job.Coordinator_Class__c;
        if (String.isBlank(coordinatorClass)) {
            return;
        }
        
        try {
            Type coordType = Type.forName(coordinatorClass);
            if (coordType == null) {
                logger.logError('CursorBatchCompletionHandler: Coordinator class not found: ' + coordinatorClass);
                return;
            }
            
            Object instance = coordType.newInstance();
            if (!(instance instanceof CursorBatchCoordinator)) {
                logger.logError('CursorBatchCompletionHandler: Class ' + coordinatorClass + ' must extend CursorBatchCoordinator');
                return;
            }
            
            CursorBatchCoordinator coordinator = (CursorBatchCoordinator) instance;
            coordinator.initializeJobName(job.Job_Name__c);
            coordinator.finish(job);
            
        } catch (Exception e) {
            logger.logException('CursorBatchCompletionHandler: Error invoking callback for ' + coordinatorClass, e);
        }
    }
}

