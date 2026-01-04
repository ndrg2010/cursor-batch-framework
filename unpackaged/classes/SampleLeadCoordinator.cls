/**
 * @description Sample coordinator demonstrating the simple single-object pattern.
 *              Queries Lead records with Status = 'Open - Not Contacted' and processes
 *              them via SampleLeadWorker. This is the most common usage pattern where
 *              the coordinator queries records and the worker processes them directly.
 * 
 * USAGE:
 * 1. Create a CursorBatch_Config__mdt record with MasterLabel = 'SampleLeadJob'
 * 2. Set Active__c = true, configure Parallel_Count__c and Page_Size__c as needed
 * 3. Execute: new SampleLeadCoordinator().submit();
 * 
 * @group CursorBatchFramework Samples
 * @see SampleLeadWorker
 * @see CursorBatchCoordinator
 */
public class SampleLeadCoordinator extends CursorBatchCoordinator {
    
    /**
     * @description Constructs the coordinator with the job name that must match
     *              a CursorBatch_Config__mdt record's MasterLabel.
     */
    public SampleLeadCoordinator() {
        super('SampleLeadJob');
    }
    
    /**
     * @description Builds the SOQL query for Lead records to process.
     *              IMPORTANT: Use inline values, not bind variables - Database.Cursor
     *              does not support bind variables.
     * @return SOQL query string selecting Leads with Status = 'Open - Not Contacted'
     */
    public override String buildQuery() {
        // Query Leads that need to be contacted
        // Customize this query based on your business requirements
        return 'SELECT Id, FirstName, LastName, Email, Status, Company ' +
               'FROM Lead ' +
               'WHERE Status = \'Open - Not Contacted\' ' +
               'ORDER BY CreatedDate ASC';
    }
    
    /**
     * @description Returns the fully qualified API name of the worker class.
     *              The worker class must extend CursorBatchWorker and have a
     *              public no-argument constructor.
     * @return Worker class name
     */
    public override String getWorkerClassName() {
        return 'SampleLeadWorker';
    }
    
    /**
     * @description Called when the coordinator completes fanning out workers.
     *              Override for custom post-fanout logic (e.g., notifications).
     */
    public override void onComplete() {
        super.onComplete();
        // Add custom logic here, e.g.:
        // - Send notification that processing has started
        // - Log to external system
    }
    
    /**
     * @description Called when ALL workers have completed (success or failure).
     *              Use this for job chaining, sending completion notifications,
     *              or cleanup tasks.
     * @param jobRecord The job tracking record with completion status and metrics
     */
    public override void finish(CursorBatch_Job__c jobRecord) {
        super.finish(jobRecord);
        
        // Example: Handle different completion statuses
        if (jobRecord.Status__c == 'Completed') {
            // All workers succeeded - trigger next steps
            // new NextJobCoordinator().submit();
        } else if (jobRecord.Status__c == 'Completed with Errors') {
            // Partial success - some workers failed
            // Check jobRecord.Failed_Workers__c for count
            // Send alert notification
        } else if (jobRecord.Status__c == 'Failed') {
            // All workers failed
            // Check jobRecord.Error_Message__c for details
        }
    }
}

