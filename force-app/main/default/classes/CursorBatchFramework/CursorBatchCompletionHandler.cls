/**
 * @description Handles CursorBatch_WorkerComplete__e Platform Events. Updates job tracking
 *              records and invokes coordinator callbacks when all workers have completed.
 * @group CursorBatchFramework
 * @see CursorBatchWorkerFinalizer
 * @see CursorBatchCoordinator
 */
public without sharing class CursorBatchCompletionHandler {
    
    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor initializing the default logger.
     */
    public CursorBatchCompletionHandler() {
        this.logger = CursorBatchLogger.getDefault();
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
        Map<Id, CursorBatch_Job__c> jobsMap = CursorBatchSelector.getJobsByIds(eventsByJob.keySet());
        
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
            
            for (CursorBatch_WorkerComplete__e evt : jobEvents) {
                // Aggregate worker retry counts
                if (evt.Retry_Count__c != null && evt.Retry_Count__c > 0) {
                    totalRetries += Integer.valueOf(evt.Retry_Count__c);
                }
                
                if (evt.Success__c) {
                    batchSuccessCount++;
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
                    logger.logError('CursorBatchCompletionHandler: Worker failed for job ' + 
                        job.Job_Name__c + ': ' + evt.Error_Message__c);
                }
            }
            
            // Initialize fields if null
            if (job.Completed_Batches__c == null) {
                job.Completed_Batches__c = 0;
            }
            if (job.Workers_Finished__c == null) {
                job.Workers_Finished__c = 0;
            }
            
            job.Completed_Batches__c += batchSuccessCount;
            job.Workers_Finished__c += workersFinishedCount;
            job.Failed_Workers__c += failCount;
            
            // Track total worker retries across the job
            if (job.Total_Worker_Retries__c == null) {
                job.Total_Worker_Retries__c = 0;
            }
            job.Total_Worker_Retries__c += totalRetries;
            
            // Check if all workers are done (using Workers_Finished + Failed, not batch count)
            Decimal totalDone = job.Workers_Finished__c + job.Failed_Workers__c;
            if (totalDone >= job.Total_Workers__c) {
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
                logger.logInfo('CursorBatchCompletionHandler: Job ' + job.Job_Name__c + ' completed. ' +
                    'Status: ' + job.Status__c + ', Workers Finished: ' + job.Workers_Finished__c + ', Failed: ' + job.Failed_Workers__c);
            }
            
            jobsToUpdate.add(job);
        }
        
        if (!jobsToUpdate.isEmpty()) {
            update jobsToUpdate;
        }
        
        // Invoke callbacks for completed jobs using 4-path finish logic
        // Skip callbacks for cancelled jobs (kill switch activated)
        for (CursorBatch_Job__c job : completedJobs) {
            if (job.Status__c != 'Cancelled') {
                invokeFinishCallback(job);
            } else {
                logger.logInfo('CursorBatchCompletionHandler: Skipping finish callback for cancelled job ' + job.Job_Name__c);
            }
        }
    }
    
    /**
     * @description Invokes the appropriate finish callback based on job configuration.
     *              Uses 4-path logic:
     *              1. If Chain_To_Job__c is set → chain to another CursorJob by name
     *              2. Else if Chain_To_Class__c is set → invoke the chain via Callable
     *              3. Else if Query_Builder_Class__c is set (CursorJob) → call worker.finish()
     *              4. Else → call coordinator.finish()
     *              
     *              Wrapped in try-catch to ensure exceptions are logged and don't silently
     *              crash the Platform Event trigger. Falls back to coordinator.finish() on error.
     * @param job The completed job record
     */
    private void invokeFinishCallback(CursorBatch_Job__c job) {
        try {
            invokeFinishCallbackInternal(job);
        } catch (Exception e) {
            logger.logException('CursorBatchCompletionHandler: Error in invokeFinishCallback for job ' + job.Job_Name__c, e);
            // Fallback: still try to call coordinator.finish() so custom cleanup can run
            try {
                CursorBatchCoordinator.invokeFinishCallback(job.Coordinator_Class__c, job.Job_Name__c, job, logger);
            } catch (Exception fallbackEx) {
                logger.logException('CursorBatchCompletionHandler: Fallback coordinator.finish() also failed for ' + job.Job_Name__c, fallbackEx);
            }
        }
    }
    
    /**
     * @description Internal implementation of the 4-path finish callback logic.
     * @param job The completed job record
     */
    private void invokeFinishCallbackInternal(CursorBatch_Job__c job) {
        CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig(job.Job_Name__c);
        
        // Path 1: Chain_To_Job is set - chain to another CursorJob by name
        if (config != null && String.isNotBlank(config.Chain_To_Job__c)) {
            try {
                CursorJob.run(config.Chain_To_Job__c);
                logger.logInfo('CursorBatchCompletionHandler: Chained to job ' + config.Chain_To_Job__c);
            } catch (Exception e) {
                logger.logException('CursorBatchCompletionHandler: Error chaining to job ' + config.Chain_To_Job__c, e);
            }
            return;
        }
        
        // Path 2: Chain_To_Class is set - invoke the chain directly
        if (config != null && String.isNotBlank(config.Chain_To_Class__c)) {
            invokeChain(config.Chain_To_Class__c, config.Chain_To_Method__c, job, logger);
            return;
        }
        
        // Path 3: Query_Builder_Class is set - this is a CursorJob, call worker.finish()
        if (config != null && String.isNotBlank(config.Query_Builder_Class__c)) {
            String workerClass = config.Worker_Class__c;
            if (String.isNotBlank(workerClass)) {
                CursorBatchWorker.invokeFinishCallback(workerClass, job, logger);
            }
            return;
        }
        
        // Path 4: Custom coordinator - call coordinator.finish()
        CursorBatchCoordinator.invokeFinishCallback(job.Coordinator_Class__c, job.Job_Name__c, job, logger);
    }
    
    /**
     * @description Invokes the chain class/method using Callable interface.
     * @param chainClass The class to chain to
     * @param chainMethod The method to call (defaults to 'run' if blank)
     * @param job The completed job record (passed for context)
     * @param logger Logger for error reporting
     */
    private static void invokeChain(String chainClass, String chainMethod, CursorBatch_Job__c job, ICursorBatchLogger logger) {
        String methodToCall = String.isNotBlank(chainMethod) ? chainMethod : 'run';
        
        try {
            Type chainType = Type.forName(chainClass);
            if (chainType == null) {
                logger.logError('CursorBatchCompletionHandler: Chain class not found: ' + chainClass);
                return;
            }
            
            Object instance = chainType.newInstance();
            
            // Try Callable interface first
            if (instance instanceof Callable) {
                Callable callableInstance = (Callable) instance;
                callableInstance.call(methodToCall, new Map<String, Object>{ 'jobRecord' => job });
                logger.logInfo('CursorBatchCompletionHandler: Chained to ' + chainClass + '.' + methodToCall + '()');
                return;
            }
            
            // Fallback: Check if it's a CursorJob chaining to another CursorJob
            // This handles CursorJob.run('NextJobName') pattern
            if (chainClass == 'CursorJob' && methodToCall == 'run') {
                // For CursorJob, we need the job name - this scenario requires explicit config
                logger.logError('CursorBatchCompletionHandler: Chain to CursorJob requires Callable implementation in ' + chainClass);
                return;
            }
            
            logger.logError('CursorBatchCompletionHandler: Chain class ' + chainClass + ' must implement Callable interface');
            
        } catch (Exception e) {
            logger.logException('CursorBatchCompletionHandler: Error invoking chain ' + chainClass + '.' + methodToCall, e);
        }
    }
}