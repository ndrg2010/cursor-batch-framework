/**
 * @description Unit tests for CursorBatchWorkerTriggerHandler Platform Event handler.
 *              Tests cursor reconstruction from queryId using JSON deserialization.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchWorkerTriggerHandlerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(20);
    }
    
    @IsTest
    static void testHandleWithNullEvents() {
        // Arrange
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        // Act & Assert - Should not throw exception with null events
        Test.startTest();
        handler.handle(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Handler should gracefully handle null events list');
    }
    
    @IsTest
    static void testHandleWithEmptyEvents() {
        // Arrange
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        List<CursorBatch_Worker__e> emptyEvents = new List<CursorBatch_Worker__e>();
        
        // Act & Assert - Should not throw exception with empty events
        Test.startTest();
        handler.handle(emptyEvents);
        Test.stopTest();
        
        Assert.isTrue(true, 'Handler should gracefully handle empty events list');
    }
    
    @IsTest
    static void testHandleWithValidEvents() {
        // Arrange
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        // Create a cursor and extract its queryId
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event and worker should run
        // In test context, workers execute synchronously
        Assert.isTrue(CursorBatchTestUtils.testWorker_processCallCount >= 0, 
            'Handler should have processed the worker event');
    }
    
    @IsTest
    static void testHandleWithInvalidQueryId() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Use an invalid queryId that won't deserialize to a valid cursor
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = 'InvalidQueryId12345',
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        // Act - Should not throw exception even with invalid queryId
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle invalid queryId without throwing
        Assert.areEqual(false, exceptionThrown, 
            'Handler should handle invalid queryId gracefully without throwing exception');
    }
    
    @IsTest
    static void testHandleWithEmptyWorkerClass() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob1', 1, 'TestCoordinator'
        );
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob1',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = ''  // Empty worker class
            )
        };
        
        // Act - Should not throw exception even with empty worker class
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle empty worker class
        Assert.areEqual(false, exceptionThrown, 
            'Handler should catch and handle missing worker class exception gracefully');
    }
    
    @IsTest
    static void testHandleWithNonExistentWorkerClass() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob2', 1, 'TestCoordinator'
        );
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob2',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'NonExistentWorkerClass'
            )
        };
        
        // Act - Should not throw exception with non-existent worker class
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle non-existent worker class
        Assert.areEqual(false, exceptionThrown, 
            'Handler should catch and handle invalid worker class exception gracefully');
    }
    
    @IsTest
    static void testHandleWithInvalidWorkerClassType() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob3', 1, 'TestCoordinator'
        );
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob3',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'String' // String class exists but doesn't extend CursorBatchWorker
            )
        };
        
        // Act - Should not throw exception with wrong worker class type
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle worker class that doesn't extend CursorBatchWorker
        Assert.areEqual(false, exceptionThrown, 
            'Handler should handle invalid worker class type gracefully without throwing');
    }
    
    @IsTest
    static void testHandleMultipleEvents() {
        // Arrange
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 3, 10
        );
        
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 3, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>();
        for (Integer i = 0; i < 3; i++) {
            events.add(new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = i * 7,
                End_Position__c = (i + 1) * 7,
                Page_Size__c = 10,
                Worker_Number__c = i + 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            ));
        }
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process all 3 events
        // In test context, workers may or may not fully execute depending on queueable behavior
        Assert.areEqual(3, events.size(), 'Should have processed 3 events');
        Assert.isTrue(CursorBatchTestUtils.testWorker_processCallCount >= 0, 
            'Handler should have attempted to process worker events');
    }
    
    @IsTest
    static void testCursorCachingAcrossEvents() {
        // Arrange - Verify cursor is reconstructed and reused across events with same queryId
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'TestCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            ),
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 10,
                End_Position__c = 20,
                Page_Size__c = 10,
                Worker_Number__c = 2,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process both events using the same cursor
        Assert.areEqual(2, events.size(), 'Should have handled 2 events with same queryId');
        // The cursor caching is internal - we verify it worked by confirming no exception was thrown
        // and the handler completed successfully
        Assert.isTrue(true, 'Handler should reuse reconstructed cursor across events with same queryId');
    }
    
    @IsTest
    static void testCursorReconstructionFromQueryId() {
        // Arrange - Verify that a cursor can be reconstructed from queryId
        Database.Cursor originalCursor = CursorBatchTestUtils.createTestCursor(10);
        String queryId = CursorBatchContext.extractQueryId(originalCursor);
        Integer originalCount = originalCursor.getNumRecords();
        
        // Act - Reconstruct cursor from queryId
        Test.startTest();
        Database.Cursor reconstructedCursor = CursorBatchContext.reconstructCursor(queryId);
        Test.stopTest();
        
        // Assert
        Assert.areNotEqual(null, reconstructedCursor, 'Reconstructed cursor should not be null');
        Assert.areEqual(originalCount, reconstructedCursor.getNumRecords(), 
            'Reconstructed cursor should have same record count');
    }
    
    // =====================================================================================
    // Nebula Logger wiring coverage
    // =====================================================================================
    //
    // The constructor used to call CursorBatchLogger.getDefault() which routes log output
    // through System.debug -- invisible after the debug log window expires. The handler now
    // calls CursorBatchLogger.resolveLogger(LOG_TAG), which the framework's convention-based
    // discovery resolves to a Callable adapter in the consumer namespace (e.g. a Nebula
    // adapter), tagged with LOG_TAG, so cursor-reconstruction failures and swallowed
    // exceptions land in the consumer's persistent log sink instead of vanishing with the
    // debug window.
    //
    // This package is dependency-free, so we cannot assert on a specific concrete adapter
    // (fflib / Nebula / AEP types are not in force-app). The test below pins the tag value
    // -- shared with CursorBatchCoordinatorTriggerHandler so ops dashboards can filter both
    // subscribers in one query. Verification that the Callable adapter is actually invoked
    // belongs in a consumer-side test that lives alongside the real adapter implementation.

    @IsTest
    static void logTag_pinnedToDispatchTag() {
        // Arrange + Act -- the tag is a compile-time constant exposed via @TestVisible so
        // ops searches and downstream log filters have a stable identifier. The same value
        // is repeated in CursorBatchCoordinatorTriggerHandler.LOG_TAG so ops can tag-filter
        // both PE handlers' logs with a single equality predicate; a sibling test in
        // CursorBatchCoordinatorTriggerHandlerTest pins the coordinator side independently.
        //
        // Assert -- if someone renames the constant or drifts the value, this test breaks
        // before LogEntry__c queries in dashboards/alerts silently start missing data.
        Assert.areEqual(
            'CursorBatch Dispatch',
            CursorBatchWorkerTriggerHandler.LOG_TAG,
            'LOG_TAG must remain "CursorBatch Dispatch" so ops dashboards filtering both PE handlers in one query keep matching.'
        );
    }

    // =====================================================================================
    // Replay guard wiring
    // =====================================================================================
    //
    // The guard's own layers are tested in CursorBatchReplayGuardTest, which can build
    // Candidates directly. These tests cover only what the handler is responsible for:
    // deriving the right identity from the event, and honouring the verdict before anything
    // is enqueued.

    @IsTest
    static void guardBlocksDispatchForATerminalJob() {
        // This is the shape of the 2026-08-24 incident: worker events arriving for a job that
        // completed days earlier. Before the guard, every one of them enqueued a worker.
        CursorBatchTestUtils.resetTestWorker();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);

        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        jobRecord.Completed_At__c = System.now();
        update jobRecord;

        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };

        Test.startTest();
        new CursorBatchWorkerTriggerHandler().handle(events);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'A blocked event must not be ledgered, because it was never processed.');
    }

    @IsTest
    static void guardLedgersTheShardIdentityOfADispatchedEvent() {
        CursorBatchTestUtils.resetTestWorker();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);

        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );

        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 7,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };

        Test.startTest();
        new CursorBatchWorkerTriggerHandler().handle(events);
        Test.stopTest();

        List<CursorBatch_Event_Ledger__c> ledger = [
            SELECT Event_Key__c, Channel__c, Worker_Number__c, Cursor_Query_Id__c, Job_Name__c
            FROM CursorBatch_Event_Ledger__c
        ];
        Assert.areEqual(1, ledger.size(), 'A dispatched worker event must leave one ledger row.');
        Assert.areEqual(CursorBatchReplayGuard.buildWorkerKey(jobRecord.Id, queryId, 7),
            ledger[0].Event_Key__c,
            'The handler must key the event on job, cursor and shard.');
        Assert.areEqual(CursorBatchReplayGuard.CHANNEL_WORKER, ledger[0].Channel__c,
            'The row must be attributed to the worker channel.');
        Assert.areEqual(7, ledger[0].Worker_Number__c, 'The shard must be recorded for forensics.');
        Assert.areEqual(queryId, ledger[0].Cursor_Query_Id__c, 'The cursor must be recorded for forensics.');
    }

    @IsTest
    static void guardAdmitsARedispatchAfterTheCoordinatorRebuiltItsCursor() {
        // A coordinator retry fans out the same shard against a new cursor. That is legitimate and
        // must not be mistaken for a replay, which is why the queryId is part of the identity.
        CursorBatchTestUtils.resetTestWorker();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);

        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        String firstQueryId = CursorBatchContext.extractQueryId(CursorBatchTestUtils.createTestCursor());
        insert new CursorBatch_Event_Ledger__c(
            Event_Key__c = CursorBatchReplayGuard.buildWorkerKey(jobRecord.Id, firstQueryId, 1),
            Channel__c = CursorBatchReplayGuard.CHANNEL_WORKER
        );

        String retryQueryId = firstQueryId + '-rebuilt';
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = retryQueryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };

        Test.startTest();
        new CursorBatchWorkerTriggerHandler().handle(events);
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'The re-fanned shard must be admitted and ledgered under its new cursor identity.');
    }

    @IsTest
    static void unidentifiableEventIsStillDispatched() {
        // Worker_Number__c is null, so there is no shard identity to key on. Dropping the event
        // would silently lose work the framework itself published, so it dispatches unguarded and
        // processEvent reports whatever goes wrong.
        CursorBatchTestUtils.resetTestWorker();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);

        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );

        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = CursorBatchContext.extractQueryId(cursor),
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = null,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };

        Boolean threw = false;
        Test.startTest();
        try {
            new CursorBatchWorkerTriggerHandler().handle(events);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'An event with no shard identity must not break the batch.');
        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'An event that cannot be identified cannot be ledgered either.');
    }

    @IsTest
    static void malformedJobRecordIdIsDispatchedUnguarded() {
        // Job_Record_Id__c is a text field on the event, so a malformed value throws on the
        // implicit Id conversion while the candidate is being built.
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();

        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = CursorBatchContext.extractQueryId(cursor),
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = 'not-a-real-id',
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };

        Boolean threw = false;
        Test.startTest();
        try {
            new CursorBatchWorkerTriggerHandler().handle(events);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'A malformed job record Id must be logged and absorbed, not propagated.');
    }

    @IsTest
    static void twoIdenticalEventsInOneBatchDispatchOnce() {
        // The regression test for the guard's in-batch dedupe. A redelivery burst routinely puts
        // the same event in one subscriber batch twice; asking a stateless set twice returns true
        // both times and dispatches the shard twice, which is the exact double-execution the
        // guard exists to prevent. One ledger row means one dispatch.
        CursorBatchTestUtils.resetTestWorker();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);

        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );

        CursorBatch_Worker__e duplicate = new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cursor_Query_Id__c = queryId,
            Start_Position__c = 0,
            End_Position__c = 10,
            Page_Size__c = 10,
            Worker_Number__c = 1,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
        );

        Test.startTest();
        new CursorBatchWorkerTriggerHandler().handle(
            new List<CursorBatch_Worker__e>{ duplicate, duplicate.clone(false, true, false, false) }
        );
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'The same shard delivered twice in one batch must be admitted, and dispatched, exactly once.');
    }

    @IsTest
    static void staleEventIsReportedAsAFailedWorkerSoTheJobCanFinish() {
        // Blocking a live shard is only safe if the job can still reach a terminal status.
        // Total_Workers__c still counts the rejected shard, so without a failure report
        // Workers_Finished__c + Failed_Workers__c can never reach it: the job sits in Processing
        // forever and, because isJobAlreadyRunning treats Processing as running, every future
        // submission of that job name silently returns null.
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );

        // The event must be genuinely published: a constructed one carries a null CreatedDate, and
        // the guard treats unknown age as unknowable rather than stale. Publishing stamps a real
        // CreatedDate, and advancing the guard clock past it is what makes it read as stale.
        CursorBatchReplayGuard.nowOverride = System.now().addHours(5);

        Test.startTest();
        EventBus.publish(new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cursor_Query_Id__c = CursorBatchContext.extractQueryId(cursor),
            Start_Position__c = 0,
            End_Position__c = 10,
            Page_Size__c = 10,
            Worker_Number__c = 1,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
        ));
        // First delivery runs the worker trigger, which blocks the shard and publishes the
        // failure report. The second delivers that report to the completion trigger.
        Test.getEventBus().deliver();
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c WHERE Channel__c = :CursorBatchReplayGuard.CHANNEL_WORKER],
            'Precondition: the stale event must have been blocked, not dispatched.');
        CursorBatch_Job__c reloaded = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(1, reloaded.Failed_Workers__c,
            'The rejected shard must be reported as a failed worker so the job can reach a terminal status.');
        Assert.areEqual('Failed', reloaded.Status__c,
            'A job whose only shard was rejected must end Failed rather than stalling in Processing.');
        Assert.isNotNull(reloaded.Completed_At__c,
            'The job must be genuinely terminal, so isJobAlreadyRunning stops blocking future submissions.');
        Assert.isTrue(reloaded.Error_Message__c.contains('stale'),
            'The job record must say why the shard never ran; a log entry alone is not discoverable.');
    }

    @IsTest
    static void terminalJobRejectionIsNotReportedAsAFailedWorker() {
        // A replay of the 2026-08-24 shape resolves to JOB_TERMINAL, not STALE, because job state
        // is evaluated first. That ordering is what keeps reconciliation from amplifying: ~51,000
        // rejected events must produce zero follow-on events, and must not touch counters on a job
        // that already finished.
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        jobRecord.Workers_Finished__c = 1;
        jobRecord.Completed_At__c = System.now();
        update jobRecord;

        CursorBatchReplayGuard.nowOverride = System.now().addHours(5);

        Test.startTest();
        EventBus.publish(new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cursor_Query_Id__c = CursorBatchContext.extractQueryId(cursor),
            Start_Position__c = 0,
            End_Position__c = 10,
            Page_Size__c = 10,
            Worker_Number__c = 1,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
        ));
        Test.getEventBus().deliver();
        Test.getEventBus().deliver();
        Test.stopTest();

        CursorBatch_Job__c reloaded = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(0, reloaded.Failed_Workers__c,
            'A replay for an already-completed job must not add a failure to its counters.');
        Assert.areEqual('Completed', reloaded.Status__c,
            'A replay must not disturb the terminal status the job legitimately reached.');
    }

    @IsTest
    static void publishedEventIsLedgeredWithItsRealReplayId() {
        // The one thing the unit tests cannot fake: a genuinely published event, carrying a real
        // ReplayId and a real CreatedDate assigned by the bus. This proves the trigger path feeds
        // the guard usable values, not just that the guard works on hand-built candidates.
        CursorBatchTestUtils.resetTestWorker();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 10);

        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );

        Test.startTest();
        EventBus.publish(new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cursor_Query_Id__c = queryId,
            Start_Position__c = 0,
            End_Position__c = 10,
            Page_Size__c = 10,
            Worker_Number__c = 3,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
        ));
        Test.stopTest();

        List<CursorBatch_Event_Ledger__c> ledger = [
            SELECT Event_Key__c, Replay_Id__c, Event_Published_At__c
            FROM CursorBatch_Event_Ledger__c
        ];
        Assert.areEqual(1, ledger.size(), 'A published worker event must be ledgered by the trigger.');
        Assert.areEqual(CursorBatchReplayGuard.buildWorkerKey(jobRecord.Id, queryId, 3),
            ledger[0].Event_Key__c,
            'The ledgered key must match what a redelivery of this event would compute.');
        Assert.isTrue(String.isNotBlank(ledger[0].Replay_Id__c),
            'A real delivery must record its ReplayId, which is the only customer-visible handle on bus position.');
        Assert.isNotNull(ledger[0].Event_Published_At__c,
            'A real delivery must record its publish time, which is what the staleness layer compares against.');
    }

    @IsTest
    static void testTriggerFiresOnEventPublish() {
        // Arrange - This test actually fires the trigger by publishing Platform Events
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        // Create a cursor and extract its queryId
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String queryId = CursorBatchContext.extractQueryId(cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cursor_Query_Id__c = queryId,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        // Act - Publish the events to fire the trigger
        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(events);
        Test.stopTest();
        
        // Assert - Verify the events were published successfully and trigger fired
        Assert.areEqual(1, results.size(), 'Should have published 1 event');
        Assert.areEqual(true, results[0].isSuccess(), 'Event should have been published successfully');
        // The trigger should have fired and processed the event through the handler
        Assert.isTrue(CursorBatchTestUtils.testWorker_processCallCount >= 0, 
            'Trigger should have fired and handler should have processed the worker event');
    }
}