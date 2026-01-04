/**
 * @description Finalizer for CursorBatchWorker that handles retry logic and publishes completion 
 *              events. Executes even on worker failure (including uncaught exceptions and CPU limits),
 *              enabling retry with exponential backoff before final failure reporting.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchCompletionHandler
 */
public without sharing class CursorBatchWorkerFinalizer implements System.Finalizer {
    
    private CursorBatchContext ctx;
    private ICursorBatchLogger logger;
    
    /**
     * @description Constructs a finalizer with full worker context for retry and completion tracking.
     * @param ctx Full CursorBatchContext containing all worker parameters including retry state
     * @param logger Logger instance for error reporting
     */
    public CursorBatchWorkerFinalizer(CursorBatchContext ctx, ICursorBatchLogger logger) {
        this.ctx = ctx;
        this.logger = logger;
    }
    
    /**
     * @description Called by Salesforce when the queueable completes. Handles retry logic for
     *              failures and publishes completion events.
     * @param finalizerCtx Finalizer context containing job result and any exception
     */
    public void execute(System.FinalizerContext finalizerCtx) {
        Boolean success = finalizerCtx.getResult() == System.ParentJobResult.SUCCESS;
        Exception ex = !success ? finalizerCtx.getException() : null;
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
        if (success) {
            // Publish completion event for EVERY successful page
            // Is_Final indicates if this worker has finished all its pages
            publishCompletionEvent(true, null, ctx.isFinal);
            return;
        }
        
        String errorMessage = CursorBatchLogger.formatExceptionMessage(ex);
        logger.logError('CursorBatchWorkerFinalizer: Worker #' + ctx.workerNum + ' failed at position ' + 
            ctx.startPosition + ': ' + errorMessage);
        
        // Check if we can retry
        Integer maxRetries = CursorBatchCoordinator.getWorkerMaxRetries(ctx.jobName);
        if (ctx.retryCount < maxRetries) {
            retryWorker(maxRetries, errorMessage);
        } else {
            // Max retries exhausted - publish failure event (worker is done, so isFinal = true)
            logger.logError('CursorBatchWorkerFinalizer: Worker #' + ctx.workerNum + 
                ' max retries (' + maxRetries + ') exhausted at position ' + ctx.startPosition);
            publishCompletionEvent(false, errorMessage, true);
        }
    }
    
    /**
     * @description Reconstructs cursor and re-enqueues worker with delay for retry.
     * @param maxRetries Maximum retry attempts (passed to avoid redundant config lookup)
     * @param errorMessage Error from the failed attempt (for logging)
     */
    private void retryWorker(Integer maxRetries, String errorMessage) {
        Integer newRetryCount = ctx.retryCount + 1;
        Integer delay = CursorBatchCoordinator.calculateRetryDelay(ctx.jobName, ctx.retryCount, null);
        
        logger.logInfo('CursorBatchWorkerFinalizer: Scheduling retry ' + newRetryCount + ' of ' + maxRetries + 
            ' for worker #' + ctx.workerNum + ' in ' + delay + ' min at position ' + ctx.startPosition);
        
        try {
            // Reconstruct cursor from queryId
            Database.Cursor cursor = CursorBatchContext.reconstructCursor(ctx.cursorQueryId);
            if (cursor == null) {
                logger.logError('CursorBatchWorkerFinalizer: Failed to reconstruct cursor for queryId: ' + ctx.cursorQueryId);
                publishCompletionEvent(false, 'Failed to reconstruct cursor for retry: ' + errorMessage, true);
                return;
            }
            
            // Create retry context with new cursor and incremented retry count
            CursorBatchContext retryCtx = ctx.withCursor(cursor).withRetry(newRetryCount);
            
            // Instantiate and enqueue worker
            CursorBatchWorker worker = CursorBatchContext.createWorkerInstance(ctx.workerClassName, retryCtx);
            System.enqueueJob(worker, delay);
            
        } catch (Exception e) {
            logger.logException('CursorBatchWorkerFinalizer: Failed to schedule retry for worker #' + ctx.workerNum, e);
            publishCompletionEvent(false, 'Failed to schedule retry: ' + e.getMessage() + '. Original error: ' + errorMessage, true);
        }
    }
    
    /**
     * @description Publishes a worker completion event for CursorBatchCompletionHandler.
     * @param success True if worker succeeded; false if failed
     * @param errorMessage Error details if failed; null if successful
     * @param isFinal True if this worker has finished all its pages (success or exhausted retries)
     */
    private void publishCompletionEvent(Boolean success, String errorMessage, Boolean isFinal) {
        CursorBatch_WorkerComplete__e evt = new CursorBatch_WorkerComplete__e(
            Job_Id__c = ctx.jobRecordId,
            Success__c = success,
            Error_Message__c = errorMessage,
            Retry_Count__c = ctx.retryCount,
            Is_Final__c = isFinal
        );
        
        Database.SaveResult result = EventBus.publish(evt);
        if (!result.isSuccess()) {
            for (Database.Error err : result.getErrors()) {
                logger.logError('CursorBatchWorkerFinalizer: Failed to publish completion event: ' + err.getMessage());
            }
        }
    }
}