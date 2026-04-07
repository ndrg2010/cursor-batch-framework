/**
 * @description Unit tests for CursorBatchCounterReducer.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCounterReducerTest {

    private static final CursorBatchCounterReducer reducer = new CursorBatchCounterReducer();

    @IsTest
    static void testCreateInitialStateReturnsEmptyMap() {
        Object state = reducer.createInitialState(null);
        Assert.isInstanceOfType(state, Map<String, Object>.class, 'Should return a Map');
        Assert.isTrue(((Map<String, Object>) state).isEmpty(), 'Initial state should be empty');
    }

    @IsTest
    static void testReduceSumsMatchingKeys() {
        Map<String, Object> state = new Map<String, Object>{ 'count' => 5, 'errors' => 2 };
        Map<String, Object> delta = new Map<String, Object>{ 'count' => 3, 'errors' => 1 };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(state, delta, null);

        Assert.areEqual(8, result.get('count'), 'count should be summed');
        Assert.areEqual(3, result.get('errors'), 'errors should be summed');
    }

    @IsTest
    static void testReduceAddsNewKeysFromDelta() {
        Map<String, Object> state = new Map<String, Object>{ 'existing' => 10 };
        Map<String, Object> delta = new Map<String, Object>{ 'newKey' => 7 };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(state, delta, null);

        Assert.areEqual(10, result.get('existing'), 'Existing key should be preserved');
        Assert.areEqual(7, result.get('newKey'), 'New key from delta should be added');
    }

    @IsTest
    static void testReducePreservesStateKeysNotInDelta() {
        Map<String, Object> state = new Map<String, Object>{
            'kept' => 42, 'alsoKept' => 99
        };
        Map<String, Object> delta = new Map<String, Object>{ 'kept' => 8 };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(state, delta, null);

        Assert.areEqual(50, result.get('kept'), 'Matching key should be summed');
        Assert.areEqual(99, result.get('alsoKept'), 'Key absent from delta should be unchanged');
    }

    @IsTest
    static void testReduceWithNullStateCreatesFromDelta() {
        Map<String, Object> delta = new Map<String, Object>{ 'pages' => 1, 'records' => 25 };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(null, delta, null);

        Assert.areEqual(1, result.get('pages'), 'Should start from 0 and add delta');
        Assert.areEqual(25, result.get('records'), 'Should start from 0 and add delta');
    }

    @IsTest
    static void testReduceWithNullDeltaPreservesState() {
        Map<String, Object> state = new Map<String, Object>{ 'total' => 100 };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(state, null, null);

        Assert.areEqual(100, result.get('total'), 'State should be unchanged when delta is null');
    }

    @IsTest
    static void testReduceWithBothNull() {
        Map<String, Object> result = (Map<String, Object>) reducer.reduce(null, null, null);
        Assert.isTrue(result.isEmpty(), 'Should return empty map when both inputs are null');
    }

    @IsTest
    static void testReduceHandlesMixedNumericTypes() {
        Map<String, Object> state = new Map<String, Object>{
            'intVal' => 10,
            'decVal' => 3.5,
            'longVal' => 100000000000L
        };
        Map<String, Object> delta = new Map<String, Object>{
            'intVal' => 5,
            'decVal' => 1.5,
            'longVal' => 1
        };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(state, delta, null);

        Assert.areEqual(15, result.get('intVal'), 'Integer values should sum correctly');
        Assert.areEqual(5.0, result.get('decVal'), 'Decimal values should sum correctly');
        Assert.areEqual(100000000001L, result.get('longVal'), 'Long values should sum correctly');
    }

    @IsTest
    static void testReduceHandlesNullValuesInDelta() {
        Map<String, Object> state = new Map<String, Object>{ 'count' => 10 };
        Map<String, Object> delta = new Map<String, Object>{ 'count' => null };

        Map<String, Object> result = (Map<String, Object>) reducer.reduce(state, delta, null);

        Assert.areEqual(10, result.get('count'), 'Null delta value should be treated as 0');
    }

    @IsTest
    static void testSerializeAndDeserializeStateRoundTrip() {
        Map<String, Object> state = new Map<String, Object>{ 'a' => 1, 'b' => 2 };

        String json = reducer.serializeState(state);
        Map<String, Object> restored = (Map<String, Object>) reducer.deserializeState(json);

        Assert.areEqual(1, restored.get('a'), 'Key a should round-trip');
        Assert.areEqual(2, restored.get('b'), 'Key b should round-trip');
    }

    @IsTest
    static void testSerializeAndDeserializeDeltaRoundTrip() {
        Map<String, Object> delta = new Map<String, Object>{ 'processed' => 50 };

        String json = reducer.serializeDelta(delta);
        Map<String, Object> restored = (Map<String, Object>) reducer.deserializeDelta(json);

        Assert.areEqual(50, restored.get('processed'), 'Delta should round-trip');
    }

    @IsTest
    static void testSerializeNullReturnsNull() {
        Assert.areEqual(null, reducer.serializeState(null), 'Null state should serialize to null');
        Assert.areEqual(null, reducer.serializeDelta(null), 'Null delta should serialize to null');
    }

    @IsTest
    static void testDeserializeBlankReturnsNull() {
        Assert.areEqual(null, reducer.deserializeState(null), 'Null JSON should deserialize to null');
        Assert.areEqual(null, reducer.deserializeState(''), 'Empty JSON should deserialize to null');
        Assert.areEqual(null, reducer.deserializeDelta(null), 'Null JSON should deserialize to null');
        Assert.areEqual(null, reducer.deserializeDelta(''), 'Empty JSON should deserialize to null');
    }

    @IsTest
    static void testMultipleReduceCallsAccumulate() {
        Map<String, Object> delta1 = new Map<String, Object>{ 'pages' => 1, 'records' => 10 };
        Map<String, Object> delta2 = new Map<String, Object>{ 'pages' => 1, 'records' => 15, 'errors' => 2 };
        Map<String, Object> delta3 = new Map<String, Object>{ 'pages' => 1, 'records' => 8 };

        Object state = reducer.createInitialState(null);
        state = reducer.reduce(state, delta1, null);
        state = reducer.reduce(state, delta2, null);
        state = reducer.reduce(state, delta3, null);

        Map<String, Object> result = (Map<String, Object>) state;
        Assert.areEqual(3, result.get('pages'), 'Pages should accumulate across 3 deltas');
        Assert.areEqual(33, result.get('records'), 'Records should accumulate across 3 deltas');
        Assert.areEqual(2, result.get('errors'), 'Errors key introduced in delta2 should be present');
    }

    @IsTest
    static void testFullSerializeDeserializeReduceCycle() {
        Object state = reducer.createInitialState(null);
        String stateJson = reducer.serializeState(state);

        Map<String, Object> delta = new Map<String, Object>{ 'count' => 5 };
        String deltaJson = reducer.serializeDelta(delta);

        Object deserializedState = reducer.deserializeState(stateJson);
        Object deserializedDelta = reducer.deserializeDelta(deltaJson);
        Object nextState = reducer.reduce(deserializedState, deserializedDelta, null);

        String nextStateJson = reducer.serializeState(nextState);
        Map<String, Object> finalState = (Map<String, Object>) reducer.deserializeState(nextStateJson);
        Assert.areEqual(5, finalState.get('count'), 'Full cycle should produce correct result');
    }

    @IsTest
    static void testReduceThrowsOnNonNumericValue() {
        Map<String, Object> state = new Map<String, Object>();
        Map<String, Object> delta = new Map<String, Object>{ 'bad' => 'not-a-number' };

        try {
            reducer.reduce(state, delta, null);
            Assert.isTrue(false, 'Should throw for non-numeric value');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('non-numeric'), 'Message should mention non-numeric');
            Assert.isTrue(e.getMessage().contains('bad'), 'Message should name the key');
        }
    }

    // ============== Enable_State_Reducer__c Resolution Tests ==============

    @IsTest
    static void testGetReducerReturnsCounterReducerWhenCheckboxTrueAndNoClass() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('CheckboxJob', 1, 10);
        config.Enable_State_Reducer__c = true;
        CursorBatchCoordinator.testConfig = config;

        ICursorBatchStateReducer result = CursorBatchStateManager.getReducer('CheckboxJob');

        Assert.isNotNull(result, 'Reducer should be returned when checkbox is true');
        Assert.isInstanceOfType(result, CursorBatchCounterReducer.class,
            'Should resolve to CursorBatchCounterReducer when checkbox is true and no class set');
    }

    @IsTest
    static void testGetReducerReturnsNullWhenCheckboxFalseAndNoClass() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('NoReducerJob', 1, 10);
        config.Enable_State_Reducer__c = false;
        CursorBatchCoordinator.testConfig = config;

        ICursorBatchStateReducer result = CursorBatchStateManager.getReducer('NoReducerJob');

        Assert.isNull(result, 'Reducer should be null when checkbox is false and no class set');
    }

    @IsTest
    static void testGetReducerUsesExplicitClassWhenCheckboxTrue() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('ExplicitClassJob', 1, 10);
        config.Enable_State_Reducer__c = true;
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;

        ICursorBatchStateReducer result = CursorBatchStateManager.getReducer('ExplicitClassJob');

        Assert.isNotNull(result, 'Reducer should be returned');
        Assert.isInstanceOfType(result, CursorBatchTestUtils.TestStateReducer.class,
            'Explicit State_Reducer_Class__c should take priority over checkbox default');
    }

    @IsTest
    static void testGetReducerUsesExplicitClassWhenCheckboxFalse() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('ExplicitNoCheckboxJob', 1, 10);
        config.Enable_State_Reducer__c = false;
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;

        ICursorBatchStateReducer result = CursorBatchStateManager.getReducer('ExplicitNoCheckboxJob');

        Assert.isNotNull(result, 'Reducer should be returned when explicit class is set');
        Assert.isInstanceOfType(result, CursorBatchTestUtils.TestStateReducer.class,
            'Explicit class should be used regardless of checkbox state');
    }

    @IsTest
    static void testInitializeStateWithCheckboxProducesInitialState() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('InitStateJob', 1, 10);
        config.Enable_State_Reducer__c = true;
        CursorBatchCoordinator.testConfig = config;

        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = 'InitStateJob',
            Status__c = 'Preparing'
        );
        String stateJson = CursorBatchStateManager.initializeState('InitStateJob', job);

        Assert.isNotNull(stateJson, 'Initial state JSON should be produced when checkbox is enabled');
        Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(stateJson);
        Assert.isTrue(state.isEmpty(), 'CursorBatchCounterReducer initial state should be an empty map');
    }

    @IsTest
    static void testInitializeStateWithCheckboxFalseReturnsNull() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('NoInitStateJob', 1, 10);
        config.Enable_State_Reducer__c = false;
        CursorBatchCoordinator.testConfig = config;

        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = 'NoInitStateJob',
            Status__c = 'Preparing'
        );
        String stateJson = CursorBatchStateManager.initializeState('NoInitStateJob', job);

        Assert.isNull(stateJson, 'No initial state should be produced when checkbox is false and no class set');
    }
}
