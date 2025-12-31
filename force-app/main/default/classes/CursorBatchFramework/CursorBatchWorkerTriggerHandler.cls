/**
 * @description Handles CursorBatch_Worker__e Platform Events. Spawns cursor batch workers
 *              using dynamic instantiation. Uses instance methods for testability.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CursorBatchCoordinator
 */
public virtual inherited sharing class CursorBatchWorkerTriggerHandler {
    
    private Map<String, Database.Cursor> cursorsByKey;
    private ICursorBatchLogger logger;
    private ICursorBatchCacheService cacheService;
    
    /**
     * @description Default constructor initializing the cursor cache map, logger, and cache service.
     */
    public CursorBatchWorkerTriggerHandler() {
        this.cursorsByKey = new Map<String, Database.Cursor>();
        this.logger = CursorBatchLogger.getDefault();
        this.cacheService = new CursorBatchCacheServiceImpl();
    }
    
    /**
     * @description Sets a custom cache service implementation for testing.
     * @param cacheService Custom ICursorBatchCacheService implementation
     */
    @TestVisible
    private void setCacheService(ICursorBatchCacheService cacheService) {
        this.cacheService = cacheService;
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
     * @description Processes a single event by retrieving the cursor and enqueueing a worker.
     * @param evt CursorBatch_Worker__e event containing worker parameters
     */
    private void processEvent(CursorBatch_Worker__e evt) {
        try {
            String cacheKey = evt.Cache_Key__c;
            Database.Cursor cursor = cursorsByKey.get(cacheKey);
            
            if (cursor == null) {
                cursor = cacheService.getCursor(cacheKey);
                if (cursor == null) {
                    logger.logError('CursorBatchWorkerTriggerHandler: Cursor not found in cache for key "' + cacheKey + '"');
                    return;
                }
                cursorsByKey.put(cacheKey, cursor);
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
        
        CursorBatchWorker worker = createWorkerInstance(workerClassName, ctx);
        
        if (!Test.isRunningTest()) {
            System.enqueueJob(worker);
            logger.logInfo('CursorBatchWorkerTriggerHandler: Enqueued ' + workerClassName + ' #' + ctx.workerNum + 
                ' (positions ' + ctx.startPosition + '-' + ctx.endPosition + ')');
        }
    }
    
    /**
     * @description Creates a worker instance using reflection-based instantiation.
     * @param className Fully qualified API name of the worker class
     * @param ctx CursorBatchContext to initialize the worker with
     * @return Initialized CursorBatchWorker instance ready for enqueueing
     * @throws CursorBatchException When class not found, not a CursorBatchWorker, or lacks no-arg constructor
     */
    @TestVisible
    private CursorBatchWorker createWorkerInstance(String className, CursorBatchContext ctx) {
        Type workerType = Type.forName(className);
        
        if (workerType == null) {
            throw new CursorBatchCoordinator.CursorBatchException('Worker class not found: ' + className);
        }
        
        try {
            Object instance = workerType.newInstance();
            
            if (!(instance instanceof CursorBatchWorker)) {
                throw new CursorBatchCoordinator.CursorBatchException(
                    'Worker class "' + className + '" must extend CursorBatchWorker'
                );
            }
            
            CursorBatchWorker worker = (CursorBatchWorker) instance;
            worker.initialize(ctx);
            return worker;
            
        } catch (System.TypeException te) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'Worker class "' + className + '" must have a no-arg constructor: ' + te.getMessage()
            );
        }
    }
    
}
