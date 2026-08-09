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
    private String query;
    
    /**
     * @description Constructs a finalizer with coordinator context for retry handling.
     * @param jobRecordId ID of the CursorBatch_Job__c tracking record
     * @param jobName Job name for configuration lookup
     * @param coordinatorClassName Fully qualified name of the coordinator class to re-enqueue
     * @param logger Logger instance for error reporting
     * @param query The SOQL query string for logging in failure scenarios (null-safe)
     */
    public CursorBatchCoordinatorFinalizer(
        Id jobRecordId, 
        String jobName, 
        String coordinatorClassName,
        ICursorBatchLogger logger,
        String query
    ) {
        this.jobRecordId = jobRecordId;
        this.jobName = jobName;
        this.coordinatorClassName = coordinatorClassName;
        this.logger = logger;
        this.query = query;
    }
    
    /**
     * @description Called by Salesforce when the queueable completes. If the coordinator
     *              failed (e.g., cursor timeout), handles retry logic.
     * @param ctx Finalizer context containing job result and any exception
     */
    public void execute(System.FinalizerContext ctx) {
        Boolean success = ctx.getResult() == System.ParentJobResult.SUCCESS;
        Exception ex = !success ? ctx.getException() : null;
        String platformStatus = success ? null : resolvePlatformStatus(ctx.getAsyncApexJobId());
        executeInternal(success, ex, platformStatus);
    }
    
    /**
     * @description Handles finalizer logic without a recovered platform status.
     * @param success True if the job succeeded; false otherwise
     * @param ex Exception from failed job, or null on success
     */
    @TestVisible
    private void executeInternal(Boolean success, Exception ex) {
        executeInternal(success, ex, null);
    }
    
    /**
     * @description Handles finalizer logic. Extracted for testability since FinalizerContext
     *              cannot be mocked directly.
     * @param success True if the job succeeded; false otherwise
     * @param ex Exception from failed job, or null on success
     * @param platformStatus AsyncApexJob.ExtendedStatus for the failed job, or null
     */
    @TestVisible
    private void executeInternal(Boolean success, Exception ex, String platformStatus) {
        // If coordinator succeeded, nothing to do
        if (success) {
            return;
        }
        
        // Not logged here: a retryable attempt is reported by retryCoordinator and a terminal
        // one by markJobFailed, so logging up front would double-report every failure.
        String errorMessage = CursorBatchLogger.formatExceptionMessage(ex, platformStatus);
        
        // Query current job record and config
        CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobRecordId);
        if (jobRecord == null) {
            // Neither branch below will run, so this is the only place the failure gets reported.
            logger.logError('CursorBatchCoordinatorFinalizer: Could not find job record ' + jobRecordId +
                ' after coordinator failure for ' + jobName + ': ' + errorMessage);
            return;
        }
        
        Integer maxRetries = CursorBatchCoordinator.getCoordinatorMaxRetries(jobName);
        Integer currentRetryCount = jobRecord.Total_Cursor_Retries__c != null 
            ? Integer.valueOf(jobRecord.Total_Cursor_Retries__c) 
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
        jobRecord.Total_Cursor_Retries__c = newRetryCount;
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
            coordinator.setJobRecordId(jobRecordId);
            
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
        // Info, not error: logTerminalStatus below is the single ERROR for this failed job, and it
        // reports the same query via the job record.
        logger.logInfo('CursorBatchCoordinatorFinalizer: Max retries exhausted for ' + jobName + 
            '. Marking job as Failed. Query: ' + query);
        
        jobRecord.Status__c = 'Failed';
        jobRecord.Query__c = query;
        jobRecord.Error_Message__c = 'Max retries exhausted. Last error: ' + errorMessage;
        jobRecord.Completed_At__c = System.now();
        // Ensure worker counts are set for failed coordinator scenarios
        jobRecord.Total_Workers__c = jobRecord.Total_Workers__c ?? 0;
        jobRecord.Completed_Batches__c = jobRecord.Completed_Batches__c ?? 0;
        jobRecord.Workers_Finished__c = jobRecord.Workers_Finished__c ?? 0;
        jobRecord.Failed_Workers__c = jobRecord.Failed_Workers__c ?? 0;
        update jobRecord;
        
        // Mirror the terminal Failed status onto the parent record (if any) so it doesn't
        // remain stuck at 'Preparing'/'Processing'. This finalizer path bypasses the
        // CompletionHandler, which is the other code path that normally writes the parent.
        CursorBatchCoordinator.mirrorJobStatusToParentExternal(jobRecord, logger);
        
        // Invoke the coordinator's finish() callback so it can handle the failure. If the
        // callback itself throws, append that to the job's error so the second failure isn't
        // lost; the status stays Failed since the job is already terminal.
        Exception finishError = CursorBatchCoordinator.invokeFinishCallback(coordinatorClassName, jobName, jobRecord, logger);
        if (finishError != null) {
            appendFinishError(jobRecord, finishError);
        }
        logger.logInfo('CursorBatchCoordinatorFinalizer: Invoked finish() callback for failed job ' + jobName);
        
        // Emitted after the finish callback so any appended error is part of the summary.
        CursorBatchCompletionHandler.logTerminalStatus(jobRecord, logger);
    }
    
    /**
     * @description Appends a finish()-callback failure to the already-Failed job's error message.
     *              Best-effort: a failure to record must not break the finalizer.
     * @param jobRecord Job record to append to
     * @param finishError The exception thrown by the coordinator's finish() callback
     */
    private void appendFinishError(CursorBatch_Job__c jobRecord, Exception finishError) {
        try {
            String combined = jobRecord.Error_Message__c + '\n\nfinish() failed: ' +
                CursorBatchLogger.formatExceptionMessage(finishError);
            if (combined.length() > CursorBatchCompletionHandler.ERROR_MESSAGE_MAX_LENGTH) {
                combined = combined.left(CursorBatchCompletionHandler.ERROR_MESSAGE_MAX_LENGTH);
            }
            jobRecord.Error_Message__c = combined;
            update new CursorBatch_Job__c(Id = jobRecord.Id, Error_Message__c = combined);
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinatorFinalizer: Failed to record finish() failure for ' + jobName, e);
        }
    }
    
    /**
     * @description Reads the parent job's ExtendedStatus so an opaque platform abort reports the
     *              underlying reason. Cursor creation timing out is this finalizer's known failure
     *              mode, and it reaches Apex only as
     *              'System.UnexpectedException: connection was cancelled here'. Best-effort:
     *              Salesforce does not guarantee the field is committed when the finalizer runs.
     * @param asyncApexJobId Parent job Id from the finalizer context
     * @return ExtendedStatus value, or null when unavailable
     */
    private String resolvePlatformStatus(Id asyncApexJobId) {
        try {
            return CursorBatchSelector.getExtendedStatus(asyncApexJobId);
        } catch (Exception e) {
            return null;
        }
    }
}