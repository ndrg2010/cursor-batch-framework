/**
 * @description Value object encapsulating context for cursor batch worker execution. Centralizes
 *              parameters for cursor processing, reducing method signature complexity.
 * @group CursorBatchFramework
 */
public without sharing class CursorBatchContext {
    
    public Database.Cursor cursor { get; private set; }
    public Integer startPosition { get; private set; }
    public Integer endPosition { get; private set; }
    public Integer pageSize { get; private set; }
    public String jobName { get; private set; }
    public Integer workerNum { get; private set; }
    public Id jobRecordId { get; private set; }
    public String workerClassName { get; private set; }
    public String cursorQueryId { get; private set; }
    public Integer retryCount { get; private set; }
    public Boolean isFinal { get; set; }
    
    /**
     * @description Constructs a CursorBatchContext with all parameters including retry support.
     * @param cursor Database cursor for record fetching
     * @param startPosition Starting cursor position for this worker
     * @param endPosition Ending cursor position (exclusive) for this worker
     * @param pageSize Number of records to fetch per page
     * @param jobName Job identifier for logging and configuration
     * @param workerNum Worker number for tracking
     * @param jobRecordId ID of the CursorBatch_Job__c tracking record
     * @param workerClassName Fully qualified API name of the worker class
     * @param cursorQueryId The queryId for cursor reconstruction in finalizers
     * @param retryCount Current retry attempt count (0 for first attempt)
     */
    public CursorBatchContext(
        Database.Cursor cursor,
        Integer startPosition,
        Integer endPosition,
        Integer pageSize,
        String jobName,
        Integer workerNum,
        Id jobRecordId,
        String workerClassName,
        String cursorQueryId,
        Integer retryCount
    ) {
        this.cursor = cursor;
        this.startPosition = startPosition;
        this.endPosition = endPosition;
        this.pageSize = pageSize;
        this.jobName = jobName;
        this.workerNum = workerNum;
        this.jobRecordId = jobRecordId;
        this.workerClassName = workerClassName;
        this.cursorQueryId = cursorQueryId;
        this.retryCount = retryCount != null ? retryCount : 0;
        this.isFinal = false;
    }
    
    /**
     * @description Creates a shallow copy of this context with all fields duplicated.
     * @return New CursorBatchContext with identical field values
     */
    private CursorBatchContext copy() {
        CursorBatchContext ctx = new CursorBatchContext(
            this.cursor, this.startPosition, this.endPosition, this.pageSize,
            this.jobName, this.workerNum, this.jobRecordId, this.workerClassName,
            this.cursorQueryId, this.retryCount
        );
        ctx.isFinal = this.isFinal;
        return ctx;
    }
    
    /**
     * @description Creates a copy of this context with an updated start position for pagination.
     * @param nextPosition New starting position for the next page
     * @return New CursorBatchContext with updated startPosition; retryCount reset to 0
     */
    public CursorBatchContext withNextPosition(Integer nextPosition) {
        CursorBatchContext ctx = copy();
        ctx.startPosition = nextPosition;
        ctx.retryCount = 0;  // Reset retry count for next page
        return ctx;
    }
    
    /**
     * @description Creates a copy of this context with an updated retry count.
     * @param newRetryCount New retry count for the retry attempt
     * @return New CursorBatchContext with updated retryCount; all other fields unchanged
     */
    public CursorBatchContext withRetry(Integer newRetryCount) {
        CursorBatchContext ctx = copy();
        ctx.retryCount = newRetryCount;
        return ctx;
    }
    
    /**
     * @description Creates a copy of this context with a new cursor instance.
     *              Used by finalizers after reconstructing the cursor from queryId.
     * @param newCursor Reconstructed Database.Cursor instance
     * @return New CursorBatchContext with updated cursor; all other fields unchanged
     */
    public CursorBatchContext withCursor(Database.Cursor newCursor) {
        CursorBatchContext ctx = copy();
        ctx.cursor = newCursor;
        return ctx;
    }
    
    /**
     * @description Factory method to construct context from a Platform Event.
     * @param evt CursorBatch_Worker__e event containing worker parameters
     * @param cursor Database cursor reconstructed from the queryId
     * @return CursorBatchContext populated from the event fields
     */
    public static CursorBatchContext fromEvent(CursorBatch_Worker__e evt, Database.Cursor cursor) {
        Integer retryCount = evt.Retry_Count__c != null ? Integer.valueOf(evt.Retry_Count__c) : 0;
        return new CursorBatchContext(
            cursor,
            Integer.valueOf(evt.Start_Position__c),
            Integer.valueOf(evt.End_Position__c),
            Integer.valueOf(evt.Page_Size__c),
            evt.Job_Name__c,
            Integer.valueOf(evt.Worker_Number__c),
            evt.Job_Record_Id__c,
            evt.Worker_Class__c,
            evt.Cursor_Query_Id__c,
            retryCount
        );
    }
    
    /**
     * @description Extracts the fully qualified class name from an object instance. Converts
     *              inner class separators ($) to dots for Type.forName compatibility.
     * @param instance Object to extract class name from
     * @return Fully qualified class name with dot separators
     */
    public static String getClassName(Object instance) {
        String className = String.valueOf(instance).substringBefore(':');
        return className.replace('$', '.');
    }
    
    /**
     * @description Reconstructs a Database.Cursor from its queryId using JSON deserialization.
     *              Used by trigger handlers and finalizers to recreate cursors across transactions.
     * @param queryId The queryId extracted from the original cursor
     * @return Reconstructed Database.Cursor, or null if queryId is blank or reconstruction fails
     */
    public static Database.Cursor reconstructCursor(String queryId) {
        if (String.isBlank(queryId)) {
            return null;
        }
        
        String cursorJson = '{"queryId":"' + queryId + '"}';
        return (Database.Cursor) JSON.deserialize(cursorJson, Database.Cursor.class);
    }
    
    /**
     * @description Creates and initializes a worker instance using reflection-based instantiation.
     *              Used by trigger handlers and finalizers to create workers dynamically.
     * @param className Fully qualified API name of the worker class
     * @param ctx CursorBatchContext to initialize the worker with
     * @return Initialized CursorBatchWorker instance ready for enqueueing
     * @throws CursorBatchCoordinator.CursorBatchException When class not found or not a CursorBatchWorker
     */
    public static CursorBatchWorker createWorkerInstance(String className, CursorBatchContext ctx) {
        Type workerType = Type.forName(className);
        if (workerType == null) {
            throw new CursorBatchCoordinator.CursorBatchException('Worker class not found: ' + className);
        }
        
        Object instance = workerType.newInstance();
        if (!(instance instanceof CursorBatchWorker)) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'Worker class "' + className + '" must extend CursorBatchWorker'
            );
        }
        
        CursorBatchWorker worker = (CursorBatchWorker) instance;
        worker.initialize(ctx);
        return worker;
    }
}