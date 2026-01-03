/**
 * @description Abstract base class for cursor-based parallel batch workers. Workers process
 *              assigned cursor position ranges, fetching pages and delegating to the abstract
 *              process() method. Uses Platform Events for parallel execution. Supports retry
 *              for failed pages via CursorBatchRetryException or automatic finalizer retry.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 * @see CursorBatchContext
 * @see CursorBatchRetryException
 */
public abstract without sharing class CursorBatchWorker implements Queueable, Database.AllowsCallouts {
    
    protected CursorBatchContext ctx;
    protected ICursorBatchLogger logger;
    
    /**
     * @description Default constructor for reflection-based instantiation. Context must be set
     *              via initialize() before enqueueing.
     */
    protected CursorBatchWorker() {
        this.logger = CursorBatchLogger.getDefault();
    }
    
    /**
     * @description Initializes the worker with execution context.
     * @param ctx CursorBatchContext containing all worker parameters
     */
    public void initialize(CursorBatchContext ctx) {
        this.ctx = ctx;
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
     * @description Executes the worker: fetches a page of records, processes them, and
     *              re-enqueues for the next page if more records remain. Handles retries
     *              for CursorBatchRetryException (self-retry) and other exceptions (finalizer retry).
     * @param queueableCtx Queueable context (unused; required by Queueable interface)
     */
    public void execute(QueueableContext queueableCtx) {
        try {
            if (ctx.cursor == null) {
                logger.logError('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + 
                    ') has no cursor available');
                attachFinalizerAndComplete();
                return;
            }
            
            // Calculate safe fetch count to avoid "Fetch beyond bound" errors
            Integer remainingInRange = ctx.endPosition - ctx.startPosition;
            Integer remainingInCursor = ctx.cursor.getNumRecords() - ctx.startPosition;
            Integer fetchCount = Math.min(ctx.pageSize, Math.min(remainingInRange, remainingInCursor));
            
            if (fetchCount <= 0) {
                attachFinalizerAndComplete();
                return;
            }
            
            List<SObject> scope = ctx.cursor.fetch(ctx.startPosition, fetchCount);
            
            if (scope.isEmpty()) {
                attachFinalizerAndComplete();
                return;
            }
            
            String retryInfo = ctx.retryCount > 0 ? ' (retry ' + ctx.retryCount + ')' : '';
            logger.logInfo('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + ') processing ' + 
                scope.size() + ' records at position ' + ctx.startPosition + retryInfo);
            
            process(scope);
            
            Integer newPosition = ctx.startPosition + scope.size();
            
            if (newPosition < ctx.endPosition && newPosition < ctx.cursor.getNumRecords()) {
                if (!Test.isRunningTest()) {
                    CursorBatchContext nextCtx = ctx.withNextPosition(newPosition);
                    System.enqueueJob(CursorBatchContext.createWorkerInstance(nextCtx.workerClassName, nextCtx));
                }
            } else {
                attachFinalizerAndComplete();
            }
            
        } catch (CursorBatchRetryException retryEx) {
            // Caller explicitly requested retry - handle with self-retry
            handleRetry(retryEx, retryEx.suggestedDelayMinutes);
        } catch (Exception e) {
            // Framework or unexpected exception - attach finalizer and let it handle retry
            attachFinalizer();
            logger.logException('CursorBatchWorker error for ' + ctx.jobName + ' at position ' + ctx.startPosition, e);
            throw e;
        }
    }
    
    /**
     * @description Handles retry logic for CursorBatchRetryException. Self-enqueues with delay
     *              if retries remain, otherwise attaches finalizer and throws.
     * @param e The exception that triggered the retry
     * @param suggestedDelay Caller-suggested delay in minutes, or null for exponential backoff
     */
    private void handleRetry(Exception e, Integer suggestedDelay) {
        Integer maxRetries = CursorBatchCoordinator.getWorkerMaxRetries(ctx.jobName);
        
        if (ctx.retryCount < maxRetries) {
            Integer delay = CursorBatchCoordinator.calculateRetryDelay(ctx.jobName, ctx.retryCount, suggestedDelay);
            Integer newRetryCount = ctx.retryCount + 1;
            
            logger.logInfo('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + 
                ') scheduling retry ' + newRetryCount + ' of ' + maxRetries + 
                ' in ' + delay + ' min at position ' + ctx.startPosition + 
                '. Reason: ' + e.getMessage());
            
            CursorBatchContext retryCtx = ctx.withRetry(newRetryCount);
            
            if (!Test.isRunningTest()) {
                System.enqueueJob(CursorBatchContext.createWorkerInstance(retryCtx.workerClassName, retryCtx), delay);
            }
        } else {
            // Max retries exhausted - fail via finalizer
            logger.logError('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + 
                ') max retries (' + maxRetries + ') exhausted at position ' + ctx.startPosition);
            attachFinalizer();
            throw e;
        }
    }
    
    /**
     * @description Attaches a finalizer to track worker completion via Platform Events.
     *              Passes full context to support retry from finalizer.
     */
    private void attachFinalizer() {
        if (ctx.jobRecordId != null && !Test.isRunningTest()) {
            System.attachFinalizer(new CursorBatchWorkerFinalizer(ctx, logger));
        }
    }
    
    /**
     * @description Attaches finalizer and calls onComplete() hook.
     */
    private void attachFinalizerAndComplete() {
        attachFinalizer();
        onComplete();
    }
    
    /**
     * @description Processes a batch of records fetched from the cursor. Override to implement
     *              business logic. Throw CursorBatchRetryException to request retry of the
     *              current page.
     * @param records SObjects to process
     * @throws CursorBatchRetryException When the caller wants to retry this page
     */
    public abstract void process(List<SObject> records);
    
    /**
     * @description Called when all pages have been processed. Override for cleanup or chaining.
     */
    public virtual void onComplete() {
        logger.logInfo('CursorBatchWorker (' + ctx.jobName + ') worker #' + ctx.workerNum + ' completed. Position: ' + ctx.startPosition + ', EndPosition: ' + ctx.endPosition);
    }
}