/**
 * @description Helper for reducer-based shared state resolution, serialization, and reduction.
 * @group CursorBatchFramework
 */
public without sharing class CursorBatchStateManager {
    
    /** Maximum length of State_JSON__c (LongTextArea). Used to validate reduceState output before assignment. */
    public static final Integer STATE_JSON_MAX_LENGTH = 131072;
    
    /** Cache of reducer by job name per transaction. Null value means no reducer configured (avoids repeated config lookups). */
    private static Map<String, ICursorBatchStateReducer> reducerCache = new Map<String, ICursorBatchStateReducer>();
    
    /**
     * @description Creates and serializes the initial state for a job when a reducer is configured.
     * @param jobName Job identifier used to resolve reducer metadata
     * @param jobRecord The job record being initialized. Typically the job being created;
     *                  it may not be persisted yet (jobRecord.Id may be null).
     * @return Serialized initial state JSON, or null when no reducer is configured
     */
    public static String initializeState(String jobName, CursorBatch_Job__c jobRecord) {
        ICursorBatchStateReducer reducer = getReducer(jobName);
        if (reducer == null) {
            return null;
        }
        return reducer.serializeState(reducer.createInitialState(jobRecord));
    }
    
    /**
     * @description Deserializes the current state snapshot for worker processing or finish().
     * @param jobName Job identifier used to resolve reducer metadata
     * @param stateJson Persisted state JSON
     * @return Deserialized state object, or null
     */
    public static Object deserializeState(String jobName, String stateJson) {
        ICursorBatchStateReducer reducer = getReducer(jobName);
        return reducer != null ? reducer.deserializeState(stateJson) : null;
    }
    
    /**
     * @description Serializes a worker-produced delta for transport on completion events.
     * @param jobName Job identifier used to resolve reducer metadata
     * @param delta Worker-produced delta object
     * @return Serialized delta JSON, or null
     */
    public static String serializeDelta(String jobName, Object delta) {
        if (delta == null) {
            return null;
        }
        ICursorBatchStateReducer reducer = getReducer(jobName);
        return reducer != null ? reducer.serializeDelta(delta) : null;
    }
    
    /**
     * @description Applies a serialized delta to the current job state and returns the next state JSON.
     * @param jobRecord Job record holding the current persisted state
     * @param deltaJson Serialized worker delta from the completion event
     * @return Serialized merged state JSON
     */
    public static String reduceState(CursorBatch_Job__c jobRecord, String deltaJson) {
        ICursorBatchStateReducer reducer = getReducer(jobRecord?.Job_Name__c);
        if (reducer == null || String.isBlank(deltaJson)) {
            return jobRecord != null ? jobRecord.State_JSON__c : null;
        }
        
        Object currentState = reducer.deserializeState(jobRecord.State_JSON__c);
        Object delta = reducer.deserializeDelta(deltaJson);
        Object nextState = reducer.reduce(currentState, delta, jobRecord);
        return reducer.serializeState(nextState);
    }
    
    /**
     * @description Resolves the configured reducer class for the specified job.
     * @param jobName Job identifier used to look up config metadata
     * @return Reducer instance, or null when no reducer is configured
     * @throws CursorBatchCoordinator.CursorBatchException When the class cannot be resolved correctly
     */
    public static ICursorBatchStateReducer getReducer(String jobName) {
        if (String.isBlank(jobName)) {
            return null;
        }
        if (reducerCache.containsKey(jobName)) {
            return reducerCache.get(jobName);
        }
        
        CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig(jobName);
        String reducerClassName = config?.State_Reducer_Class__c;
        
        if (String.isBlank(reducerClassName)) {
            if (config != null && config.Enable_State_Reducer__c == true) {
                reducerClassName = 'CursorBatchCounterReducer';
            } else {
                reducerCache.put(jobName, null);
                return null;
            }
        }
        
        Type reducerType = Type.forName(reducerClassName);
        if (reducerType == null) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'State reducer class not found: ' + reducerClassName
            );
        }
        
        Object instance = reducerType.newInstance();
        if (!(instance instanceof ICursorBatchStateReducer)) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'State reducer class "' + reducerClassName +
                '" must implement ICursorBatchStateReducer'
            );
        }
        
        ICursorBatchStateReducer reducer = (ICursorBatchStateReducer) instance;
        reducerCache.put(jobName, reducer);
        return reducer;
    }
}
