/**
 * @description Handles CursorBatch_Worker__e Platform Events. Spawns cursor batch workers
 *              using dynamic instantiation. Reconstructs Database.Cursor from the queryId
 *              passed in each event. Uses instance methods for testability.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchCoordinator
 */
public virtual without sharing class CursorBatchWorkerTriggerHandler {
    
    private Map<String, Database.Cursor> cursorsByQueryId;
    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor initializing the cursor map and logger.
     */
    public CursorBatchWorkerTriggerHandler() {
        this.cursorsByQueryId = new Map<String, Database.Cursor>();
        this.logger = CursorBatchLogger.getDefault();
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
     * @description Processes a single event by reconstructing the cursor and enqueueing a worker.
     * @param evt CursorBatch_Worker__e event containing worker parameters
     */
    private void processEvent(CursorBatch_Worker__e evt) {
        try {
            String queryId = evt.Cursor_Query_Id__c;
            Database.Cursor cursor = cursorsByQueryId.get(queryId);
            
            if (cursor == null) {
                cursor = CursorBatchContext.reconstructCursor(queryId);
                if (cursor == null) {
                    logger.logError('CursorBatchWorkerTriggerHandler: Failed to reconstruct cursor for queryId "' + queryId + '"');
                    return;
                }
                logger.logInfo('CursorBatchWorkerTriggerHandler: Reconstructed cursor for queryId "' + queryId + '"');
                cursorsByQueryId.put(queryId, cursor);
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