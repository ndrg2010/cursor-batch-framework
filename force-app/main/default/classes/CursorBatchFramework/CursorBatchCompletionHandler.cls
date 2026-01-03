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
        
        // Invoke callbacks for completed jobs
        for (CursorBatch_Job__c job : completedJobs) {
            CursorBatchCoordinator.invokeFinishCallback(job.Coordinator_Class__c, job.Job_Name__c, job, logger);
        }
    }
}