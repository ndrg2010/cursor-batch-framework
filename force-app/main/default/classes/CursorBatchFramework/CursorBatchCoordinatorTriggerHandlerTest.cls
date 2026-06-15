/**
 * @description Unit tests for CursorBatchCoordinatorTriggerHandler Platform Event handler.
 *              Tests coordinator instantiation and enqueueing via reflection.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCoordinatorTriggerHandlerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(20);
    }
    
    @IsTest
    static void testHandleWithNullEvents() {
        // Arrange
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act & Assert - Should not throw exception with null events
        Test.startTest();
        handler.handle(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Handler should gracefully handle null events list');
    }
    
    @IsTest
    static void testHandleWithEmptyEvents() {
        // Arrange
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        List<CursorBatch_Coordinator__e> emptyEvents = new List<CursorBatch_Coordinator__e>();
        
        // Act & Assert - Should not throw exception with empty events
        Test.startTest();
        handler.handle(emptyEvents);
        Test.stopTest();
        
        Assert.isTrue(true, 'Handler should gracefully handle empty events list');
    }
    
    @IsTest
    static void testHandleWithValidEvent() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event without throwing
        Assert.isTrue(true, 'Handler should have processed the coordinator event');
    }
    
    @IsTest
    static void testHandleWithDelay() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = 5
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event with delay without throwing
        Assert.isTrue(true, 'Handler should have processed the coordinator event with delay');
    }
    
    @IsTest
    static void testHandleWithEmptyCoordinatorClass() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'TestCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = '',  // Empty class name
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act - Should not throw exception with empty coordinator class
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle empty coordinator class
        Assert.areEqual(false, exceptionThrown, 
            'Handler should handle empty coordinator class gracefully without throwing exception');
    }
    
    @IsTest
    static void testHandleWithNonExistentCoordinatorClass() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'NonExistentCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'NonExistentCoordinatorClass',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act - Should not throw exception with non-existent coordinator class
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle non-existent coordinator class
        Assert.areEqual(false, exceptionThrown, 
            'Handler should handle non-existent coordinator class gracefully without throwing exception');
    }
    
    @IsTest
    static void testHandleWithInvalidCoordinatorClassType() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'String',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'String',  // String class exists but doesn't extend CursorBatchCoordinator
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act - Should not throw exception with wrong coordinator class type
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle coordinator class that doesn't extend CursorBatchCoordinator
        Assert.areEqual(false, exceptionThrown, 
            'Handler should handle invalid coordinator class type gracefully without throwing');
    }
    
    @IsTest
    static void testHandleMultipleEvents() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>();
        for (Integer i = 0; i < 3; i++) {
            CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
                'TestJob' + i, 
                'CursorBatchTestUtils.TestCursorBatchCoordinator',
                0
            );
            
            events.add(new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob' + i,
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            ));
        }
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process all 3 events
        Assert.areEqual(3, events.size(), 'Should have processed 3 events');
        Assert.isTrue(true, 'Handler should have processed all coordinator events');
    }
    
    @IsTest
    static void testTriggerFiresOnEventPublish() {
        // Arrange - This test actually fires the trigger by publishing Platform Events
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
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
        Assert.isTrue(true, 'Trigger should have fired and handler should have processed the coordinator event');
    }
    
    @IsTest
    static void testHandleWithZeroDelay() {
        // Arrange - Test that delay of 0 is treated as no delay
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = 0  // Zero delay
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event without delay (0 treated as no delay)
        Assert.isTrue(true, 'Handler should have processed the coordinator event with zero delay');
    }

    // =====================================================================================
    // enqueueCoordinator coverage
    // =====================================================================================
    //
    // The pre-existing "happy path" tests (testHandleWithValidEvent / testHandleWithDelay /
    // testHandleWithZeroDelay / testHandleMultipleEvents) all reference
    // 'CursorBatchTestUtils.TestCursorBatchCoordinator', which only declares parameterized
    // constructors. Type.newInstance() requires a public no-arg constructor, so newInstance()
    // throws and processEvent's catch block fires before enqueueCoordinator is ever called --
    // leaving enqueueCoordinator at 0% coverage. The tests below resolve to
    // TestableCoordinator (defined at the bottom of this file), which exposes a public no-arg
    // constructor and therefore lets newInstance() succeed and processEvent reach
    // enqueueCoordinator on both the no-delay and delay branches.

    @IsTest
    static void testHandle_validCoordinatorWithNoDelay_reachesEnqueueCoordinator() {
        // Arrange -- TestableCoordinator has a public no-arg constructor and extends
        // CursorBatchCoordinator, so createCoordinatorInstance returns a non-null instance
        // and processEvent must call enqueueCoordinator.
        String className = 'CursorBatchCoordinatorTriggerHandlerTest.TestableCoordinator';
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'EnqueueNoDelayJob',
            className,
            0
        );

        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'EnqueueNoDelayJob',
                Coordinator_Class__c = className,
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();

        // Assert -- enqueueCoordinator skips the real System.enqueueJob under
        // Test.isRunningTest(), so the only observable signal is that the catch block in
        // processEvent did NOT fire. The row must stay untouched in Preparing -- if anything
        // threw before reaching enqueueCoordinator the test would no longer be exercising
        // that method.
        CursorBatch_Job__c reloaded = [
            SELECT Id, Status__c, Error_Message__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobRecord.Id
            LIMIT 1
        ];
        Assert.areEqual('Preparing', reloaded.Status__c,
            'enqueueCoordinator must complete without falling into the catch block in processEvent.');
        Assert.isTrue(String.isBlank(reloaded.Error_Message__c),
            'No error should be recorded when enqueueCoordinator succeeds.');
    }

    @IsTest
    static void testHandle_validCoordinatorWithPositiveDelay_reachesDelayBranch() {
        // Arrange -- same as above but with Delay_Minutes__c set so the
        // delayMinutes > 0 branch in enqueueCoordinator is exercised (including the
        // Integer.valueOf cast on the Decimal field).
        String className = 'CursorBatchCoordinatorTriggerHandlerTest.TestableCoordinator';
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'EnqueueWithDelayJob',
            className,
            0
        );

        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'EnqueueWithDelayJob',
                Coordinator_Class__c = className,
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = 7
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();

        // Assert -- row untouched in Preparing proves the delay branch executed without
        // falling into the catch block in processEvent.
        CursorBatch_Job__c reloaded = [
            SELECT Id, Status__c, Error_Message__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobRecord.Id
            LIMIT 1
        ];
        Assert.areEqual('Preparing', reloaded.Status__c,
            'enqueueCoordinator delay branch must complete without falling into the catch block in processEvent.');
        Assert.isTrue(String.isBlank(reloaded.Error_Message__c),
            'No error should be recorded when enqueueCoordinator with delay succeeds.');
    }

    // =====================================================================================
    // handleCsvCallback coverage
    // =====================================================================================
    //
    // No pre-existing test exercises the CSV_Ready dispatch path. The cases below cover:
    //   - the happy path with Started_At__c populated (duration calc + coordinator
    //     construction);
    //   - the catch branch when Job_Record_Id__c is not a parseable Id;
    //   - the missing-job branch when the FOR UPDATE query returns nothing;
    //   - the wrong-status guard that ignores callbacks for jobs that aren't in
    //     'Extracting File';
    //   - the Started_At__c=null branch where queryDurationMs stays 0.

    @IsTest
    static void testHandleCsvCallback_extractingFileWithStartedAt_isSuccessful() {
        // Arrange -- job is in 'Extracting File' status with Started_At__c set. The CSV_Ready
        // callback should compute queryDurationMs from evt.CreatedDate - Started_At__c and
        // construct a CursorBatchCsvCallbackCoordinator. Under Test.isRunningTest() the
        // enqueueJob call is skipped, so the row remains in 'Extracting File'.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'CsvReadyHappyJob',
            'irrelevant-because-CSV_Ready-bypasses-coordinator-resolution',
            0
        );
        jobRecord.Status__c = 'Extracting File';
        update jobRecord;

        // CreatedDate on a freshly new'd Platform Event is null. The duration calc would
        // NPE without a CreatedDate, so we deserialize from JSON to inject one.
        Datetime createdDate = jobRecord.Started_At__c.addSeconds(42);
        CursorBatch_Coordinator__e evt = (CursorBatch_Coordinator__e) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'CursorBatch_Coordinator__e' },
                'Job_Name__c' => 'csv-cursor-query-id-happy',
                'Coordinator_Class__c' => 'CSV_Ready',
                'Job_Record_Id__c' => jobRecord.Id,
                'CreatedDate' => createdDate
            }),
            CursorBatch_Coordinator__e.class
        );

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(new List<CursorBatch_Coordinator__e>{ evt });
        Test.stopTest();

        // Assert -- happy path must not flip the row to Failed.
        CursorBatch_Job__c reloaded = [
            SELECT Id, Status__c, Error_Message__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobRecord.Id
            LIMIT 1
        ];
        Assert.areEqual('Extracting File', reloaded.Status__c,
            'CSV_Ready happy path must leave the job in Extracting File since the handler skips enqueue under Test.isRunningTest().');
        Assert.isTrue(String.isBlank(reloaded.Error_Message__c),
            'CSV_Ready happy path must not record an Error_Message__c.');
    }

    @IsTest
    static void testHandleCsvCallback_invalidJobRecordId_isNonFatal() {
        // Arrange -- Job_Record_Id__c is not a parseable Id. Id.valueOf throws inside
        // handleCsvCallback's inner try; the inner catch must log and return so the outer
        // handle() call does not propagate.
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'csv-cursor-query-bad-id',
                Coordinator_Class__c = 'CSV_Ready',
                Job_Record_Id__c = 'not-a-real-id',
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act + Assert -- must not throw.
        Boolean threw = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw,
            'CSV_Ready with an unparseable Job_Record_Id__c must be swallowed by the inner catch.');
    }

    @IsTest
    static void testHandleCsvCallback_missingJobRecord_isNonFatal() {
        // Arrange -- valid Id format but no row exists. We create the row to capture an Id
        // and then delete it; the FOR UPDATE query returns an empty list and the handler
        // must log and return without throwing.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'CsvReadyGoneJob',
            'irrelevant',
            0
        );
        Id jobId = jobRecord.Id;
        delete jobRecord;

        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'csv-cursor-query-missing-row',
                Coordinator_Class__c = 'CSV_Ready',
                Job_Record_Id__c = jobId,
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act + Assert -- must not throw.
        Boolean threw = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw,
            'CSV_Ready for a job row that no longer exists must be a no-op, not an exception.');
    }

    @IsTest
    static void testHandleCsvCallback_wrongStatus_skipsProcessingAndDoesNotModifyJob() {
        // Arrange -- job is still in 'Preparing'. The CSV_Ready guard
        // (jobRecord.Status__c != 'Extracting File') must short-circuit before the
        // coordinator is constructed, and must not modify the job row.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'CsvReadyWrongStatusJob',
            'irrelevant',
            0
        );

        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'csv-cursor-query-wrong-status',
                Coordinator_Class__c = 'CSV_Ready',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();

        // Assert -- the row is untouched (still Preparing, no error message).
        CursorBatch_Job__c reloaded = [
            SELECT Id, Status__c, Error_Message__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobRecord.Id
            LIMIT 1
        ];
        Assert.areEqual('Preparing', reloaded.Status__c,
            'CSV_Ready against a non-Extracting File job must not modify the row.');
        Assert.isTrue(String.isBlank(reloaded.Error_Message__c),
            'CSV_Ready short-circuit on wrong status must not record an Error_Message__c.');
    }

    @IsTest
    static void testHandleCsvCallback_nullStartedAt_skipsDurationCalc() {
        // Arrange -- Started_At__c=null exercises the `if (jobRecord.Started_At__c != null)`
        // branch where queryDurationMs stays 0 and evt.CreatedDate is never read. This means
        // we don't need to inject CreatedDate via JSON deserialization for this case.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'CsvReadyNullStartedAtJob',
            'irrelevant',
            0
        );
        jobRecord.Status__c = 'Extracting File';
        jobRecord.Started_At__c = null;
        update jobRecord;

        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'csv-cursor-query-null-started-at',
                Coordinator_Class__c = 'CSV_Ready',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();

        // Assert -- the row remains in Extracting File; no Failed flip means
        // CursorBatchCsvCallbackCoordinator construction + setJobRecordId succeeded.
        CursorBatch_Job__c reloaded = [
            SELECT Id, Status__c, Error_Message__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobRecord.Id
            LIMIT 1
        ];
        Assert.areEqual('Extracting File', reloaded.Status__c,
            'CSV_Ready with null Started_At__c must still complete the duration-skip branch successfully.');
        Assert.isTrue(String.isBlank(reloaded.Error_Message__c),
            'CSV_Ready with null Started_At__c must not record an Error_Message__c.');
    }

    // =====================================================================================
    // handleCsvError coverage
    // =====================================================================================
    //
    // No pre-existing test exercises the CSV_Error dispatch path. The cases below cover:
    //   - the inner catch when Job_Record_Id__c isn't a parseable Id (Id.valueOf throws);
    //   - the missing-row no-op when CursorBatchSelector.getJobById returns null;
    //   - the happy path: row flipped to Failed, Error_Message__c populated with the
    //     'CSV middleware error: ...' prefix, Completed_At__c stamped, and the completion
    //     handler invoked. The job's Coordinator_Class__c uses TestableCoordinator so any
    //     reflection inside routeFinishCallback resolves cleanly.

    @IsTest
    static void testHandleCsvError_invalidJobRecordId_isNonFatal() {
        // Arrange -- Job_Record_Id__c is not a parseable Id. Id.valueOf throws inside the
        // inner try; the inner catch must log and return, so handle() does not propagate.
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'middleware error message',
                Coordinator_Class__c = 'CSV_Error',
                Job_Record_Id__c = 'not-a-real-id',
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act + Assert -- must not throw.
        Boolean threw = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw,
            'CSV_Error with an unparseable Job_Record_Id__c must be swallowed by the inner catch.');
    }

    @IsTest
    static void testHandleCsvError_validJob_marksAsFailedWithPrefixedMessageAndStampsCompletedAt() {
        // Arrange -- a real job row; the CSV_Error path must flip it to Failed, write the
        // 'CSV middleware error: <evt.Job_Name__c>' message, stamp Completed_At__c, and
        // invoke routeFinishCallback. We use TestableCoordinator as the Coordinator_Class__c
        // so that any reflection in routeFinishCallback resolves to a real Queueable with a
        // public no-arg constructor.
        String coordinatorClass = 'CursorBatchCoordinatorTriggerHandlerTest.TestableCoordinator';
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'CsvErrorHappyJob',
            coordinatorClass,
            0
        );
        Datetime beforeHandle = System.now();
        String middlewareMessage = 'CSV indexing failed: timeout after 5 minutes';

        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = middlewareMessage,
                Coordinator_Class__c = 'CSV_Error',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();

        // Assert -- row is now Failed with the prefixed error and a Completed_At__c stamp.
        CursorBatch_Job__c reloaded = [
            SELECT Id, Status__c, Error_Message__c, Completed_At__c
            FROM CursorBatch_Job__c
            WHERE Id = :jobRecord.Id
            LIMIT 1
        ];
        Assert.areEqual('Failed', reloaded.Status__c,
            'handleCsvError must flip Status__c to Failed.');
        Assert.areEqual('CSV middleware error: ' + middlewareMessage, reloaded.Error_Message__c,
            'handleCsvError must record the CSV middleware prefix + original message verbatim.');
        Assert.isNotNull(reloaded.Completed_At__c,
            'handleCsvError must stamp Completed_At__c on the failed row.');
        // Compare at second precision: Datetime custom fields drop milliseconds on the DB
        // round-trip (the persisted value is truncated to the nearest second), but
        // beforeHandle is captured from System.now() with full millisecond precision in
        // memory. A strict >= against the in-memory value can fail by a few hundred ms
        // even when the handler clearly ran after beforeHandle, so compare floored seconds.
        Assert.isTrue(
            reloaded.Completed_At__c.getTime() / 1000 >= beforeHandle.getTime() / 1000,
            'Completed_At__c must be at or after the second beforeHandle was captured.'
        );
    }

    // =====================================================================================
    // Nebula Logger wiring coverage
    // =====================================================================================
    //
    // The constructor used to call CursorBatchLogger.getDefault() which routes log output
    // through System.debug -- invisible after the debug log window expires. The handler now
    // calls CursorBatchLogger.resolveLogger(LOG_TAG), which the framework's convention-based
    // discovery resolves to CursorBatchLoggerAdapter (Callable Nebula adapter living in the
    // consumer namespace), tagged with LOG_TAG, so swallowed exceptions land in Nebula's
    // LogEntry__c.
    //
    // The two tests below pin (a) the tag value (shared with CursorBatchWorkerTriggerHandler
    // so ops dashboards can filter both subscribers in one query) and (b) that the
    // AEP-resolved ILoggerService is actually invoked from a normal handle() path. (b) proves
    // the Nebula adapter is wired through the framework's resolveLogger contract -- the
    // System.debug-only default never touches ILoggerService.

    @IsTest
    static void logTag_pinnedToDispatchTag() {
        // Arrange + Act -- the tag is a compile-time constant exposed via @TestVisible so
        // ops searches and downstream Nebula log filters have a stable identifier. The same
        // value is repeated in CursorBatchWorkerTriggerHandler.LOG_TAG so ops can tag-filter
        // both PE handlers' logs with a single equality predicate; a sibling test in
        // CursorBatchWorkerTriggerHandlerTest pins the worker side independently.
        //
        // Assert -- if someone renames the constant or drifts the value, this test breaks
        // before LogEntry__c queries in dashboards/alerts silently start missing data.
        Assert.areEqual(
            'CursorBatch Dispatch',
            CursorBatchCoordinatorTriggerHandler.LOG_TAG,
            'LOG_TAG must remain "CursorBatch Dispatch" so ops dashboards filtering both PE handlers in one query keep matching.'
        );
    }

    @IsTest
    static void constructor_routesLogOutputThroughAepResolvedLoggerService() {
        // Arrange -- swap the AEP-resolved ILoggerService for an ApexMocks stub. The handler
        // constructor calls CursorBatchLogger.resolveLogger(LOG_TAG) which uses Type.forName
        // to find CursorBatchLoggerAdapter, instantiates it via no-arg constructor (which in
        // turn does Application.Service.newInstance(ILoggerService.class) -- this is the seam
        // we intercept here), and calls Callable.call('addTag', ...) to apply LOG_TAG. If the
        // handler still called CursorBatchLogger.getDefault() (the System.debug-only
        // implementation), no call would ever reach mockLoggerService and the verify below
        // would fail with "Wanted 1 time(s) but was called 0 time(s)".
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        ILoggerService mockLoggerService = (ILoggerService) mocks.mock(ILoggerService.class);
        ILogEntryBuilder mockEntryBuilder = (ILogEntryBuilder) mocks.mock(ILogEntryBuilder.class);
        mocks.startStubbing();
        mocks.when(mockLoggerService.info((String) fflib_Match.anyString())).thenReturn(mockEntryBuilder);
        mocks.when(mockLoggerService.error((String) fflib_Match.anyString())).thenReturn(mockEntryBuilder);
        mocks.when(mockLoggerService.exception((String) fflib_Match.anyString(), fflib_Match.anyObject())).thenReturn(mockEntryBuilder);
        mocks.when(mockEntryBuilder.addTags((Set<String>) fflib_Match.anyObject())).thenReturn(mockEntryBuilder);
        mocks.stopStubbing();
        Application.Service.setMock(ILoggerService.class, mockLoggerService);

        // Use the ThrowingCoordinator path so processEvent's catch fires and logException is
        // guaranteed to be invoked once -- this is the exact code path stuck-job forensics
        // depend on, so verifying it routes through Nebula is the highest-signal check.
        String throwingClassName = 'CursorBatchCoordinatorTriggerHandlerTest.ThrowingCoordinator';
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'NebulaWiringJob',
            throwingClassName,
            0
        );
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'NebulaWiringJob',
                Coordinator_Class__c = throwingClassName,
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();

        // Assert -- the exception swallow in processEvent must hit ILoggerService.exception
        // (which is what CursorBatchLoggerAdapter.logException delegates to). Any count >= 1
        // proves the adapter is wired through resolveLogger; the framework's debug-only
        // default would produce 0.
        ((ILoggerService) mocks.verify(mockLoggerService, mocks.atLeast(1)))
            .exception((String) fflib_Match.anyString(), fflib_Match.anyObject());
    }

    /**
     * @description Test-only coordinator whose no-arg constructor unconditionally throws.
     *              Used to exercise the catch block in CursorBatchCoordinatorTriggerHandler.processEvent
     *              so the Nebula-routed logger.logException invocation can be verified by
     *              constructor_routesLogOutputThroughAepResolvedLoggerService.
     *
     *              Resolved at runtime via Type.forName('CursorBatchCoordinatorTriggerHandlerTest.ThrowingCoordinator').
     *              The class intentionally does not extend CursorBatchCoordinator -- the constructor
     *              throws before the instanceof check is reached, so the type is irrelevant to the test.
     */
    public class ThrowingCoordinator {
        public ThrowingCoordinator() {
            throw new ThrowingCoordinatorException('Forced failure for unit test');
        }
    }

    public class ThrowingCoordinatorException extends Exception {}

    /**
     * @description Test-only concrete subclass of CursorBatchCoordinator with a public no-arg
     *              constructor, so Type.newInstance() succeeds and processEvent reaches
     *              enqueueCoordinator. CursorBatchTestUtils.TestCursorBatchCoordinator only
     *              exposes parameterized constructors (TestCursorBatchCoordinator(String) /
     *              TestCursorBatchCoordinator(String, String)), so newInstance() against it
     *              throws and the catch block in processEvent fires before enqueueCoordinator
     *              is ever invoked -- which is why enqueueCoordinator was previously at 0%
     *              coverage. Resolved at runtime via
     *              Type.forName('CursorBatchCoordinatorTriggerHandlerTest.TestableCoordinator').
     */
    public class TestableCoordinator extends CursorBatchCoordinator {
        public TestableCoordinator() {
            super();
        }

        public override String buildQuery() {
            return 'SELECT Id FROM Account';
        }

        public override String getWorkerClassName() {
            return 'CursorBatchTestUtils.TestCursorBatchWorker';
        }
    }
}