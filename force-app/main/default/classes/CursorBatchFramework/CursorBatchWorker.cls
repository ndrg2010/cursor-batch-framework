/**
 * @description Abstract base class for cursor-based parallel batch workers. Workers process
 *              assigned cursor position ranges, fetching pages and delegating to the abstract
 *              process() method. Uses Platform Events for parallel execution. Supports retry
 *              for failed pages via CursorBatchRetryException or automatic finalizer retry.
 *
 *              State management: It is the responsibility of the worker implementation to
 *              manage shared state (via buildStateDelta, sent on completion events) and
 *              per-worker state (e.g. ctx.workerState when available), and to decide when
 *              to send deltas in completion events, if at all. Workers may send a per-page
 *              state delta after every page (incremental deltas merged by the reducer), and
 *              may also accumulate state across pages (e.g. in workerState) and optionally
 *              flush to shared state once on the final page to avoid double-counting.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 * @see CursorBatchContext
 * @see CursorBatchRetryException
 */
public abstract without sharing class CursorBatchWorker implements Queueable, Database.AllowsCallouts {
    @TestVisible
    protected CursorBatchContext ctx;
    protected ICursorBatchLogger logger;
    protected Object currentState;
    private Boolean stateLoaded = false;
    
    /**
     * @description Default constructor for reflection-based instantiation. Context must be set
     *              via initialize() before enqueueing. Uses convention-based logger resolution
     *              to automatically discover CursorBatchLoggerAdapter if present.
     */
    protected CursorBatchWorker() {
        this.logger = CursorBatchLogger.resolveLogger(null);
    }
    
    /**
     * @description Initializes the worker with execution context. Applies the Logger_Tag__c
     *              from job config to the logger if it supports tagging via Callable.
     * @param ctx CursorBatchContext containing all worker parameters
     */
    public void initialize(CursorBatchContext ctx) {
        this.ctx = ctx;
        this.currentState = null;
        this.stateLoaded = false;
        applyLoggerTag();
    }
    
    /**
     * @description Applies the Logger_Tag__c from job config to the logger. Uses Callable
     *              interface to avoid compile-time dependency on CursorBatchLoggerAdapter.
     */
    private void applyLoggerTag() {
        if (ctx == null || String.isBlank(ctx.jobName) || !(this.logger instanceof Callable)) {
            return;
        }
        CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig(ctx.jobName);
        if (config != null && String.isNotBlank(config.Logger_Tag__c)) {
            ((Callable) this.logger).call('addTag', new Map<String, Object>{ 'tag' => config.Logger_Tag__c });
        }
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
        // Attach finalizer FIRST to catch uncatchable exceptions (permissions, limits, etc.)
        attachFinalizer();
        
        if (ctx == null || String.isBlank(ctx.jobName)) {
            logger.logError('CursorBatchWorker: context or job name is missing; cannot execute');
            onComplete();
            return;
        }
        
        try {
            ctx.stateDeltaJson = null;  // Current run only; set below after successful process(); finalizer reads it for completion event
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
            ctx.stateDeltaJson = CursorBatchStateManager.serializeDelta(ctx.jobName, buildStateDelta(scope));
            if (ctx.stateDeltaJson != null && ctx.stateDeltaJson.length() > CursorBatchStateManager.STATE_JSON_MAX_LENGTH) {
                logger.logError('CursorBatchWorker: State delta exceeds field limit for job ' + ctx.jobName + ', discarding');
                ctx.stateDeltaJson = null;
            }
            
            Integer newPosition = ctx.startPosition + scope.size();
            
            if (newPosition < ctx.endPosition && newPosition < ctx.cursor.getNumRecords()) {
                // Check if job was cancelled (kill switch) before spooling to next page
                if (CursorBatchSelector.isJobCancelled(ctx.jobRecordId)) {
                    logger.logInfo('CursorBatchWorker (' + ctx.jobName + ' #' + ctx.workerNum + 
                        ') stopping - job was cancelled');
                    ctx.isFinal = true;
                    onComplete();
                } else {
                    // More pages to process - build state for next run; enqueue only outside test
                    String serializedState = buildSerializedWorkerState();
                    if (!Test.isRunningTest()) {
                        CursorBatchContext nextCtx = ctx.withNextPosition(newPosition, serializedState);
                        System.enqueueJob(CursorBatchContext.createWorkerInstance(nextCtx.workerClassName, nextCtx));
                    }
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
     * @description Loads the latest persisted shared state snapshot for the current job.
     *              State reads are intentionally unlocked so workers do not serialize each other.
     *              Called lazily from getCurrentState() so SOQL runs only when the worker reads state.
     */
    private void loadCurrentStateInternal() {
        currentState = null;
        if (ctx == null || ctx.jobRecordId == null || String.isBlank(ctx.jobName)) {
            return;
        }
        if (CursorBatchStateManager.getReducer(ctx.jobName) == null) {
            return;
        }
        CursorBatch_Job__c jobSnapshot = CursorBatchSelector.getJobSnapshotById(ctx.jobRecordId);
        if (jobSnapshot != null) {
            currentState = CursorBatchStateManager.deserializeState(ctx.jobName, jobSnapshot.State_JSON__c);
        }
    }
    
    /**
     * @description Initializes the shared state snapshot for finish() callbacks.
     * @param jobRecord Completed job record containing the final persisted state
     */
    private void initializeFinishState(CursorBatch_Job__c jobRecord) {
        currentState = CursorBatchStateManager.deserializeState(jobRecord?.Job_Name__c, jobRecord?.State_JSON__c);
        stateLoaded = true;
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
     * @description Returns the current shared state snapshot for reducer-enabled CursorJob workers.
     *              Loads state from the job record on first call (lazy); subsequent calls return
     *              the cached value. Subclasses can cast this to their reducer's state type.
     * @return Current state snapshot, or null when no reducer is configured or state is not loaded
     */
    protected Object getCurrentState() {
        if (!stateLoaded) {
            loadCurrentStateInternal();
            stateLoaded = true;
        }
        return currentState;
    }
    
    /**
     * @description Returns serialized per-worker state to carry to the next page. Override to
     *              accumulate state across pages (e.g. records processed by this worker).
     *              The value is passed via context to the next run; it is not sent on completion
     *              events. Flush accumulated value to shared state at most once (e.g. in
     *              buildStateDelta() on the final page only) so the completion handler does not
     *              double-count.
     * @return Serialized per-worker state for the next run, or null
     */
    protected virtual String buildSerializedWorkerState() {
        return null;
    }
    
    /**
     * @description Produces a reducer delta after a page processes successfully.
     *              Override in reducer-enabled workers to contribute shared state updates.
     *              The worker implementation decides when to send deltas in completion events:
     *              per-page (return an incremental delta every page), only on the final page,
     *              or not at all. Per-page deltas should be incremental (this page only) so
     *              the completion handler does not double-count; accumulated per-worker state
     *              should be flushed to shared state at most once (e.g. in this method on the
     *              final page only).
     * @param records Records that were processed successfully
     * @return Delta object to serialize and publish, or null
     */
    protected virtual Object buildStateDelta(List<SObject> records) {
        return null;
    }
    
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
            worker.initializeFinishState(jobRecord);
            worker.finish(jobRecord);
            
        } catch (Exception e) {
            logger.logException('CursorBatchWorker: Error invoking finish() for ' + workerClassName, e);
        }
    }
}