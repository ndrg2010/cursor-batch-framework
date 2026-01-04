/**
 * @description Sample worker demonstrating the parent/child pattern for avoiding
 *              record lock contention. Receives Account (parent) records from the
 *              coordinator, then queries and updates their Opportunities (children).
 * 
 * WHY THIS PATTERN WORKS:
 * - The coordinator queries Accounts, distributing them across workers
 * - Each worker queries Opportunities ONLY for its assigned Accounts
 * - All Opportunities for a given Account are processed by the SAME worker
 * - No risk of UNABLE_TO_LOCK_ROW errors from concurrent parent access
 * 
 * CONTRAST WITH DIRECT CHILD QUERY (ANTI-PATTERN):
 * If the coordinator queried Opportunities directly and distributed them:
 * - Worker 1 might get Opportunity A from Account X
 * - Worker 2 might get Opportunity B from Account X
 * - Both workers update children of Account X simultaneously
 * - Record lock contention occurs, causing UNABLE_TO_LOCK_ROW errors
 * 
 * WHEN TO USE THIS PATTERN:
 * - Master-detail relationships (child DML locks the parent)
 * - Rollup summary fields (parent recalculates during child DML)
 * - Any parent/child relationship where concurrent child updates cause locking
 * 
 * @group CursorBatchFramework Samples
 * @see SampleAccountOpportunityCoordinator
 * @see CursorBatchWorker
 */
public class SampleAccountOpportunityWorker extends CursorBatchWorker {
    
    // Must match the target stage used in the coordinator's query
    private static final String TARGET_STAGE = 'Prospecting';
    private static final String NEW_STAGE = 'Qualification';
    
    /**
     * @description Default constructor required for reflection-based instantiation.
     */
    public SampleAccountOpportunityWorker() {
        super();
    }
    
    /**
     * @description Processes a batch of Account records by querying and updating
     *              their child Opportunities. This is the key to the parent/child
     *              pattern: we receive parents but process children.
     * 
     * @param records List of Account SObjects (parents) to process
     */
    public override void process(List<SObject> records) {
        List<Account> accounts = (List<Account>) records;
        
        // Extract Account IDs for the child query
        Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();
        
        // Query child Opportunities for these specific Accounts
        // This ensures all Opportunities for each Account are processed together
        List<Opportunity> opportunities = [
            SELECT Id, Name, StageName, AccountId, Amount
            FROM Opportunity
            WHERE AccountId IN :accountIds
            AND StageName = :TARGET_STAGE
        ];
        
        if (opportunities.isEmpty()) {
            // No Opportunities to process for this batch of Accounts
            // This can happen if Opportunities were updated between coordinator
            // query time and worker execution (cursor snapshot behavior)
            return;
        }
        
        // Process the Opportunities
        for (Opportunity opp : opportunities) {
            // Move Opportunities to the next stage
            opp.StageName = NEW_STAGE;
            
            // Add your business logic here:
            // - Update Amount, CloseDate, or other fields
            // - Create Tasks or follow-up activities
            // - Integrate with external systems
        }
        
        // Update all Opportunities for these Accounts in a single DML
        // Since all Opportunities per Account are in this worker, no lock contention
        update opportunities;
    }
    
    /**
     * @description Called when this worker finishes ALL its assigned pages.
     */
    public override void onComplete() {
        super.onComplete();
        // Per-worker completion logic
    }
}

