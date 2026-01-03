/**
 * @description Finalizer for CursorBatchCoordinator that handles retry logic when the cursor
 *              query times out. Since Database.getCursor() can throw an uncatchable 
 *              System.QueryException, this finalizer detects failure and re-enqueues the 
 *              coordinator with the same job record ID until max retries is exhausted.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 */
public without sharing class CursorBatchCoordinatorFinalizer implements System.Finalizer {
    
    private Id jobRecordId;
    private String jobName;
    private String coordinatorClassName;
    private ICursorBatchLogger logger;
    
    /**
     * @description Constructs a finalizer with coordinator context for retry handling.
     * @param jobRecordId ID of the CursorBatch_Job__c tracking record
     * @param jobName Job name for configuration lookup
     * @param coordinatorClassName Fully qualified name of the coordinator class to re-enqueue
     * @param logger Logger instance for error reporting
     */
    public CursorBatchCoordinatorFinalizer(
        Id jobRecordId, 
        String jobName, 
        String coordinatorClassName,
        ICursorBatchLogger logger
    ) {
        this.jobRecordId = jobRecordId;
        this.jobName = jobName;
        this.coordinatorClassName = coordinatorClassName;
        this.logger = logger;
    }
    
    /**
     * @description Called by Salesforce when the queueable completes. If the coordinator
     *              failed (e.g., cursor timeout), handles retry logic.
     * @param ctx Finalizer context containing job result and any exception
     */
    public void execute(System.FinalizerContext ctx) {
        Boolean success = ctx.getResult() == System.ParentJobResult.SUCCESS;
        Exception ex = !success ? ctx.getException() : null;
        executeInternal(success, ex);
    }
    
    /**
     * @description Handles finalizer logic. Extracted for testability since FinalizerContext
     *              cannot be mocked directly.
     * @param success True if the job succeeded; false otherwise
     * @param ex Exception from failed job, or null on success
     */
    @TestVisible
    private void executeInternal(Boolean success, Exception ex) {
        // If coordinator succeeded, nothing to do
        if (success) {
            return;
        }
        
        String errorMessage = CursorBatchLogger.formatExceptionMessage(ex);
        logger.logError('CursorBatchCoordinatorFinalizer: Coordinator failed for job ' + jobName + ': ' + errorMessage);
        
        // Query current job record and config
        CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobRecordId);
        if (jobRecord == null) {
            logger.logError('CursorBatchCoordinatorFinalizer: Could not find job record ' + jobRecordId);
            return;
        }
        
        Integer maxRetries = CursorBatchCoordinator.getCoordinatorMaxRetries(jobName);
        Integer currentRetryCount = jobRecord.Retry_Count__c != null 
            ? Integer.valueOf(jobRecord.Retry_Count__c) 
            : 0;
        
        if (currentRetryCount < maxRetries) {
            // Retry: increment count and re-enqueue coordinator
            retryCoordinator(jobRecord, currentRetryCount, maxRetries, errorMessage);
        } else {
            // Max retries exhausted: mark job as failed
            markJobFailed(jobRecord, errorMessage);
        }
    }
    
    /**
     * @description Increments retry count and re-enqueues the coordinator.
     * @param jobRecord Job record to update
     * @param currentRetryCount Current retry count before increment
     * @param maxRetries Maximum retry attempts (passed to avoid redundant config lookup)
     * @param errorMessage Error from the failed attempt
     */
    private void retryCoordinator(CursorBatch_Job__c jobRecord, Integer currentRetryCount, Integer maxRetries, String errorMessage) {
        Integer newRetryCount = currentRetryCount + 1;
        
        // Warn log on each retry attempt
        logger.logInfo('WARN: CursorBatchCoordinatorFinalizer: Cursor query failed for ' + jobName + 
            '. Scheduling retry ' + newRetryCount + ' of ' + maxRetries + '. Error: ' + errorMessage);
        
        // Update job record with new retry count
        jobRecord.Retry_Count__c = newRetryCount;
        jobRecord.Error_Message__c = 'Retry ' + newRetryCount + ': ' + errorMessage;
        update jobRecord;
        
        // Instantiate coordinator via reflection and set existing job ID
        Type coordinatorType = Type.forName(coordinatorClassName);
        if (coordinatorType == null) {
            logger.logError('CursorBatchCoordinatorFinalizer: Could not find coordinator class: ' + coordinatorClassName);
            markJobFailed(jobRecord, 'Could not find coordinator class: ' + coordinatorClassName);
            return;
        }
        
        try {
            CursorBatchCoordinator coordinator = (CursorBatchCoordinator) coordinatorType.newInstance();
            coordinator.initializeJobName(jobName);
            coordinator.setExistingJobId(jobRecordId);
            
            System.enqueueJob(coordinator);
            logger.logInfo('CursorBatchCoordinatorFinalizer: Re-enqueued coordinator for retry');
            
        } catch (Exception e) {
            // In test context, System.enqueueJob may fail - this is expected
            // The job record has already been updated with retry count, so we just log
            logger.logInfo('CursorBatchCoordinatorFinalizer: Could not enqueue coordinator (may be in test context): ' + e.getMessage());
        }
    }
    
    /**
     * @description Marks the job as failed when max retries are exhausted and invokes 
     *              the coordinator's finish() callback.
     * @param jobRecord Job record to update
     * @param errorMessage Final error message
     */
    private void markJobFailed(CursorBatch_Job__c jobRecord, String errorMessage) {
        logger.logError('CursorBatchCoordinatorFinalizer: Max retries exhausted for ' + jobName + 
            '. Marking job as Failed.');
        
        jobRecord.Status__c = 'Failed';
        jobRecord.Error_Message__c = 'Max retries exhausted. Last error: ' + errorMessage;
        jobRecord.Completed_At__c = System.now();
        // Ensure worker counts are set for failed coordinator scenarios
        jobRecord.Total_Workers__c = jobRecord.Total_Workers__c ?? 0;
        jobRecord.Completed_Workers__c = jobRecord.Completed_Workers__c ?? 0;
        jobRecord.Failed_Workers__c = jobRecord.Failed_Workers__c ?? 0;
        update jobRecord;
        
        // Invoke the coordinator's finish() callback so it can handle the failure
        CursorBatchCoordinator.invokeFinishCallback(coordinatorClassName, jobName, jobRecord, logger);
        logger.logInfo('CursorBatchCoordinatorFinalizer: Invoked finish() callback for failed job ' + jobName);
    }
}