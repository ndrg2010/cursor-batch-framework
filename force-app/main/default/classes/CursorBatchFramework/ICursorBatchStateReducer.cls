/**
 * @description Interface for reducer-based shared state in metadata-driven CursorJob batches.
 *              Implementations own the state shape, delta shape, and serialization strategy.
 * @group CursorBatchFramework
 */
public interface ICursorBatchStateReducer {
    
    /**
     * @description Creates the initial shared state for a job before any workers run.
     * @param jobRecord The job record being created
     * @return Initial state object; may be null
     */
    Object createInitialState(CursorBatch_Job__c jobRecord);
    
    /**
     * @description Merges a worker-produced delta into the current shared state.
     * @param currentState The current state object deserialized from the job record
     * @param delta The delta object deserialized from the worker completion event
     * @param jobRecord The job record being updated
     * @return The next state object to persist
     */
    Object reduce(Object currentState, Object delta, CursorBatch_Job__c jobRecord);
    
    /**
     * @description Serializes the shared state object for persistence on the job record.
     * @param state The state object to serialize
     * @return Serialized state JSON, or null
     */
    String serializeState(Object state);
    
    /**
     * @description Deserializes persisted shared state JSON from the job record.
     * @param stateJson Serialized state JSON
     * @return Deserialized state object, or null
     */
    Object deserializeState(String stateJson);
    
    /**
     * @description Serializes a worker-produced delta for inclusion in completion events.
     * @param delta The delta object to serialize
     * @return Serialized delta JSON, or null
     */
    String serializeDelta(Object delta);
    
    /**
     * @description Deserializes a worker-produced delta from a completion event.
     * @param deltaJson Serialized delta JSON
     * @return Deserialized delta object, or null
     */
    Object deserializeDelta(String deltaJson);
}
