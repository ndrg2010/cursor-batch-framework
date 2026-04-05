/**
 * @description Platform Event callback handler for the CSV Cursor Middleware. Receives
 *              CursorBatch_Coordinator__e events published by the middleware when a CSV
 *              session reaches a terminal state (ready or error). Queries the middleware
 *              status endpoint to confirm the result and invokes the onReady() or onError()
 *              hooks for subclass processing.
 *
 *              The middleware publishes the PE with:
 *                  Job_Record_Id__c   = csvQueryId  (the session identifier)
 *                  Job_Name__c        = contentVersionId (the originating file)
 *                  Coordinator_Class__c = 'CSV_Ready'
 *
 *              PE fields are passed to this class via the Callable interface before
 *              the trigger handler enqueues it. Subclass and override onReady() to
 *              implement custom fan-out or processing logic.
 *
 * @group CursorBatchFramework
 * @see CsvCursorClient
 * @see CursorBatchCoordinatorTriggerHandler
 */
public virtual without sharing class CSV_Ready implements Queueable, Database.AllowsCallouts, Callable {

    @TestVisible
    private String csvQueryId;
    @TestVisible
    private String contentVersionId;
    private ICursorBatchLogger logger;

    public CSV_Ready() {
        this.logger = CursorBatchLogger.getDefault();
    }

    /**
     * @description Receives PE field values from the trigger handler before enqueueing.
     *              Expected action: 'handlePlatformEvent' with keys Job_Record_Id__c
     *              (csvQueryId) and Job_Name__c (contentVersionId).
     */
    public Object call(String action, Map<String, Object> args) {
        if (action == 'handlePlatformEvent' && args != null) {
            this.csvQueryId = (String) args.get('Job_Record_Id__c');
            this.contentVersionId = (String) args.get('Job_Name__c');
        }
        return null;
    }

    /**
     * @description Queries the middleware for session status and routes to the appropriate
     *              hook. If the session is ready, onReady() is called with the full status
     *              result including row count and headers. If the session errored, onError()
     *              is called with the error details.
     */
    public void execute(QueueableContext ctx) {
        if (String.isBlank(csvQueryId)) {
            logger.logError('CSV_Ready: csvQueryId is missing; cannot process callback');
            return;
        }

        try {
            CsvCursorClient.StatusResult status = CsvCursorClient.getStatus(csvQueryId);

            if (status.status == 'ready') {
                logger.logInfo(
                    'CSV_Ready: Session ' + csvQueryId + ' ready. ' +
                    'ContentVersion: ' + contentVersionId +
                    ', Rows: ' + status.rowCount +
                    ', Columns: ' + (status.headers != null ? status.headers.size() : 0)
                );
                onReady(status);
            } else if (status.status == 'error') {
                String errorMsg = status.error != null ? status.error.message : 'Unknown error';
                logger.logError(
                    'CSV_Ready: Session ' + csvQueryId +
                    ' (ContentVersion: ' + contentVersionId + ') failed: ' + errorMsg
                );
                onError(status);
            } else {
                logger.logInfo(
                    'CSV_Ready: Session ' + csvQueryId +
                    ' not yet terminal (status: ' + status.status + ')'
                );
            }
        } catch (Exception e) {
            logger.logException(
                'CSV_Ready: Error processing callback for session ' + csvQueryId, e
            );
        }
    }

    /**
     * @description Called when the middleware session is ready. Override to implement
     *              custom processing such as creating a CursorBatch_Job__c record,
     *              calculating worker ranges from status.rowCount, and enqueueing
     *              workers that call CsvCursorClient.getRows().
     * @param status StatusResult containing rowCount, headers, and columnTypes
     */
    protected virtual void onReady(CsvCursorClient.StatusResult status) {
        // Extension point for subclasses.
    }

    /**
     * @description Called when the middleware session has errored. Override to implement
     *              custom error handling such as updating a tracking record or sending
     *              a notification.
     * @param status StatusResult containing the error detail
     */
    protected virtual void onError(CsvCursorClient.StatusResult status) {
        // Extension point for subclasses.
    }

    public String getCsvQueryId() {
        return csvQueryId;
    }

    public String getContentVersionId() {
        return contentVersionId;
    }
}
