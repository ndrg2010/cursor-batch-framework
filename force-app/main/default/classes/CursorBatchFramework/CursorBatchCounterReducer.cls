/**
 * @description Built-in default reducer for the most common shared-state pattern: summing
 *              numeric counters by key. Both state and delta are Map<String, Object> where
 *              every value is a number. reduce() merges by adding matching keys; new delta
 *              keys are added to state and existing state keys absent from the delta are
 *              preserved.
 *
 *              This reducer is used automatically when Enable_State_Reducer__c is checked
 *              on the CursorBatch_Config__mdt and no custom State_Reducer_Class__c is set.
 *              Workers emit deltas via buildStateDelta():
 *                return new Map<String, Object>{ 'processedCount' => lastPageSize, 'errorCount' => 2 };
 *
 * @group CursorBatchFramework
 * @see ICursorBatchStateReducer
 */
public class CursorBatchCounterReducer implements ICursorBatchStateReducer {

    public Object createInitialState(CursorBatch_Job__c jobRecord) {
        return new Map<String, Object>();
    }

    public Object reduce(Object currentState, Object delta, CursorBatch_Job__c jobRecord) {
        Map<String, Object> state = currentState != null
            ? new Map<String, Object>((Map<String, Object>) currentState)
            : new Map<String, Object>();
        Map<String, Object> deltaMap = delta != null
            ? (Map<String, Object>) delta
            : new Map<String, Object>();

        for (String key : deltaMap.keySet()) {
            state.put(key, toDecimal(key, state.get(key)) + toDecimal(key, deltaMap.get(key)));
        }
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

    private Decimal toDecimal(String key, Object value) {
        if (value == null) return 0;
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer) return (Decimal) ((Integer) value);
        if (value instanceof Long) return (Decimal) ((Long) value);
        if (value instanceof Double) return Decimal.valueOf((Double) value);
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'CursorBatchCounterReducer: non-numeric value for key "' + key +
                '": ' + String.valueOf(value) + ' (' + CursorBatchContext.getClassName(value) + ')'
            );
        }
    }
}
