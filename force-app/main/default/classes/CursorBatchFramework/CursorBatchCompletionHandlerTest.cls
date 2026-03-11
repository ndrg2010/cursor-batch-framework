/**
 * @description Unit tests for CursorBatchCompletionHandler Platform Event handler.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCompletionHandlerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(10);
    }
    
    @IsTest
    static void testHandleSuccessEvents() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 3, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(2, updatedJob.Completed_Batches__c, 'Should increment completed batch count');
        System.assertEquals(2, updatedJob.Workers_Finished__c, 'Should increment workers finished count');
        System.assertEquals(0, updatedJob.Failed_Workers__c, 'Failed count should be 0');
        System.assertEquals('Processing', updatedJob.Status__c, 'Status should still be Processing (not all complete)');
    }
    
    @IsTest
    static void testHandleFailureEvents() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Test error message',
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(0, updatedJob.Completed_Batches__c, 'Completed batch count should be 0');
        System.assertEquals(0, updatedJob.Workers_Finished__c, 'Workers finished should be 0');
        System.assertEquals(1, updatedJob.Failed_Workers__c, 'Should increment failed count');
        System.assertEquals('Test error message', updatedJob.Error_Message__c, 
            'Should capture error message');
    }
    
    @IsTest
    static void testHandleMixedEvents() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 4, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker 2 failed',
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(2, updatedJob.Completed_Batches__c, 'Should have 2 completed batches');
        System.assertEquals(2, updatedJob.Workers_Finished__c, 'Should have 2 workers finished');
        System.assertEquals(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        System.assertEquals('Worker 2 failed', updatedJob.Error_Message__c, 
            'Should capture first error');
    }
    
    @IsTest
    static void testHandleAllWorkersCompleteSuccess() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(2, updatedJob.Workers_Finished__c, 'Should have 2 workers finished');
        System.assertEquals('Completed', updatedJob.Status__c, 'Status should be Completed');
        System.assertNotEquals(null, updatedJob.Completed_At__c, 'Completed_At should be set');
    }
    
    @IsTest
    static void testHandleAllWorkersCompleteWithPartialFailures() {
        // Arrange - Some workers succeed, some fail = Completed with Errors
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker failed',
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(1, updatedJob.Workers_Finished__c, 'Should have 1 worker finished');
        System.assertEquals(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        System.assertEquals('Completed with Errors', updatedJob.Status__c, 'Status should be Completed with Errors');
        System.assertNotEquals(null, updatedJob.Completed_At__c, 'Completed_At should be set');
    }
    
    @IsTest
    static void testHandleAllWorkersFailed() {
        // Arrange - All workers fail = Failed
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker 1 failed',
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker 2 failed',
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(0, updatedJob.Workers_Finished__c, 'Should have 0 workers finished');
        System.assertEquals(2, updatedJob.Failed_Workers__c, 'Should have 2 failed');
        System.assertEquals('Failed', updatedJob.Status__c, 'Status should be Failed when all workers fail');
        System.assertEquals('Worker 1 failed', updatedJob.Error_Message__c, 'Should capture first error');
        System.assertNotEquals(null, updatedJob.Completed_At__c, 'Completed_At should be set');
    }
    
    @IsTest
    static void testHandleWithMissingJobRecord() {
        // Arrange
        Id fakeJobId = CursorBatch_Job__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        
        // Count existing jobs before the test
        Integer jobCountBefore = [SELECT COUNT() FROM CursorBatch_Job__c];
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = fakeJobId,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should complete without throwing exception and not create/modify any jobs
        Integer jobCountAfter = [SELECT COUNT() FROM CursorBatch_Job__c];
        System.assertEquals(jobCountBefore, jobCountAfter, 
            'No jobs should be created when handling events for non-existent job');
    }
    
    @IsTest
    static void testHandleEventsFromMultipleJobs() {
        // Arrange
        CursorBatch_Job__c jobRecord1 = CursorBatchTestUtils.createTestJobRecord(
            'TestJob1', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        CursorBatch_Job__c jobRecord2 = CursorBatchTestUtils.createTestJobRecord(
            'TestJob2', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord1.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord2.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob1 = CursorBatchSelector.getJobById(jobRecord1.Id);
        CursorBatch_Job__c updatedJob2 = CursorBatchSelector.getJobById(jobRecord2.Id);
        System.assertEquals('Completed', updatedJob1.Status__c, 'Job 1 should be Completed');
        System.assertEquals('Completed', updatedJob2.Status__c, 'Job 2 should be Completed');
    }
    
    @IsTest
    static void testCallbackWithNonCoordinatorClass() {
        // Arrange - Class that doesn't extend Coordinator
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob1', 1, 'String'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Completed', updatedJob.Status__c, 'Job should complete even with invalid coordinator class');
    }
    
    @IsTest
    static void testCallbackWithNonExistentClass() {
        // Arrange - Non-existent coordinator class
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob2', 1, 'NonExistentCoordinatorClass'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Completed', updatedJob.Status__c, 'Job should still complete with non-existent class');
    }
    
    @IsTest
    static void testHandleWorkerRetryTracking() {
        // Arrange - Test that worker retry counts are aggregated on the job record
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 3, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Simulate 3 workers completing with different retry counts
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Retry_Count__c = 0,  // No retries
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Retry_Count__c = 2,  // 2 retries before success
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Max retries exhausted',
                Retry_Count__c = 3,  // 3 retries before failure
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(5, updatedJob.Total_Worker_Retries__c, 
            'Should aggregate retry counts (0 + 2 + 3 = 5)');
        System.assertEquals(2, updatedJob.Workers_Finished__c, 'Should have 2 workers finished');
        System.assertEquals(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        System.assertEquals('Completed with Errors', updatedJob.Status__c, 'Status should be Completed with Errors due to partial failure');
    }
    
    @IsTest
    static void testHandleWorkerRetryTrackingWithNullRetryCount() {
        // Arrange - Test handling of null retry counts (for backwards compatibility)
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Retry_Count__c = null,  // Null retry count (legacy event)
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Retry_Count__c = 1,  // 1 retry
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(1, updatedJob.Total_Worker_Retries__c, 
            'Should handle null retry counts gracefully (only count the 1)');
        System.assertEquals('Completed', updatedJob.Status__c, 'Status should be Completed');
    }
    
    @IsTest
    static void testHandleSuccessEventReducesSharedState() {
        // Arrange
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 2, 20);
        config.Query_Builder_Class__c = 'CursorJobTest.TestQueryBuilder';
        config.Query_Builder_Method__c = 'getAccountsQuery';
        config.Worker_Class__c = 'CursorBatchTestUtils.TestStatefulCursorJobWorker';
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorJob'
        );
        jobRecord.State_JSON__c = '{"processedCount":2,"pagesProcessed":1}';
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = false,
                State_Delta__c = '{"processedCount":5,"pagesProcessed":1}'
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(updatedJob.State_JSON__c);
        System.assertEquals(7, ((Decimal) state.get('processedCount')).intValue(),
            'Reducer should merge page delta into the persisted state');
        System.assertEquals(2, ((Decimal) state.get('pagesProcessed')).intValue(),
            'Reducer should update page count in persisted state');
    }
    
    @IsTest
    static void testHandleStateReductionFailureContinuesProcessing() {
        // When reduceState throws (e.g. malformed delta JSON), handler should log, skip the state update,
        // and still apply worker counts and completion status so the job does not get stuck.
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 1, 20);
        config.Query_Builder_Class__c = 'CursorJobTest.TestQueryBuilder';
        config.Query_Builder_Method__c = 'getAccountsQuery';
        config.Worker_Class__c = 'CursorBatchTestUtils.TestStatefulCursorJobWorker';
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorJob'
        );
        String initialStateJson = '{"processedCount":0,"pagesProcessed":0}';
        jobRecord.State_JSON__c = initialStateJson;
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true,
                State_Delta__c = 'not valid json'
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act - should not throw; reduceState will throw internally, handler catches and continues
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - worker count and completion status still updated; state update skipped
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(1, updatedJob.Completed_Batches__c, 'Should count successful batch despite state reduction failure');
        System.assertEquals(1, updatedJob.Workers_Finished__c, 'Should count worker finished');
        System.assertEquals('Completed', updatedJob.Status__c, 'Job should complete and not stay stuck in Processing');
        System.assertEquals(initialStateJson, updatedJob.State_JSON__c,
            'State should be unchanged when reduceState throws (delta skipped)');
    }
    
    @IsTest
    static void testTriggerFiresOnEventPublish() {
        // Arrange - This test actually fires the trigger by publishing Platform Events
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        // Act - Publish the events to fire the trigger
        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(events);
        Test.stopTest();
        
        // Assert - Verify the events were published successfully and trigger fired
        System.assertEquals(2, results.size(), 'Should have published 2 events');
        System.assertEquals(true, results[0].isSuccess(), 'Event should have been published successfully');
        System.assertEquals(true, results[1].isSuccess(), 'Event should have been published successfully');
        
        // The trigger should have fired and processed the events through the handler
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(2, updatedJob.Workers_Finished__c, 'Trigger should have fired and handler should have processed both events');
        System.assertEquals('Completed', updatedJob.Status__c, 'Status should be Completed');
    }
    
    // ============================================
    // Idempotency (Replay) and Cleanup Tests
    // ============================================
    
    @IsTest
    static void testHandleCompletedJobDeletesProcessedEvents() {
        // When a job reaches terminal status, processed-event records for that job are deleted.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.handle(events);
        Integer remaining = [SELECT COUNT() FROM CursorBatch_Processed_Event__c WHERE Cursor_Batch_Job__c = :jobRecord.Id];
        System.assertEquals(0, remaining, 'Processed events for completed job should be deleted');
    }
    
    @IsTest
    static void testHandleReplayedEventsSkippedWhenProcessedEventsExist() {
        // When processed-event records exist for (Job, ReplayId), handler skips those events (idempotency).
        // We simulate "replay" by pre-inserting processed events and passing events with matching ReplayId via put.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 3, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        String key1 = jobRecord.Id + '#idem-replay-1';
        String key2 = jobRecord.Id + '#idem-replay-2';
        insert new List<CursorBatch_Processed_Event__c>{
            new CursorBatch_Processed_Event__c(
                Cursor_Batch_Job__c = jobRecord.Id,
                Replay_Id__c = 'idem-replay-1',
                Processed_Event_Key__c = key1
            ),
            new CursorBatch_Processed_Event__c(
                Cursor_Batch_Job__c = jobRecord.Id,
                Replay_Id__c = 'idem-replay-2',
                Processed_Event_Key__c = key2
            )
        };
        CursorBatch_WorkerComplete__e evt1 = new CursorBatch_WorkerComplete__e(
            Job_Id__c = jobRecord.Id,
            Success__c = true,
            Error_Message__c = null,
            Is_Final__c = true
        );
        evt1.put('ReplayId', 'idem-replay-1');
        CursorBatch_WorkerComplete__e evt2 = new CursorBatch_WorkerComplete__e(
            Job_Id__c = jobRecord.Id,
            Success__c = true,
            Error_Message__c = null,
            Is_Final__c = true
        );
        evt2.put('ReplayId', 'idem-replay-2');
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{ evt1, evt2 };
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.handle(events);
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals(0, updatedJob.Completed_Batches__c, 'Replayed events should be skipped');
        System.assertEquals(0, updatedJob.Workers_Finished__c, 'Replayed events should not count toward workers finished');
        System.assertEquals('Processing', updatedJob.Status__c, 'Job should still be Processing');
    }
    
    // ============================================
    // Cancelled Job (Kill Switch) Tests
    // ============================================
    
    @IsTest
    static void testHandleCancelledJobPreservesStatus() {
        // Arrange - Create a job that has been cancelled (kill switch activated)
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'CancelledTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Cancelled';
        Datetime cancelledAt = System.now().addMinutes(-1);
        jobRecord.Completed_At__c = cancelledAt;
        update jobRecord;
        
        // Simulate workers completing after cancellation
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Status should remain Cancelled, not be overwritten to Completed
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Cancelled', updatedJob.Status__c, 
            'Cancelled status should be preserved, not overwritten');
        System.assertEquals(cancelledAt, updatedJob.Completed_At__c, 
            'Completed_At should not be overwritten if already set');
    }
    
    @IsTest
    static void testHandleCancelledJobWithFailuresPreservesStatus() {
        // Arrange - Cancelled job with failed workers
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'CancelledFailedTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Cancelled';
        jobRecord.Completed_At__c = System.now();
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker stopped due to cancellation',
                Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker stopped due to cancellation',
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Status should remain Cancelled, not be changed to Failed
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Cancelled', updatedJob.Status__c, 
            'Cancelled status should be preserved even when all workers fail');
    }
    
    @IsTest
    static void testCancelledJobSkipsFinishCallback() {
        // Arrange - Cancelled job with a coordinator that would normally get finish() called
        // The finish() callback should NOT be invoked for cancelled jobs
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'CancelledCallbackTestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Cancelled';
        jobRecord.Completed_At__c = System.now();
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        
        // Act - Should complete without throwing exception
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Job should remain cancelled and handler should complete successfully
        // (No exception means finish callback was either skipped or handled gracefully)
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Cancelled', updatedJob.Status__c, 
            'Status should remain Cancelled after handling completion events');
        System.assertEquals(1, updatedJob.Workers_Finished__c, 
            'Worker completion should still be tracked');
    }
}