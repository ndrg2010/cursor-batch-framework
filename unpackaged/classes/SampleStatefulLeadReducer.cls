/**
 * @description Sample reducer that tracks aggregate progress for a stateful CursorJob.
 *              The shared state is stored as JSON on CursorBatch_Job__c.State_JSON__c.
 *
 * STATE SHAPE:
 * {
 *   "processedCount": 0,
 *   "contactedCount": 0,
 *   "pagesProcessed": 0
 * }
 *
 * DELTA SHAPE:
 * {
 *   "processedCount": <records in current page>,
 *   "contactedCount": <records updated in current page>,
 *   "pagesProcessed": 1
 * }
 *
 * @group CursorBatchFramework Samples
 * @see SampleStatefulLeadWorker
 * @see ICursorBatchStateReducer
 */
public class SampleStatefulLeadReducer implements ICursorBatchStateReducer {
    
    public Object createInitialState(CursorBatch_Job__c jobRecord) {
        return new Map<String, Object>{
            'processedCount' => 0,
            'contactedCount' => 0,
            'pagesProcessed' => 0
        };
    }
    
    public Object reduce(Object currentState, Object delta, CursorBatch_Job__c jobRecord) {
        Map<String, Object> state = currentState != null
            ? (Map<String, Object>) currentState
            : (Map<String, Object>) createInitialState(jobRecord);
        Map<String, Object> deltaMap = delta != null
            ? (Map<String, Object>) delta
            : new Map<String, Object>();
        
        state.put('processedCount', asInteger(state.get('processedCount')) + asInteger(deltaMap.get('processedCount')));
        state.put('contactedCount', asInteger(state.get('contactedCount')) + asInteger(deltaMap.get('contactedCount')));
        state.put('pagesProcessed', asInteger(state.get('pagesProcessed')) + asInteger(deltaMap.get('pagesProcessed')));
        return state;
    }
    
    public String serializeState(Object state) {
        return state != null ? JSON.serialize(state) : null;
    }
    
    public Object deserializeState(String stateJson) {
        return String.isNotBlank(stateJson) ? JSON.deserializeUntyped(stateJson) : null;
    }
    
    public String serializeDelta(Object delta) {
        return delta != null ? JSON.serialize(delta) : null;
    }
    
    public Object deserializeDelta(String deltaJson) {
        return String.isNotBlank(deltaJson) ? JSON.deserializeUntyped(deltaJson) : null;
    }
    
    private Integer asInteger(Object value) {
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
