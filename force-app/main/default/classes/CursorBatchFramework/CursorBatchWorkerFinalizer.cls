/**
 * @description Finalizer for CursorBatchWorker that publishes completion events. Executes even
 *              on worker failure, ensuring accurate completion tracking for callbacks.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchCompletionHandler
 */
public inherited sharing class CursorBatchWorkerFinalizer implements System.Finalizer {
    
    private Id jobRecordId;
    private Integer workerNum;
    private ICursorBatchLogger logger;
    
    /**
     * @description Constructs a finalizer with worker context for completion tracking.
     * @param jobRecordId ID of the CursorBatch_Job__c tracking record
     * @param workerNum Worker number for logging
     * @param logger Logger instance for error reporting
     */
    public CursorBatchWorkerFinalizer(Id jobRecordId, Integer workerNum, ICursorBatchLogger logger) {
        this.jobRecordId = jobRecordId;
        this.workerNum = workerNum;
        this.logger = logger;
    }
    
    /**
     * @description Called by Salesforce when the queueable completes. Publishes a completion
     *              event for CursorBatchCompletionHandler to process.
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
        String errorMessage = null;
        
        if (!success) {
            errorMessage = ex != null ? ex.getMessage() + '\n' + ex.getStackTraceString() : 'Unknown error';
            logger.logError('CursorBatchWorkerFinalizer: Worker #' + workerNum + ' failed: ' + errorMessage);
        }
        
        CursorBatch_WorkerComplete__e evt = new CursorBatch_WorkerComplete__e(
            Job_Id__c = jobRecordId,
            Success__c = success,
            Error_Message__c = errorMessage
        );
        
        Database.SaveResult result = EventBus.publish(evt);
        if (!result.isSuccess()) {
            for (Database.Error err : result.getErrors()) {
                logger.logError('CursorBatchWorkerFinalizer: Failed to publish completion event: ' + err.getMessage());
            }
        }
    }
}

