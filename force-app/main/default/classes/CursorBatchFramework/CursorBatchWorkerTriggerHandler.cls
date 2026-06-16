/**
 * @description Handles CursorBatch_Worker__e Platform Events. Spawns cursor batch workers
 *              using dynamic instantiation. Reconstructs Database.Cursor from the queryId
 *              passed in each event. Uses instance methods for testability.
 *
 *              Logging: the framework's default logger (CursorBatchLogger.getDefault()) writes
 *              everything to System.debug, which is invisible after the debug log window
 *              expires and has no persistent paper trail for stuck-job forensics. This handler
 *              instead routes through CursorBatchLogger.resolveLogger(LOG_TAG), the framework's
 *              convention-based extension point: it looks up CursorBatchLoggerAdapter via
 *              Type.forName (Callable-enabled Nebula adapter living in the consumer namespace),
 *              tags it with LOG_TAG, and falls back to System.debug only if the adapter class
 *              cannot be loaded -- so this stays cross-package safe even if the framework is
 *              repackaged or the adapter is moved between namespaces. Both PE dispatch
 *              handlers (this class and CursorBatchCoordinatorTriggerHandler) share the same
 *              LOG_TAG so ops can pull "anything that went wrong during PE dispatch" in a
 *              single LogEntry__c tag filter rather than having to OR two separate tags.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchCoordinator
 * @see CursorBatchLogger
 * @see CursorBatchLoggerAdapter
 */
public virtual without sharing class CursorBatchWorkerTriggerHandler {
    
    /**
     * @description Shared tag attached to every LogEntry__c emitted from PE dispatch handlers.
     *              Kept identical in CursorBatchCoordinatorTriggerHandler so ops dashboards can
     *              filter both subscribers' logs with a single tag clause. @TestVisible so the
     *              pinned-value test can catch silent drift before LogEntry__c queries miss
     *              data.
     */
    @TestVisible
    private static final String LOG_TAG = 'CursorBatch Dispatch';

    private Map<String, Database.Cursor> cursorsByQueryId;
    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor. Routes log output through Nebula Logger (via the
     *              framework's resolveLogger convention) instead of the System.debug default,
     *              so cursor-reconstruction failures and swallowed exceptions are recoverable
     *              from LogEntry__c after the transaction ends.
     */
    public CursorBatchWorkerTriggerHandler() {
        this.cursorsByQueryId = new Map<String, Database.Cursor>();
        this.logger = CursorBatchLogger.resolveLogger(LOG_TAG);
    }
    
    /**
     * @description Handles incoming Platform Events by creating and enqueueing workers.
     * @param events CursorBatch_Worker__e events from the Platform Event trigger
     */
    public void handle(List<CursorBatch_Worker__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        for (CursorBatch_Worker__e evt : events) {
            processEvent(evt);
        }
    }
    
    /**
     * @description Processes a single event by reconstructing the cursor (for SOQL) or
     *              skipping reconstruction (for CSV) and enqueueing a worker.
     * @param evt CursorBatch_Worker__e event containing worker parameters
     */
    private void processEvent(CursorBatch_Worker__e evt) {
        try {
            Database.Cursor cursor = null;
            
            if (evt.Processing_Type__c != CursorBatchContext.PROCESSING_TYPE_CSV) {
                String queryId = evt.Cursor_Query_Id__c;
                cursor = cursorsByQueryId.get(queryId);
                
                if (cursor == null) {
                    cursor = CursorBatchContext.reconstructCursor(queryId);
                    if (cursor == null) {
                        logger.logError('CursorBatchWorkerTriggerHandler: Failed to reconstruct cursor for queryId "' + queryId + '"');
                        return;
                    }
                    logger.logInfo('CursorBatchWorkerTriggerHandler: Reconstructed cursor for queryId "' + queryId + '"');
                    cursorsByQueryId.put(queryId, cursor);
                }
            }
            
            CursorBatchContext ctx = CursorBatchContext.fromEvent(evt, cursor);
            enqueueWorker(ctx);
            
        } catch (Exception e) {
            logger.logException('CursorBatchWorkerTriggerHandler: Error processing event for job "' + evt.Job_Name__c + '"', e);
        }
    }
    
    /**
     * @description Creates and enqueues a worker instance for the given context.
     * @param ctx CursorBatchContext containing worker execution parameters
     * @throws CursorBatchException When worker class name is blank
     */
    private void enqueueWorker(CursorBatchContext ctx) {
        String workerClassName = ctx.workerClassName;
        
        if (String.isBlank(workerClassName)) {
            throw new CursorBatchCoordinator.CursorBatchException('Worker class name not specified for job: ' + ctx.jobName);
        }
        
        CursorBatchWorker worker = CursorBatchContext.createWorkerInstance(workerClassName, ctx);
        
        if (!Test.isRunningTest()) {
            System.enqueueJob(worker);
            logger.logInfo('CursorBatchWorkerTriggerHandler: Enqueued ' + workerClassName + ' #' + ctx.workerNum + 
                ' (positions ' + ctx.startPosition + '-' + ctx.endPosition + ')');
        }
    }
    
}