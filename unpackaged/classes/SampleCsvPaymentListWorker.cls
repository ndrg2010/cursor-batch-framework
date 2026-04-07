/**
 * @description Sample CSV worker that processes a payment list file from external
 *              middleware. Demonstrates two key v0.20 CSV worker features:
 *
 *              1. CSV PROCESSING — extends CursorBatchCsvWorker to receive rows as
 *                 List<Map<String, Object>> keyed by CSV column headers:
 *                 Id, Payment Amount, Payment Date.
 *
 *              2. REDUCER SHARED STATE — accumulates a running total (sum of amounts)
 *                 and a past-due count (Payment Date < today) as per-page deltas for
 *                 the built-in CursorBatchCounterReducer.
 *
 *              On finish(), reads the aggregated state and metadata to update the
 *              originating Direct_Pay_Validation__c record with:
 *              - Status__c           = 'Completed'
 *              - Total_Payments__c   = sum of all Payment Amount values
 *              - Past_Due_Payments__c = count of rows where Payment Date < today
 *
 * SETUP (CursorBatch_Config__mdt):
 *   MasterLabel           = 'Process CSV Payment List'
 *   Worker_Class__c       = 'SampleCsvPaymentListWorker'
 *   State_Reducer_Class__c = 'CursorBatchCounterReducer'
 *   Processing_Type__c    = 'CSV'
 *   Active__c             = true
 *
 * EXECUTION:
 *   CursorJob.run('Process CSV Payment List', JSON.serialize(new Map<String, Object>{
 *       'recordId' => 'a0Bxx0000012345AAA'
 *   }));
 *
 * @group CursorBatchFramework Samples
 * @see CursorBatchCsvWorker
 * @see CursorBatchCounterReducer
 */
public class SampleCsvPaymentListWorker extends CursorBatchCsvWorker {

    private Decimal pageTotal = 0;
    private Integer pagePastDueCount = 0;

    /**
     * @description Processes a page of CSV payment rows. Accumulates per-page
     *              totals that buildStateDelta() emits for the reducer.
     * @param rows CSV rows keyed by column header (Id, Payment Amount, Payment Date)
     */
    public override void process(List<Map<String, Object>> rows) {
        pageTotal = 0;
        pagePastDueCount = 0;

        for (Map<String, Object> row : rows) {
            Decimal amount = toDecimal(row.get('Payment Amount'));
            Date paymentDate = toDate(row.get('Payment Date'));

            pageTotal += amount;
            if (paymentDate != null && paymentDate < Date.today()) {
                pagePastDueCount++;
            }
        }
    }

    /**
     * @description Emits incremental deltas after every successful page. The
     *              CursorBatchCounterReducer sums these across all workers.
     */
    protected override Object buildStateDelta() {
        return new Map<String, Object>{
            'total' => pageTotal,
            'pastDuePayments' => pagePastDueCount
        };
    }

    /**
     * @description Called once after ALL workers complete. Reads the final reducer
     *              state and posts totals back to the originating Direct_Pay_Validation__c
     *              record identified by metadata.recordId.
     */
    public override void finish(CursorBatch_Job__c jobRecord) {
        Map<String, Object> state = getCurrentState();
        Map<String, Object> meta  = getMetadata();
        if (state == null || meta == null) {
            return;
        }

        logger.logInfo('SampleCsvPaymentListWorker finished — total: ' +
            state.get('total') + ', past due: ' + state.get('pastDuePayments'));

        update new Direct_Pay_Validation__c(
            Id = (Id) meta.get('recordId'),
            Status__c = 'Completed',
            Past_Due_Payments__c = toDecimal(state.get('pastDuePayments')),
            Total_Payments__c = toDecimal(state.get('total'))
        );
    }
}
