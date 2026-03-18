/**
 * @description Sample query builder for a reducer-enabled CursorJob.
 *              Use this with CursorJob and SampleStatefulLeadWorker to demonstrate
 *              reducer-managed shared state across worker pages.
 *
 * SETUP:
 * - Create a CursorBatch_Config__mdt record with MasterLabel = 'SampleStatefulLeadJob'
 * - Set Query_Builder_Class__c = 'SampleStatefulLeadQueryBuilder'
 * - Set Query_Builder_Method__c = 'buildOpenLeadQuery'
 * - Set Worker_Class__c = 'SampleStatefulLeadWorker'
 * - Set State_Reducer_Class__c = 'SampleStatefulLeadReducer'
 * - Set Active__c = true
 *
 * EXECUTION:
 * CursorJob.run('SampleStatefulLeadJob');
 *
 * @group CursorBatchFramework Samples
 * @see SampleStatefulLeadWorker
 * @see SampleStatefulLeadReducer
 * @see CursorJob
 */
public class SampleStatefulLeadQueryBuilder implements ICursorBatchQueryBuilder {
    
    /**
     * @description Routes metadata-configured method names to the actual query builder.
     * @param methodName Method name from CursorBatch_Config__mdt
     * @return SOQL query string or null if the method name is unsupported
     */
    public String buildQuery(String methodName) {
        switch on methodName {
            when 'buildOpenLeadQuery' {
                return buildOpenLeadQuery();
            }
            when else {
                return null;
            }
        }
    }
    
    /**
     * @description Builds the query for Leads to process.
     * @return SOQL query string for Leads in the initial open status
     */
    public String buildOpenLeadQuery() {
        return 'SELECT Id, FirstName, LastName, Email, Status, Company ' +
               'FROM Lead ' +
               'WHERE Status = \'Open - Not Contacted\' ' +
               'ORDER BY CreatedDate ASC';
    }
}
