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
     *              via initialize() before enqueueing. Uses convention-based logger resolution
     *              to automatically discover CursorBatchLoggerAdapter if present.
     */
    protected CursorBatchWorker() {
        this.logger = resolveLogger();
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
     * @description Resolves the logger implementation using convention-based discovery.
     *              Looks for a class named 'CursorBatchLoggerAdapter' that implements ICursorBatchLogger.
     *              Falls back to CursorBatchLogger (System.debug) if not found.
     * @return ICursorBatchLogger instance
     */
    private static ICursorBatchLogger resolveLogger() {
        try {
            Type adapterType = Type.forName('CursorBatchLoggerAdapter');
            if (adapterType != null) {
                Object instance = adapterType.newInstance();
                if (instance instanceof ICursorBatchLogger) {
                    return (ICursorBatchLogger) instance;
                }
            }
        } catch (Exception e) {
            // Class not found or instantiation failed - use default
        }
        return CursorBatchLogger.getDefault();
    }
    
    /**
     * @description Executes the worker: fetches a page of records, processes them, and
     *              re-enqueues for the next page if more records remain. Handles retries
     *              for CursorBatchRetryException (self-retry) and other exceptions (finalizer retry).
     * @param queueableCtx Queueable context (unused; required by Queueable interface)
     */
    public void execute(QueueableContext queueableCtx) {
        // Attach finalizer FIRST to catch uncatchable exceptions (permissions, limits, etc.)
        attachFinalizer();
        
        try {
            if (ctx.cursor == null) {
                logger.logError('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + 
                    ') has no cursor available');
                onComplete();
                return;
            }
            
            // Calculate safe fetch count to avoid "Fetch beyond bound" errors
            Integer remainingInRange = ctx.endPosition - ctx.startPosition;
            Integer remainingInCursor = ctx.cursor.getNumRecords() - ctx.startPosition;
            Integer fetchCount = Math.min(ctx.pageSize, Math.min(remainingInRange, remainingInCursor));
            
            if (fetchCount <= 0) {
                ctx.isFinal = true;
                onComplete();
                return;
            }
            
            List<SObject> scope = ctx.cursor.fetch(ctx.startPosition, fetchCount);
            
            if (scope.isEmpty()) {
                ctx.isFinal = true;
                onComplete();
                return;
            }
            
            String retryInfo = ctx.retryCount > 0 ? ' (retry ' + ctx.retryCount + ')' : '';
            logger.logInfo('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + ') processing ' + 
                scope.size() + ' records at position ' + ctx.startPosition + retryInfo);
            
            process(scope);
            
            Integer newPosition = ctx.startPosition + scope.size();
            
            if (newPosition < ctx.endPosition && newPosition < ctx.cursor.getNumRecords()) {
                // More pages to process - not final
                if (!Test.isRunningTest()) {
                    CursorBatchContext nextCtx = ctx.withNextPosition(newPosition);
                    System.enqueueJob(CursorBatchContext.createWorkerInstance(nextCtx.workerClassName, nextCtx));
                }
            } else {
                // Final page - mark as complete
                ctx.isFinal = true;
                onComplete();
            }
            
        } catch (CursorBatchRetryException retryEx) {
            // Caller explicitly requested retry - handle with self-retry
            handleRetry(retryEx, retryEx.suggestedDelayMinutes);
        } catch (Exception e) {
            // Finalizer already attached at start - it will handle retry
            logger.logException('CursorBatchWorker error for ' + ctx.jobName + ' at position ' + ctx.startPosition, e);
            throw e;
        }
    }
    
    /**
     * @description Handles retry logic for CursorBatchRetryException. Self-enqueues with delay
     *              if retries remain, otherwise throws (finalizer handles failure reporting).
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
            // Max retries exhausted - finalizer already attached will handle failure
            logger.logError('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + 
                ') max retries (' + maxRetries + ') exhausted at position ' + ctx.startPosition);
            throw e;
        }
    }
    
    /**
     * @description Attaches a finalizer to track worker completion via Platform Events.
     *              Passes full context to support retry from finalizer. Called at the start
     *              of execute() to ensure uncatchable exceptions are still tracked.
     */
    private void attachFinalizer() {
        if (ctx.jobRecordId != null && !Test.isRunningTest()) {
            System.attachFinalizer(new CursorBatchWorkerFinalizer(ctx, logger));
        }
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
    
    /**
     * @description Called when ALL workers for the job have completed (success or failure).
     *              This is invoked by CursorBatchCompletionHandler on a fresh worker instance
     *              for CursorJob (metadata-driven) jobs. Override to implement custom completion
     *              logic such as chaining to another batch, sending notifications, or cleanup.
     *              
     *              Note: This method is called on a NEW instance of the worker class, not the
     *              instances that processed records. Use jobRecord fields for completion info.
     * @param jobRecord The CursorBatch_Job__c record with completion status and worker counts
     */
    public virtual void finish(CursorBatch_Job__c jobRecord) {
        // Default: no-op. Subclasses override for custom completion logic.
    }
    
    /**
     * @description Invokes the worker's finish() callback method via reflection.
     *              Used by CursorBatchCompletionHandler for CursorJob (metadata-driven) jobs.
     * @param workerClassName Fully qualified name of the worker class
     * @param jobRecord Job record containing completion details
     * @param logger Logger instance for error reporting
     */
    public static void invokeFinishCallback(
        String workerClassName,
        CursorBatch_Job__c jobRecord,
        ICursorBatchLogger logger
    ) {
        if (String.isBlank(workerClassName)) {
            return;
        }
        
        try {
            Type workerType = Type.forName(workerClassName);
            if (workerType == null) {
                logger.logError('CursorBatchWorker: Worker class not found: ' + workerClassName);
                return;
            }
            
            Object instance = workerType.newInstance();
            if (!(instance instanceof CursorBatchWorker)) {
                logger.logError('CursorBatchWorker: Class ' + workerClassName + ' must extend CursorBatchWorker');
                return;
            }
            
            CursorBatchWorker worker = (CursorBatchWorker) instance;
            worker.finish(jobRecord);
            
        } catch (Exception e) {
            logger.logException('CursorBatchWorker: Error invoking finish() for ' + workerClassName, e);
        }
    }
}