/**
 * @description Value object encapsulating context for cursor batch worker execution. Centralizes
 *              parameters for cursor processing, reducing method signature complexity.
 * @group CursorBatchFramework
 */
public without sharing class CursorBatchContext {
    
    public static final String PROCESSING_TYPE_CSV = 'CSV';
    public static final String PROCESSING_TYPE_SOQL = 'SOQL';
    
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
    /** Serialized shared-state delta for the current run only. Set by the framework from buildStateDelta() after successful process(); read by the finalizer and sent on the completion event. Not copied to the next queueable or retry context. */
    public String stateDeltaJson { get; set; }
    /**
     * @description Optional serialized per-worker state carried across pages and retries.
     *              Not sent on completion events; only on the context passed to the next queueable run.
     *              Workers may set/read it; format and size are the worker's responsibility.
     */
    public String workerState { get; set; }
    /** Optional JSON metadata from job invocation. Available to workers via ctx.metadataJson. */
    public String metadataJson { get; private set; }
    /** Processing type for this job (SOQL or CSV). Controls cursor reconstruction and fetch behavior. */
    @TestVisible
    public String processingType { get; private set; }
    /** Convenience accessor: true when processingType is CSV. */
    public Boolean isCsvJob { get { return processingType == PROCESSING_TYPE_CSV; } }
    
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
        this(cursor, startPosition, endPosition, pageSize, jobName, workerNum,
             jobRecordId, workerClassName, cursorQueryId, retryCount, null);
    }
    
    /**
     * @description Constructs a CursorBatchContext with all parameters including metadata.
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
     * @param metadataJson Optional JSON metadata from job invocation
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
        Integer retryCount,
        String metadataJson
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
        this.stateDeltaJson = null;
        this.workerState = null;
        this.metadataJson = metadataJson;
        this.processingType = PROCESSING_TYPE_SOQL;
    }
    
    /**
     * @description Creates a shallow copy of this context. stateDeltaJson is not copied
     *              (it is for the current run's completion event only, read by the finalizer).
     * @return New CursorBatchContext with copied field values
     */
    private CursorBatchContext copy() {
        CursorBatchContext ctx = new CursorBatchContext(
            this.cursor, this.startPosition, this.endPosition, this.pageSize,
            this.jobName, this.workerNum, this.jobRecordId, this.workerClassName,
            this.cursorQueryId, this.retryCount, this.metadataJson
        );
        ctx.isFinal = this.isFinal;
        ctx.processingType = this.processingType;
        // stateDeltaJson is for current run only (finalizer publishes it); do not copy
        ctx.workerState = this.workerState;
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
     * @description Creates a copy of this context with an updated start position and per-worker
     *              state for the next page. Use when enqueueing the next page so the next run
     *              receives the accumulated worker state.
     * @param nextPosition New starting position for the next page
     * @param workerStateForNextPage Serialized per-worker state to carry to the next run (may be null)
     * @return New CursorBatchContext with updated startPosition, retryCount reset to 0, and workerState set
     */
    public CursorBatchContext withNextPosition(Integer nextPosition, String workerStateForNextPage) {
        CursorBatchContext ctx = copy();
        ctx.startPosition = nextPosition;
        ctx.retryCount = 0;  // Reset retry count for next page
        ctx.workerState = workerStateForNextPage;
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
        CursorBatchContext ctx = new CursorBatchContext(
            cursor,
            Integer.valueOf(evt.Start_Position__c),
            Integer.valueOf(evt.End_Position__c),
            Integer.valueOf(evt.Page_Size__c),
            evt.Job_Name__c,
            Integer.valueOf(evt.Worker_Number__c),
            evt.Job_Record_Id__c,
            evt.Worker_Class__c,
            evt.Cursor_Query_Id__c,
            retryCount,
            evt.Metadata_JSON__c
        );
        ctx.processingType = String.isNotBlank(evt.Processing_Type__c)
            ? evt.Processing_Type__c : PROCESSING_TYPE_SOQL;
        return ctx;
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
     * @description Extracts the queryId from a Database.Cursor for passing across transactions
     *              (e.g. to a Queueable). Used with reconstructCursor to recreate the cursor later.
     * @param cursor The Database.Cursor to extract queryId from
     * @return The queryId string, or null if cursor is null or queryId cannot be extracted
     */
    public static String extractQueryId(Database.Cursor cursor) {
        if (cursor == null) {
            return null;
        }
        try {
            String cursorJson = JSON.serialize(cursor);
            Map<String, Object> cursorMap = (Map<String, Object>) JSON.deserializeUntyped(cursorJson);
            return (String) cursorMap.get('queryId');
        } catch (Exception e) {
            return null;
        }
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