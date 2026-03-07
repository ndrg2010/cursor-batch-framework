/**
 * @description Sample worker for reducer-based shared state with CursorJob.
 *              It reads the current state snapshot before processing each page,
 *              updates Lead records, and emits a delta for centralized reduction.
 *
 * EXECUTION:
 * CursorJob.run('SampleStatefulLeadJob');
 *
 * @group CursorBatchFramework Samples
 * @see SampleStatefulLeadQueryBuilder
 * @see SampleStatefulLeadReducer
 * @see CursorBatchWorker
 */
public class SampleStatefulLeadWorker extends CursorBatchWorker {
    
    private Integer lastProcessedCount = 0;
    
    public SampleStatefulLeadWorker() {
        super();
    }
    
    /**
     * @description Processes Lead records and demonstrates reading the reducer state snapshot.
     * @param records Current page of Lead records
     */
    public override void process(List<SObject> records) {
        List<Lead> leads = (List<Lead>) records;
        Map<String, Object> state = (Map<String, Object>) getCurrentState();
        
        // Example of reading the latest reduced snapshot before this page starts.
        Integer alreadyProcessed = state != null && state.containsKey('processedCount')
            ? toInteger(state.get('processedCount'))
            : 0;
        logger.logInfo('SampleStatefulLeadWorker starting page with processedCount=' + alreadyProcessed);
        
        for (Lead lead : leads) {
            lead.Status = 'Working - Contacted';
        }
        update leads;
        
        lastProcessedCount = leads.size();
    }
    
    /**
     * @description Returns a reducer delta for this successfully processed page.
     * @param records Current page of Lead records
     * @return Delta map to merge into the job state
     */
    protected override Object buildStateDelta(List<SObject> records) {
        return new Map<String, Object>{
            'processedCount' => lastProcessedCount,
            'contactedCount' => lastProcessedCount,
            'pagesProcessed' => 1
        };
    }
    
    /**
     * @description Called after all workers complete. Demonstrates reading the final reduced state.
     * @param jobRecord Completed job record with the final State_JSON__c persisted by the framework
     */
    public override void finish(CursorBatch_Job__c jobRecord) {
        Map<String, Object> finalState = (Map<String, Object>) getCurrentState();
        if (finalState == null) {
            logger.logInfo('SampleStatefulLeadWorker finished with no reducer state available');
            return;
        }
        
        Integer processedCount = toInteger(finalState.get('processedCount'));
        Integer contactedCount = toInteger(finalState.get('contactedCount'));
        Integer pagesProcessed = toInteger(finalState.get('pagesProcessed'));
        
        logger.logInfo(
            'SampleStatefulLeadWorker finished. processedCount=' + processedCount +
            ', contactedCount=' + contactedCount +
            ', pagesProcessed=' + pagesProcessed
        );
    }
    
    private Integer toInteger(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        return Integer.valueOf(String.valueOf(value));
    }
}
