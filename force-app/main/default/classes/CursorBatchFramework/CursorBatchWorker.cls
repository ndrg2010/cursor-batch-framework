/**
 * @description Abstract base class for cursor-based parallel batch workers. Workers process
 *              assigned cursor position ranges, fetching pages and delegating to the abstract
 *              process() method. Uses Platform Events for parallel execution with cursors
 *              cached in Platform Cache.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 * @see CursorBatchContext
 */
public abstract inherited sharing class CursorBatchWorker implements Queueable, Database.AllowsCallouts {
    
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
     *              re-enqueues for the next page if more records remain.
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
            
            List<SObject> scope = ctx.cursor.fetch(ctx.startPosition, ctx.pageSize);
            
            if (scope.isEmpty()) {
                attachFinalizerAndComplete();
                return;
            }
            
            logger.logInfo('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + ') processing ' + scope.size() + ' records at position ' + ctx.startPosition);
            
            process(scope);
            
            Integer newPosition = ctx.startPosition + scope.size();
            
            if (newPosition < ctx.endPosition && newPosition < ctx.cursor.getNumRecords()) {
                if (!Test.isRunningTest()) {
                    System.enqueueJob(createNextWorkerInstance(ctx.withNextPosition(newPosition)));
                }
            } else {
                attachFinalizerAndComplete();
            }
            
        } catch (Exception e) {
            // Attach finalizer before re-throwing so failure is tracked
            attachFinalizer();
            logger.logException('CursorBatchWorker error for ' + ctx.jobName + ' at position ' + ctx.startPosition, e);
            throw e;
        }
    }
    
    /**
     * @description Attaches a finalizer to track worker completion via Platform Events.
     */
    private void attachFinalizer() {
        if (ctx.jobRecordId != null && !Test.isRunningTest()) {
            System.attachFinalizer(new CursorBatchWorkerFinalizer(ctx.jobRecordId, ctx.workerNum, logger));
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
     *              business logic.
     * @param records SObjects to process
     */
    public abstract void process(List<SObject> records);
    
    /**
     * @description Creates the next worker instance for pagination using the worker class name
     *              from context. Ensures fully qualified names work correctly for inner classes.
     * @param nextCtx Context with updated position for the next page
     * @return Initialized CursorBatchWorker instance ready for enqueueing
     */
    private CursorBatchWorker createNextWorkerInstance(CursorBatchContext nextCtx) {
        String className = nextCtx.workerClassName;
        Type workerType = Type.forName(className);
        CursorBatchWorker worker = (CursorBatchWorker) workerType.newInstance();
        worker.initialize(nextCtx);
        return worker;
    }
    
    /**
     * @description Called when all pages have been processed. Override for cleanup or chaining.
     */
    public virtual void onComplete() {
        logger.logInfo('CursorBatchWorker (' + ctx.jobName + ') worker #' + ctx.workerNum + ' completed. Position: ' + ctx.startPosition + ', EndPosition: ' + ctx.endPosition);
    }
}
