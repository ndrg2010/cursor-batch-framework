/**
 * @description Coordinator that handles the CSV middleware callback. When the middleware finishes
 *              indexing a CSV file, it publishes a CursorBatch_Coordinator__e with
 *              Coordinator_Class__c = 'CSV_Ready'. The trigger handler routes that event here.
 *
 *              This coordinator retrieves the row count from the middleware and fans out
 *              workers using the same shared fanOutJob() logic as the SOQL path. The
 *              csvCursorQuery session ID is persisted on the job record by the trigger
 *              handler (in its own transaction) so it survives coordinator rollback on retry.
 * @group CursorBatchFramework
 * @see CsvCursorClient
 * @see CursorBatchCoordinatorTriggerHandler
 */
public without sharing class CursorBatchCsvCallbackCoordinator extends CursorBatchCoordinator {

    private String csvCursorQuery;
    private CursorBatch_Config__mdt cachedConfig;

    public CursorBatchCsvCallbackCoordinator() {
        super();
    }

    /**
     * @description Constructs the callback coordinator with the middleware session ID.
     * @param csvCursorQuery Session identifier from the middleware callback event
     */
    public CursorBatchCsvCallbackCoordinator(String csvCursorQuery) {
        super();
        this.csvCursorQuery = csvCursorQuery;
    }

    /**
     * @description Handles the CSV_Ready callback: resolves the job, gets the row count from
     *              the middleware, and fans out workers using the inherited fanOutJob() method.
     *              On retry (no-arg constructor path), recovers csvCursorQuery from the job record.
     * @param ctx Queueable context
     */
    public override void execute(QueueableContext ctx) {
        currentAsyncJobId = ctx?.getJobId();
        try {
            CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobRecordId);
            if (jobRecord == null) {
                throw new CursorBatchException('Job record not found for CSV callback: ' + jobRecordId);
            }

            this.jobName = jobRecord.Job_Name__c;
            if (String.isBlank(this.metadataJson) && String.isNotBlank(jobRecord.Metadata_JSON__c)) {
                this.metadataJson = jobRecord.Metadata_JSON__c;
            }

            if (String.isBlank(this.csvCursorQuery) && String.isNotBlank(jobRecord.Cursor_Query_Id__c)) {
                this.csvCursorQuery = jobRecord.Cursor_Query_Id__c;
            }

            this.cachedConfig = getConfig(jobName);
            if (this.cachedConfig == null) {
                throw new CursorBatchException('No active config found for CSV job: ' + jobName);
            }
            this.processingType = CursorBatchContext.PROCESSING_TYPE_CSV;
            setLogger(CursorBatchLogger.resolveLogger(this.cachedConfig.Logger_Tag__c));

            logger.logInfo('CursorBatchCsvCallbackCoordinator processing callback for ' +
                jobName + ', csvCursorQuery=' + csvCursorQuery);

            Integer totalRecords = CsvCursorClient.getRowCount(csvCursorQuery);
            logger.logInfo('CursorBatchCsvCallbackCoordinator row count for ' + jobName + ': ' + totalRecords);

            attachFinalizer(jobRecord.Id, null);

            if (fanOutJob(jobRecord, csvCursorQuery, totalRecords, 0, this.cachedConfig)) {
                onComplete();
            }

        } catch (Exception e) {
            logger.logException('CursorBatchCsvCallbackCoordinator error for ' + jobName, e);
            throw e;
        } finally {
            currentAsyncJobId = null;
        }
    }

    public override String buildQuery() {
        return null;
    }

    public override String getWorkerClassName() {
        CursorBatch_Config__mdt config = this.cachedConfig != null ? this.cachedConfig : getConfig(jobName);
        if (config == null || String.isBlank(config.Worker_Class__c)) {
            throw new CursorBatchException(
                'CursorBatchCsvCallbackCoordinator requires Worker_Class__c in config for job: ' + jobName
            );
        }
        return config.Worker_Class__c;
    }
}
