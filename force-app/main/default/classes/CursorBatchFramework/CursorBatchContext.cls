/**
 * @description Value object encapsulating context for cursor batch worker execution. Centralizes
 *              parameters for cursor processing, reducing method signature complexity.
 * @group CursorBatchFramework
 */
public inherited sharing class CursorBatchContext {
    
    public Database.Cursor cursor { get; private set; }
    public Integer startPosition { get; private set; }
    public Integer endPosition { get; private set; }
    public Integer pageSize { get; private set; }
    public String jobName { get; private set; }
    public Integer workerNum { get; private set; }
    public Id jobRecordId { get; private set; }
    public String workerClassName { get; private set; }
    
    /**
     * @description Constructs a CursorBatchContext with all required parameters.
     * @param cursor Database cursor for record fetching
     * @param startPosition Starting cursor position for this worker
     * @param endPosition Ending cursor position (exclusive) for this worker
     * @param pageSize Number of records to fetch per page
     * @param jobName Job identifier for logging and configuration
     * @param workerNum Worker number for tracking
     * @param jobRecordId ID of the CursorBatch_Job__c tracking record
     * @param workerClassName Fully qualified API name of the worker class
     */
    public CursorBatchContext(
        Database.Cursor cursor,
        Integer startPosition,
        Integer endPosition,
        Integer pageSize,
        String jobName,
        Integer workerNum,
        Id jobRecordId,
        String workerClassName
    ) {
        this.cursor = cursor;
        this.startPosition = startPosition;
        this.endPosition = endPosition;
        this.pageSize = pageSize;
        this.jobName = jobName;
        this.workerNum = workerNum;
        this.jobRecordId = jobRecordId;
        this.workerClassName = workerClassName;
    }
    
    /**
     * @description Creates a copy of this context with an updated start position for pagination.
     * @param nextPosition New starting position for the next page
     * @return New CursorBatchContext with updated startPosition; all other fields unchanged
     */
    public CursorBatchContext withNextPosition(Integer nextPosition) {
        return new CursorBatchContext(
            this.cursor,
            nextPosition,
            this.endPosition,
            this.pageSize,
            this.jobName,
            this.workerNum,
            this.jobRecordId,
            this.workerClassName
        );
    }
    
    /**
     * @description Factory method to construct context from a Platform Event.
     * @param evt CursorBatch_Worker__e event containing worker parameters
     * @param cursor Database cursor retrieved from Platform Cache
     * @return CursorBatchContext populated from the event fields
     */
    public static CursorBatchContext fromEvent(CursorBatch_Worker__e evt, Database.Cursor cursor) {
        return new CursorBatchContext(
            cursor,
            Integer.valueOf(evt.Start_Position__c),
            Integer.valueOf(evt.End_Position__c),
            Integer.valueOf(evt.Page_Size__c),
            evt.Job_Name__c,
            Integer.valueOf(evt.Worker_Number__c),
            evt.Job_Record_Id__c,
            evt.Worker_Class__c
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
}
