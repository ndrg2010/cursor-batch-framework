/**
 * @description Sample coordinator demonstrating the parent/child pattern for avoiding
 *              record lock contention. This pattern queries PARENT records (Accounts)
 *              while the worker queries and processes CHILD records (Opportunities).
 * 
 * WHY THIS PATTERN?
 * When processing child records in parallel, record lock contention can occur if:
 * - Workers receive child records from the SAME parent across different batches
 * - Multiple workers try to update children of the same parent simultaneously
 * - Master-detail relationships or rollup summaries cause implicit parent locking
 * 
 * THE SOLUTION:
 * - Coordinator queries parent records (Accounts with qualifying Opportunities)
 * - Workers receive parent records and query their own child records
 * - All children of a given parent are processed by the SAME worker
 * - No cross-worker lock contention on parent records
 * 
 * USAGE:
 * 1. Create a CursorBatch_Config__mdt record with MasterLabel = 'SampleAccountOpportunityJob'
 * 2. Set Active__c = true, configure Parallel_Count__c and Page_Size__c as needed
 * 3. Execute: new SampleAccountOpportunityCoordinator().submit();
 * 
 * @group CursorBatchFramework Samples
 * @see SampleAccountOpportunityWorker
 * @see CursorBatchCoordinator
 */
public class SampleAccountOpportunityCoordinator extends CursorBatchCoordinator {
    
    // The Opportunity stage we want to process
    private static final String TARGET_STAGE = 'Prospecting';
    
    /**
     * @description Constructs the coordinator with the job name that must match
     *              a CursorBatch_Config__mdt record's MasterLabel.
     */
    public SampleAccountOpportunityCoordinator() {
        super('SampleAccountOpportunityJob');
    }
    
    /**
     * @description Builds the SOQL query for Account records that have Opportunities
     *              in the target stage. Uses a subquery to filter Accounts.
     * 
     *              KEY INSIGHT: We query Accounts (parents), not Opportunities (children).
     *              This ensures all Opportunities for a given Account are processed by
     *              the same worker, avoiding record lock contention.
     * 
     *              IMPORTANT: Use inline values, not bind variables - Database.Cursor
     *              does not support bind variables.
     * 
     * @return SOQL query string selecting Accounts with qualifying Opportunities
     */
    public override String buildQuery() {
        // Query Accounts that have at least one Opportunity in the target stage
        // The worker will query and process the actual Opportunities
        return 'SELECT Id, Name ' +
               'FROM Account ' +
               'WHERE Id IN (SELECT AccountId FROM Opportunity WHERE StageName = \'' + TARGET_STAGE + '\') ' +
               'ORDER BY Name ASC';
    }
    
    /**
     * @description Returns the fully qualified API name of the worker class.
     * @return Worker class name
     */
    public override String getWorkerClassName() {
        return 'SampleAccountOpportunityWorker';
    }
    
    /**
     * @description Called when the coordinator completes fanning out workers.
     */
    public override void onComplete() {
        super.onComplete();
        // Custom post-fanout logic
    }
    
    /**
     * @description Called when ALL workers have completed.
     * @param jobRecord The job tracking record with completion status
     */
    public override void finish(CursorBatch_Job__c jobRecord) {
        super.finish(jobRecord);
        
        if (jobRecord.Status__c == 'Completed') {
            // All Opportunities successfully processed
        } else if (jobRecord.Status__c == 'Completed with Errors') {
            // Some Accounts/Opportunities had errors
            // Consider: Send notification, retry failed Accounts, etc.
        }
    }
}

