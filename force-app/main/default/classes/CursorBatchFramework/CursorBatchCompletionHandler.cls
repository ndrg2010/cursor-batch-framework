/**
 * @description Handles CursorBatch_WorkerComplete__e Platform Events. Updates job tracking
 *              records and invokes coordinator callbacks when all workers have completed.
 *              Idempotency (processed-event insert, lookup, and cleanup) runs only for jobs
 *              that have a state reducer configured; non-stateful jobs do not use idempotency tracking.
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
     *              callbacks when all workers finish. Idempotency runs only for stateful jobs
     *              (insert per event, lookup, delete on completion); non-stateful jobs have no
     *              processed-event DML or idempotency SOQL.
     *              Job updates are committed before inserting processed-event records so that
     *              transient insert failures do not roll back the critical job state. If the
     *              insert fails, a replayed event may apply the same delta again; reducer
     *              authors should design for occasional double-application (e.g. idempotent
     *              or commutative reducers).
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
        
        // Idempotency: already-processed (Job, ReplayId) from previous transactions. Only for
        // stateful jobs (reducer configured) to protect shared state from replay; no insert/cleanup for non-stateful jobs.
        Set<String> statefulEventKeysInBatch = new Set<String>();
        for (Id jobId : eventsByJob.keySet()) {
            CursorBatch_Job__c job = jobsMap.get(jobId);
            if (job != null && CursorBatchStateManager.getReducer(job.Job_Name__c) != null) {
                for (CursorBatch_WorkerComplete__e evt : eventsByJob.get(jobId)) {
                    String key = getEventKey(evt);
                    if (String.isNotBlank(key)) {
                        statefulEventKeysInBatch.add(key);
                    }
                }
            }
        }
        Set<String> alreadyProcessedKeys = getAlreadyProcessedEventKeys(statefulEventKeysInBatch);
        Set<String> processedInThisBatch = new Set<String>();
        List<CursorBatch_Processed_Event__c> processedEventsToInsert = new List<CursorBatch_Processed_Event__c>();
        
        // One entry per job Id (no duplicate job records in list).
        List<CursorBatch_Job__c> jobsToUpdate = new List<CursorBatch_Job__c>();
        List<CursorBatch_Job__c> completedJobs = new List<CursorBatch_Job__c>();
        Set<Id> completedStatefulJobIds = new Set<Id>();
        
        for (Id jobId : eventsByJob.keySet()) {
            CursorBatch_Job__c job = jobsMap.get(jobId);
            if (job == null) {
                logger.logError('CursorBatchCompletionHandler: Job not found: ' + jobId);
                continue;
            }
            Boolean isStatefulJob = CursorBatchStateManager.getReducer(job.Job_Name__c) != null;
            
            List<CursorBatch_WorkerComplete__e> jobEvents = eventsByJob.get(jobId);
            Integer batchSuccessCount = 0;  // Tracks page/batch completions
            Integer workersFinishedCount = 0;  // Tracks distinct workers that finished all pages
            Integer failCount = 0;
            Integer totalRetries = 0;
            
            for (CursorBatch_WorkerComplete__e evt : jobEvents) {
                String eventKey = isStatefulJob ? getEventKey(evt) : null;
                if (String.isNotBlank(eventKey) && (alreadyProcessedKeys.contains(eventKey) || processedInThisBatch.contains(eventKey))) {
                    continue; // Replay or duplicate in same batch: skip
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
                            String evtKey = getEventKey(evt);
                            logger.logException('CursorBatchCompletionHandler: State reduction failed for job ' + job.Job_Name__c + (String.isNotBlank(evtKey) ? ', eventKey=' + evtKey : '') + ', skipping delta', e);
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
                    logger.logError('CursorBatchCompletionHandler: Worker failed for job ' + 
                        job.Job_Name__c + ': ' + evt.Error_Message__c);
                }
                
                if (String.isNotBlank(eventKey)) {
                    processedInThisBatch.add(eventKey);
                    processedEventsToInsert.add(new CursorBatch_Processed_Event__c(
                        Cursor_Batch_Job__c = jobId,
                        Replay_Id__c = getReplayIdString(evt),
                        Processed_Event_Key__c = eventKey
                    ));
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
                if (isStatefulJob) {
                    completedStatefulJobIds.add(job.Id);
                }
                logger.logInfo('CursorBatchCompletionHandler: Job ' + job.Job_Name__c + ' completed. ' +
                    'Status: ' + job.Status__c + ', Workers Finished: ' + job.Workers_Finished__c + ', Failed: ' + job.Failed_Workers__c);
            }
            
            jobsToUpdate.add(job);
        }
        
        if (!jobsToUpdate.isEmpty()) {
            update jobsToUpdate;
        }
        
        // Idempotency DML: insert processed-event records (stateful jobs only); wrapped so failure does not roll back job updates
        if (!processedEventsToInsert.isEmpty()) {
            try {
                insert processedEventsToInsert;
            } catch (Exception e) {
                logger.logException('CursorBatchCompletionHandler: Failed to record processed events for idempotency', e);
            }
        }
        
        // Clean up idempotency records for completed stateful jobs only. In test run inline delete
        // so tests don't depend on async; otherwise enqueue one Queueable per chunk of 200 job IDs
        // (CursorBatchProcessedEventCleanup.MAX_JOB_IDS_PER_QUERY) to clean all completed jobs.
        if (!completedStatefulJobIds.isEmpty()) {
            try {
                if (Test.isRunningTest()) {
                    delete [SELECT Id FROM CursorBatch_Processed_Event__c WHERE Cursor_Batch_Job__c IN :completedStatefulJobIds];
                } else {
                    List<Id> idList = new List<Id>(completedStatefulJobIds);
                    Integer chunkSize = 200;
                    for (Integer i = 0; i < idList.size(); i += chunkSize) {
                        Set<Id> chunk = new Set<Id>();
                        for (Integer j = i; j < Math.min(i + chunkSize, idList.size()); j++) {
                            chunk.add(idList[j]);
                        }
                        System.enqueueJob(new CursorBatchProcessedEventCleanup(chunk));
                    }
                }
            } catch (Exception e) {
                logger.logException('CursorBatchCompletionHandler: Failed to clean up processed events for completed jobs', e);
            }
        }
        
        // Invoke callbacks for completed jobs using 4-path finish logic
        // Skip callbacks for cancelled jobs (kill switch activated)
        for (CursorBatch_Job__c job : completedJobs) {
            if (job.Status__c != 'Cancelled') {
                routeFinishCallback(job, logger);
            } else {
                logger.logInfo('CursorBatchCompletionHandler: Skipping finish callback for cancelled job ' + job.Job_Name__c);
            }
        }
    }
    
    private static String getEventKey(CursorBatch_WorkerComplete__e evt) {
        Id jobId = evt.Job_Id__c;
        String replayIdStr = getReplayIdString(evt);
        if (jobId == null || String.isBlank(replayIdStr)) {
            return null;
        }
        return jobId + '#' + replayIdStr;
    }
    
    private static String getReplayIdString(CursorBatch_WorkerComplete__e evt) {
        Object replayId = evt.get('ReplayId');
        return replayId != null ? String.valueOf(replayId) : null;
    }
    
    private static Set<String> getAlreadyProcessedEventKeys(Set<String> eventKeys) {
        if (eventKeys == null || eventKeys.isEmpty()) {
            return new Set<String>();
        }
        List<String> keyList = new List<String>(eventKeys);
        List<CursorBatch_Processed_Event__c> existing = [
            SELECT Processed_Event_Key__c
            FROM CursorBatch_Processed_Event__c
            WHERE Processed_Event_Key__c IN :keyList
        ];
        Set<String> result = new Set<String>();
        for (CursorBatch_Processed_Event__c pe : existing) {
            if (String.isNotBlank(pe.Processed_Event_Key__c)) {
                result.add(pe.Processed_Event_Key__c);
            }
        }
        return result;
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
     * @param job The completed job record
     * @param logger Logger instance for error reporting
     */
    public static void routeFinishCallback(CursorBatch_Job__c job, ICursorBatchLogger logger) {
        try {
            routeFinishCallbackInternal(job, logger);
        } catch (Exception e) {
            logger.logException('CursorBatchCompletionHandler: Error in routeFinishCallback for job ' + job.Job_Name__c, e);
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
     * @param logger Logger instance for routing
     */
    private static void routeFinishCallbackInternal(CursorBatch_Job__c job, ICursorBatchLogger logger) {
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