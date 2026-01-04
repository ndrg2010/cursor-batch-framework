/**
 * @description Sample worker demonstrating the simple single-object pattern.
 *              Processes Lead records received from SampleLeadCoordinator,
 *              updating their Status to 'Working - Contacted'.
 * 
 * This is the most common pattern where:
 * - Coordinator queries the records to process
 * - Worker receives those records and performs the business logic
 * - Worker updates the same records it received
 * 
 * @group CursorBatchFramework Samples
 * @see SampleLeadCoordinator
 * @see CursorBatchWorker
 */
public class SampleLeadWorker extends CursorBatchWorker {
    
    /**
     * @description Default constructor required for reflection-based instantiation.
     *              The framework creates worker instances dynamically using Type.forName().
     */
    public SampleLeadWorker() {
        super();
        // Optionally set a custom logger:
        // setLogger(NebulaLoggerAdapterForCursorBatch.getInstance());
    }
    
    /**
     * @description Processes a batch of Lead records. This method is called once
     *              per page of records. The worker may process multiple pages if
     *              assigned a range larger than the page size.
     * 
     *              To request a retry of the current page (e.g., on rate limiting),
     *              throw CursorBatchRetryException.
     * 
     * @param records List of Lead SObjects to process
     * @throws CursorBatchRetryException When retry is needed (e.g., external callout rate limited)
     */
    public override void process(List<SObject> records) {
        List<Lead> leads = (List<Lead>) records;
        
        // Example: Update Lead status to indicate they've been processed
        for (Lead lead : leads) {
            lead.Status = 'Working - Contacted';
            // Add your business logic here:
            // - Enrich data from external sources
            // - Calculate field values
            // - Prepare for campaign assignment
        }
        
        // Perform DML - the framework handles errors via finalizers
        update leads;
        
        // Example: If making external callouts, handle rate limiting with retry
        // HttpResponse response = callExternalService(leads);
        // if (response.getStatusCode() == 429) {
        //     throw CursorBatchRetryException.create('Rate limited by external service', 5);
        // }
    }
    
    /**
     * @description Called when this worker finishes ALL its assigned pages.
     *              Override for custom cleanup or logging. Note: This is called
     *              per-worker, not when the entire job completes.
     */
    public override void onComplete() {
        super.onComplete();
        // Add custom per-worker completion logic here
    }
}

