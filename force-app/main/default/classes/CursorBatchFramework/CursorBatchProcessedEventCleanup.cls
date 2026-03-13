/**
 * @description Queueable that deletes CursorBatch_Processed_Event__c records for completed
 *              stateful jobs in chunks using Database.Cursor. Enqueued by CursorBatchCompletionHandler
 *              so cleanup does not run in the handler transaction (avoids governor and latency issues).
 * @group CursorBatchFramework
 * @see CursorBatchCompletionHandler
 */
public without sharing class CursorBatchProcessedEventCleanup implements Queueable {
    
    private static final Integer PAGE_SIZE = 2000;
    /** SOQL IN list limit; if more job IDs are passed, only the first batch is used for this enqueue. */
    private static final Integer MAX_JOB_IDS_PER_QUERY = 200;
    
    private final String cursorQueryId;
    private final Integer position;
    
    /**
     * @description Creates a cleanup job for the given completed stateful job IDs.
     *              Builds a cursor over processed-event records using bind variables and stores
     *              its queryId for execute(). Uses at most MAX_JOB_IDS_PER_QUERY job IDs per instance;
     *              callers should enqueue one cleanup per chunk when jobIds exceeds that limit.
     * @param jobIds Set of CursorBatch_Job__c IDs whose processed-event records should be deleted
     */
    public CursorBatchProcessedEventCleanup(Set<Id> jobIds) {
        if (jobIds == null || jobIds.isEmpty()) {
            this.cursorQueryId = null;
            this.position = 0;
            return;
        }
        List<Id> idList = new List<Id>(jobIds);
        if (idList.size() > MAX_JOB_IDS_PER_QUERY) {
            List<Id> chunk = new List<Id>();
            for (Integer i = 0; i < MAX_JOB_IDS_PER_QUERY; i++) {
                chunk.add(idList[i]);
            }
            idList = chunk;
        }
        String soql = 'SELECT Id FROM CursorBatch_Processed_Event__c WHERE Cursor_Batch_Job__c IN :idList';
        Map<String, Object> bindVars = new Map<String, Object>{ 'idList' => idList };
        Database.Cursor cursor = Database.getCursorWithBinds(soql, bindVars, AccessLevel.SYSTEM_MODE);
        this.cursorQueryId = CursorBatchContext.extractQueryId(cursor);
        this.position = 0;
    }
    
    /**
     * @description Private constructor for chaining when more pages remain.
     */
    @TestVisible
    private CursorBatchProcessedEventCleanup(String cursorQueryId, Integer position) {
        this.cursorQueryId = cursorQueryId;
        this.position = position;
    }
    
    /**
     * @description Fetches a page of processed-event IDs, deletes them, and re-enqueues if more remain.
     */
    public void execute(QueueableContext ctx) {
        if (String.isBlank(cursorQueryId)) {
            return;
        }
        Database.Cursor cursor = CursorBatchContext.reconstructCursor(cursorQueryId);
        if (cursor == null || position >= cursor.getNumRecords()) {
            return;
        }
        Integer numRecords = cursor.getNumRecords();
        Integer fetchSize = Math.min(PAGE_SIZE, numRecords - position);
        List<SObject> toDelete = cursor.fetch(position, fetchSize);
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        Integer nextPosition = position + toDelete.size();
        if (nextPosition < cursor.getNumRecords() && !Test.isRunningTest()) {
            System.enqueueJob(new CursorBatchProcessedEventCleanup(cursorQueryId, nextPosition));
        }
    }
}
