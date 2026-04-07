/**
 * @description Sample query builder that receives a Payment List record ID at runtime
 *              and scopes the cursor query to that list's payments.
 *
 *              Implements ICursorBatchMetadataQueryBuilder (not ICursorBatchQueryBuilder)
 *              so the framework passes the metadataJson from CursorJob.run() as the
 *              second argument to buildQuery(). This is how you inject runtime values
 *              into a Database.Cursor query (which does not support bind variables).
 *
 * SETUP:
 * - Create CursorBatch_Config__mdt with MasterLabel = 'Process Payment List'
 * - Set Query_Builder_Class__c  = 'SampleMetadataPaymentQueryBuilder'
 * - Set Query_Builder_Method__c = 'buildPaymentsForListQuery'
 * - Set Worker_Class__c         = 'SampleStatefulMetadataPaymentWorker'
 * - Set State_Reducer_Class__c  = 'CursorBatchCounterReducer'
 * - Set Active__c = true
 *
 * EXECUTION:
 * CursorJob.run('Process Payment List', JSON.serialize(new Map<String, Object>{
 *     'paymentListId' => 'a00xx0000012345AAA'
 * }));
 *
 * NOTE: This sample uses Opportunity as a stand-in for a Payment custom object.
 *       Replace Opportunity / CloseDate with your custom object and fields
 *       (e.g., Payment__c / Payment_Date__c).
 *
 * @group CursorBatchFramework Samples
 * @see SampleStatefulMetadataPaymentWorker
 * @see CursorBatchCounterReducer
 * @see ICursorBatchMetadataQueryBuilder
 */
public class SampleMetadataPaymentQueryBuilder implements ICursorBatchMetadataQueryBuilder {

    /**
     * @description Routes the method name from CursorBatch_Config__mdt.Query_Builder_Method__c
     *              to the actual builder, passing the runtime metadata JSON.
     * @param methodName Method name configured in metadata
     * @param metadataJson JSON from CursorJob.run(name, metadataJson), or null
     * @return SOQL query string with inlined values (no bind variables)
     */
    public String buildQuery(String methodName, String metadataJson) {
        switch on methodName {
            when 'buildPaymentsForListQuery' {
                return buildPaymentsForListQuery(metadataJson);
            }
            when else {
                return null;
            }
        }
    }

    private String buildPaymentsForListQuery(String metadataJson) {
        if (String.isBlank(metadataJson)) {
            return null;
        }

        Map<String, Object> meta = (Map<String, Object>) JSON.deserializeUntyped(metadataJson);
        String paymentListId = (String) meta.get('paymentListId');

        if (String.isBlank(paymentListId)) {
            return null;
        }

        return 'SELECT Id, Name, CloseDate, Amount, StageName, AccountId ' +
               'FROM Opportunity ' +
               'WHERE AccountId = \'' + String.escapeSingleQuotes(paymentListId) + '\' ' +
               'ORDER BY CloseDate ASC';
    }
}
