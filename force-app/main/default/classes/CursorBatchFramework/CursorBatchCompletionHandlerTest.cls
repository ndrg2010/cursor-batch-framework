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
        Assert.areEqual(2, updatedJob.Completed_Batches__c, 'Should increment completed batch count');
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Should increment workers finished count');
        Assert.areEqual(0, updatedJob.Failed_Workers__c, 'Failed count should be 0');
        Assert.areEqual('Processing', updatedJob.Status__c, 'Status should still be Processing (not all complete)');
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
        Assert.areEqual(0, updatedJob.Completed_Batches__c, 'Completed batch count should be 0');
        Assert.areEqual(0, updatedJob.Workers_Finished__c, 'Workers finished should be 0');
        Assert.areEqual(1, updatedJob.Failed_Workers__c, 'Should increment failed count');
        Assert.areEqual('Test error message', updatedJob.Error_Message__c, 
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
        Assert.areEqual(2, updatedJob.Completed_Batches__c, 'Should have 2 completed batches');
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Should have 2 workers finished');
        Assert.areEqual(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        Assert.areEqual('Worker 2 failed', updatedJob.Error_Message__c, 
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
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Should have 2 workers finished');
        Assert.areEqual('Completed', updatedJob.Status__c, 'Status should be Completed');
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 'Completed_At should be set');
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
        Assert.areEqual(1, updatedJob.Workers_Finished__c, 'Should have 1 worker finished');
        Assert.areEqual(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        Assert.areEqual('Completed with Errors', updatedJob.Status__c, 'Status should be Completed with Errors');
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 'Completed_At should be set');
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
        Assert.areEqual(0, updatedJob.Workers_Finished__c, 'Should have 0 workers finished');
        Assert.areEqual(2, updatedJob.Failed_Workers__c, 'Should have 2 failed');
        Assert.areEqual('Failed', updatedJob.Status__c, 'Status should be Failed when all workers fail');
        Assert.areEqual('Worker 1 failed', updatedJob.Error_Message__c, 'Should capture first error');
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 'Completed_At should be set');
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
        Assert.areEqual(jobCountBefore, jobCountAfter, 
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
        Assert.areEqual('Completed', updatedJob1.Status__c, 'Job 1 should be Completed');
        Assert.areEqual('Completed', updatedJob2.Status__c, 'Job 2 should be Completed');
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
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should complete even with invalid coordinator class');
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
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should still complete with non-existent class');
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
        Assert.areEqual(5, updatedJob.Total_Worker_Retries__c, 
            'Should aggregate retry counts (0 + 2 + 3 = 5)');
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Should have 2 workers finished');
        Assert.areEqual(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        Assert.areEqual('Completed with Errors', updatedJob.Status__c, 'Status should be Completed with Errors due to partial failure');
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
        Assert.areEqual(1, updatedJob.Total_Worker_Retries__c, 
            'Should handle null retry counts gracefully (only count the 1)');
        Assert.areEqual('Completed', updatedJob.Status__c, 'Status should be Completed');
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
        Assert.areEqual(7, ((Decimal) state.get('processedCount')).intValue(),
            'Reducer should merge page delta into the persisted state');
        Assert.areEqual(2, ((Decimal) state.get('pagesProcessed')).intValue(),
            'Reducer should update page count in persisted state');
    }
    
    @IsTest
    static void testHandleMultipleDeltasSameJobInSameBatch() {
        // Two completion events for the same job in one batch; both deltas must be applied.
        // Verifies reducer is applied per event and order does not break correctness (commutative).
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 2, 20);
        config.Query_Builder_Class__c = 'CursorJobTest.TestQueryBuilder';
        config.Worker_Class__c = 'CursorBatchTestUtils.TestStatefulCursorJobWorker';
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorJob'
        );
        jobRecord.State_JSON__c = '{"processedCount":0,"pagesProcessed":0,"jobName":"TestJob"}';
        update jobRecord;
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true,
                State_Delta__c = '{"processedCount":3,"pagesProcessed":1}'
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true,
                State_Delta__c = '{"processedCount":5,"pagesProcessed":1}'
            )
        };
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(updatedJob.State_JSON__c);
        Assert.areEqual(8, ((Decimal) state.get('processedCount')).intValue(),
            'Reducer should apply both deltas (3 + 5 = 8)');
        Assert.areEqual(2, ((Decimal) state.get('pagesProcessed')).intValue(),
            'Reducer should apply both page counts (1 + 1 = 2)');
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
        Assert.areEqual(1, updatedJob.Completed_Batches__c, 'Should count successful batch despite state reduction failure');
        Assert.areEqual(1, updatedJob.Workers_Finished__c, 'Should count worker finished');
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should complete and not stay stuck in Processing');
        Assert.areEqual(initialStateJson, updatedJob.State_JSON__c,
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
        Assert.areEqual(2, results.size(), 'Should have published 2 events');
        Assert.areEqual(true, results[0].isSuccess(), 'Event should have been published successfully');
        Assert.areEqual(true, results[1].isSuccess(), 'Event should have been published successfully');
        
        // The trigger should have fired and processed the events through the handler
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Trigger should have fired and handler should have processed both events');
        Assert.areEqual('Completed', updatedJob.Status__c, 'Status should be Completed');
    }
    
    // ============================================
    // Idempotency (Replay) and Cleanup Tests
    // ============================================
    
    @IsTest
    static void testHandleCompletedJobDeletesProcessedEvents() {
        // When a stateful job reaches terminal status, processed-event records for that job are deleted.
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 2, 20);
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;
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
        Assert.areEqual(0, remaining, 'Processed events for completed stateful job should be deleted');
    }
    
    @IsTest
    static void testNonStatefulJobNoProcessedEventsInsertedOrCleaned() {
        // Non-stateful jobs (no reducer) do not use idempotency: no insert, no cleanup delete.
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
        Integer count = [SELECT COUNT() FROM CursorBatch_Processed_Event__c WHERE Cursor_Batch_Job__c = :jobRecord.Id];
        Assert.areEqual(0, count, 'Non-stateful job should have no processed-event records inserted or cleaned');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should still complete normally');
    }
    
    @IsTest
    static void testHandleReplayedEventsSkippedWhenProcessedEventsExist() {
        // Idempotency runs only for stateful jobs. Verify stateful job path: use config with State_Reducer_Class__c.
        // (Replay skip cannot be asserted in unit test because ReplayId is not editable on platform events.)
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 2, 20);
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;
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
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(2, updatedJob.Completed_Batches__c, 'Stateful job should process both events');
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Both workers should be counted');
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should complete');
    }
    
    // ============================================
    // Finish Callback Idempotency Tests
    // ============================================
    
    @IsTest
    static void testFinishCallbackFiresOnceWhenThresholdCrossed() {
        // Arrange - 2-worker job whose final events all arrive in a single batch
        CursorBatchTestUtils.resetFinishCountingCoordinator();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishOnceJob', 2, 'CursorBatchTestUtils.FinishCountingCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true),
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(1, CursorBatchTestUtils.finishCountingCoordinator_finishCallCount,
            'finish() should be invoked exactly once by the batch that crosses the threshold');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should be Completed');
    }
    
    @IsTest
    static void testLatePageEventDoesNotRefireFinishCallback() {
        // Arrange - Both workers report their final page (job completes), then a non-final page
        // event for the same job is delivered afterwards. Worker page chaining does not depend on
        // this handler, so a delayed or redelivered completion-event batch can legitimately land
        // after every worker's final event has already been counted.
        CursorBatchTestUtils.resetFinishCountingCoordinator();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'LatePageEventJob', 2, 'CursorBatchTestUtils.FinishCountingCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> finalEvents = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true),
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        List<CursorBatch_WorkerComplete__e> latePageEvents = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = false)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(finalEvents);
        CursorBatch_Job__c afterCompletion = CursorBatchSelector.getJobById(jobRecord.Id);
        new CursorBatchCompletionHandler().handle(latePageEvents);
        Test.stopTest();
        
        // Assert - the late batch is still counted, but must not complete the job a second time
        Assert.areEqual(1, CursorBatchTestUtils.finishCountingCoordinator_finishCallCount,
            'finish() must not fire again for a job that was already complete');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(3, updatedJob.Completed_Batches__c, 'Late page event should still be counted');
        Assert.areEqual(2, updatedJob.Workers_Finished__c, 'Workers finished should stay at the worker count');
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should remain Completed');
        Assert.areEqual(afterCompletion.Completed_At__c, updatedJob.Completed_At__c,
            'Completed_At should keep the timestamp from the first completion');
    }
    
    @IsTest
    static void testRedeliveredFinalEventDoesNotRefireFinishCallback() {
        // Arrange - A redelivered final event pushes Workers_Finished past Total_Workers on a
        // non-stateful job (which has no processed-event idempotency), and must not re-complete it.
        CursorBatchTestUtils.resetFinishCountingCoordinator();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'RedeliveredFinalJob', 1, 'CursorBatchTestUtils.FinishCountingCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(1, CursorBatchTestUtils.finishCountingCoordinator_finishCallCount,
            'finish() must fire once even when a final event is redelivered');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(2, updatedJob.Workers_Finished__c,
            'Redelivered event still increments the counter (non-stateful jobs have no idempotency)');
    }
    
    // ============================================
    // Finish Callback Failure Tests
    // ============================================
    
    @IsTest
    static void testFinishFailureRecordedOnJob() {
        // Arrange - a job whose workers all succeed but whose finish() callback throws. The job
        // row is already committed as Completed before the callback runs, so without the
        // finish-failure write-back the failure would only exist in a debug log.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishThrowsJob', 1, 'CursorBatchTestUtils.ThrowingFinishCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed with Errors', updatedJob.Status__c,
            'A failing finish() should upgrade the job status instead of leaving it Completed');
        Assert.isTrue(updatedJob.Error_Message__c.contains('finish() failed'),
            'Error message should identify the failure as coming from finish()');
        Assert.isTrue(updatedJob.Error_Message__c.contains(CursorBatchTestUtils.THROWING_FINISH_MESSAGE),
            'Error message should include the underlying exception message');
    }
    
    @IsTest
    static void testFinishFailureAppendsToWorkerError() {
        // Arrange - one worker fails and one succeeds, so the job already carries a worker error
        // and 'Completed with Errors'. The finish() failure must be appended, not overwrite it.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishThrowsMixedJob', 2, 'CursorBatchTestUtils.ThrowingFinishCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id, Success__c = false, Error_Message__c = 'worker boom', Is_Final__c = true
            ),
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed with Errors', updatedJob.Status__c, 'Status should stay Completed with Errors');
        Assert.isTrue(updatedJob.Error_Message__c.startsWith('worker boom'),
            'The first worker error should be preserved at the front of the message');
        Assert.isTrue(updatedJob.Error_Message__c.contains(CursorBatchTestUtils.THROWING_FINISH_MESSAGE),
            'The finish() failure should be appended to the existing error');
    }
    
    @IsTest
    static void testFinishFailureDoesNotDowngradeFailedStatus() {
        // Arrange - every worker fails, so the job is 'Failed'. A subsequent finish() failure
        // must not soften that to 'Completed with Errors'.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishThrowsFailedJob', 1, 'CursorBatchTestUtils.ThrowingFinishCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id, Success__c = false, Error_Message__c = 'worker boom', Is_Final__c = true
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c, 'Failed is more severe and must not be downgraded');
        Assert.isTrue(updatedJob.Error_Message__c.contains(CursorBatchTestUtils.THROWING_FINISH_MESSAGE),
            'The finish() failure should still be recorded on a Failed job');
    }
    
    @IsTest
    static void testFinishFailureMirroredToParent() {
        // Arrange - the parent is mirrored before the finish callback runs, so it initially reads
        // 'Completed'; the upgraded status has to be pushed to the parent a second time.
        CursorBatch_Job_Parent__c parent = new CursorBatch_Job_Parent__c(
            Config_Developer_Name__c = 'FinishThrowsParentJob',
            Config_Label__c = 'FinishThrowsParentJob',
            Last_Job_Started_At__c = System.now()
        );
        insert parent;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishThrowsParentJob', 1, 'CursorBatchTestUtils.ThrowingFinishCoordinator'
        );
        jobRecord.Job_Parent__c = parent.Id;
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job_Parent__c updatedParent = [
            SELECT Id, Last_Job_Status__c FROM CursorBatch_Job_Parent__c WHERE Id = :parent.Id
        ];
        Assert.areEqual('Completed with Errors', updatedParent.Last_Job_Status__c,
            'Parent Last_Job_Status__c should reflect the status after the finish() failure');
    }
    
    @IsTest
    static void testFinishFailureDoesNotBreakEventProcessing() {
        // Arrange - a finish() failure must never bubble out of the platform-event handler or
        // roll back the worker counters that were already committed.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishThrowsNoBubbleJob', 1, 'CursorBatchTestUtils.ThrowingFinishCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        try {
            new CursorBatchCompletionHandler().handle(events);
        } catch (Exception e) {
            Assert.fail('handle() should not propagate a finish() failure: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(1, updatedJob.Workers_Finished__c, 'Worker counters should still be committed');
        Assert.areEqual(1, updatedJob.Completed_Batches__c, 'Batch counters should still be committed');
        Assert.isNotNull(updatedJob.Completed_At__c, 'Completed timestamp should still be set');
    }
    
    @IsTest
    static void testSuccessfulFinishLeavesJobClean() {
        // Arrange - regression guard: a finish() that returns normally must not touch the status
        // or write an error message.
        CursorBatchTestUtils.resetFinishCountingCoordinator();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishSucceedsJob', 1, 'CursorBatchTestUtils.FinishCountingCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed', updatedJob.Status__c, 'A clean finish should leave the job Completed');
        Assert.isNull(updatedJob.Error_Message__c, 'A clean finish should not write an error message');
    }
    
    @IsTest
    static void testUnconstructableCoordinatorDoesNotFlipStatus() {
        // Arrange - TestCursorBatchCoordinator has no no-arg constructor, so Type.newInstance()
        // throws and finish() never runs. That is a reflection failure, not a failure in the
        // caller's finish() logic, so it is logged only and must not mark the job as errored.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'UnconstructableCoordinatorJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(Job_Id__c = jobRecord.Id, Success__c = true, Is_Final__c = true)
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed', updatedJob.Status__c,
            'A coordinator that cannot be constructed should not mark the job as errored');
        Assert.isNull(updatedJob.Error_Message__c, 'No error message should be written');
    }
    
    @IsTest
    static void testWorkerInvokeFinishCallbackReturnsException() {
        // Arrange - covers the CursorJob (worker) finish path directly, without needing a
        // CursorBatch_Config__mdt record to route through routeFinishCallbackInternal.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'WorkerFinishThrowsJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        Exception thrown = CursorBatchWorker.invokeFinishCallback(
            'CursorBatchTestUtils.ThrowingFinishWorker', jobRecord, mockLogger
        );
        Exception clean = CursorBatchWorker.invokeFinishCallback(
            'CursorBatchTestUtils.TestCursorBatchWorker', jobRecord, mockLogger
        );
        Test.stopTest();
        
        // Assert
        Assert.isNotNull(thrown, 'A failing worker finish() should return its exception to the caller');
        Assert.isTrue(thrown.getMessage().contains(CursorBatchTestUtils.THROWING_FINISH_MESSAGE),
            'The returned exception should be the one thrown by finish()');
        Assert.isNull(clean, 'A worker finish() that completes should return null');
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
        Assert.areEqual('Cancelled', updatedJob.Status__c, 
            'Cancelled status should be preserved, not overwritten');
        Assert.areEqual(cancelledAt, updatedJob.Completed_At__c, 
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
        Assert.areEqual('Cancelled', updatedJob.Status__c, 
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
        Assert.areEqual('Cancelled', updatedJob.Status__c, 
            'Status should remain Cancelled after handling completion events');
        Assert.areEqual(1, updatedJob.Workers_Finished__c, 
            'Worker completion should still be tracked');
    }
    
    // ============================================
    // CursorBatch_Job_Parent__c Last_Job_Status__c Tests
    // ============================================
    
    @IsTest
    static void testParentLastStatusUpdatedOnCompletion() {
        // Arrange - linked parent + a job that will reach 'Completed' on the next event
        CursorBatch_Job_Parent__c parent = new CursorBatch_Job_Parent__c(
            Config_Developer_Name__c = 'ParentStatusJob',
            Config_Label__c = 'ParentStatusJob',
            Last_Job_Started_At__c = System.now()
        );
        insert parent;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'ParentStatusJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Job_Parent__c = parent.Id;
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null,
                Is_Final__c = true
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert - parent reflects the terminal job status
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Completed', updatedJob.Status__c, 'Job should be Completed');
        CursorBatch_Job_Parent__c updatedParent = [
            SELECT Id, Last_Job_Status__c FROM CursorBatch_Job_Parent__c WHERE Id = :parent.Id
        ];
        Assert.areEqual('Completed', updatedParent.Last_Job_Status__c,
            'Parent Last_Job_Status__c should be set to the terminal job status');
    }
    
    @IsTest
    static void testParentLastStatusUpdatedOnFailure() {
        // Arrange - parent + single-worker job that will fail and reach 'Failed'
        CursorBatch_Job_Parent__c parent = new CursorBatch_Job_Parent__c(
            Config_Developer_Name__c = 'ParentFailJob',
            Config_Label__c = 'ParentFailJob',
            Last_Job_Started_At__c = System.now()
        );
        insert parent;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'ParentFailJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Job_Parent__c = parent.Id;
        update jobRecord;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'boom',
                Is_Final__c = true
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job_Parent__c updatedParent = [
            SELECT Id, Last_Job_Status__c FROM CursorBatch_Job_Parent__c WHERE Id = :parent.Id
        ];
        Assert.areEqual('Failed', updatedParent.Last_Job_Status__c,
            'Parent Last_Job_Status__c should reflect Failed terminal status');
    }
    
    @IsTest
    static void testParentLastStatusUpdatedOnCancelled() {
        // Arrange - parent + cancelled job. Completion events still arrive after killJob; the
        // handler skips the finish callback but should still write 'Cancelled' onto the parent.
        CursorBatch_Job_Parent__c parent = new CursorBatch_Job_Parent__c(
            Config_Developer_Name__c = 'ParentCancelJob',
            Config_Label__c = 'ParentCancelJob',
            Last_Job_Started_At__c = System.now()
        );
        insert parent;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'ParentCancelJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Job_Parent__c = parent.Id;
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
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert - parent reflects Cancelled even though finish callback was skipped
        CursorBatch_Job_Parent__c updatedParent = [
            SELECT Id, Last_Job_Status__c FROM CursorBatch_Job_Parent__c WHERE Id = :parent.Id
        ];
        Assert.areEqual('Cancelled', updatedParent.Last_Job_Status__c,
            'Parent Last_Job_Status__c should reflect Cancelled terminal status');
    }
    
    @IsTest
    static void testParentUpdateFailureSwallowed() {
        // Arrange - call routeFinishCallback directly with an in-memory job snapshot whose
        // Job_Parent__c points at a syntactically-valid but already-deleted parent ID. The
        // update inside updateParentLastStatus will throw ENTITY_IS_DELETED; that exception
        // must be caught and logged instead of bubbling up to the caller.
        // (Going through handle() doesn't work because Job_Parent__c is SetNull-on-parent-delete,
        //  which would null the lookup before the handler ever sees it.)
        CursorBatch_Job_Parent__c parent = new CursorBatch_Job_Parent__c(
            Config_Developer_Name__c = 'ParentSwallowJob',
            Config_Label__c = 'ParentSwallowJob',
            Last_Job_Started_At__c = System.now()
        );
        insert parent;
        Id deletedParentId = parent.Id;
        delete parent;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'ParentSwallowJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        update jobRecord;
        
        CursorBatch_Job__c snapshot = new CursorBatch_Job__c(
            Id = jobRecord.Id,
            Job_Name__c = 'ParentSwallowJob',
            Status__c = 'Completed',
            Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
            Job_Parent__c = deletedParentId
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act - must not throw
        Test.startTest();
        CursorBatchCompletionHandler.routeFinishCallback(snapshot, mockLogger);
        Test.stopTest();
        
        // Assert - the parent update failure was logged, downstream routing still ran
        Boolean foundParentFailure = false;
        for (String msg : mockLogger.exceptionMessages) {
            if (msg.contains('parent Last_Job_Status__c')) {
                foundParentFailure = true;
                break;
            }
        }
        Assert.isTrue(foundParentFailure,
            'Parent update failure should be logged via logException');
    }
    
    // ============================================
    // Terminal Status Logging Tests
    // ============================================
    
    @IsTest
    static void testTerminalStatusLogsErrorForFailedJob() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TerminalFailedJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator', 40
        );
        jobRecord.Status__c = 'Failed';
        jobRecord.Failed_Workers__c = 2;
        jobRecord.Error_Message__c = 'worker blew up';
        update jobRecord;
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(
            CursorBatchSelector.getJobById(jobRecord.Id), mockLogger
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual(1, mockLogger.errorMessages.size(), 'Should emit exactly one error entry');
        String entry = mockLogger.errorMessages[0];
        Assert.isTrue(entry.startsWith('[' + CursorBatchLogger.SCOPE_JOB_FAILED + ']'),
            'Entry should be scoped as a job failure: ' + entry);
        Assert.isTrue(entry.contains('TerminalFailedJob'), 'Entry should name the job');
        Assert.isTrue(entry.contains(jobRecord.Id), 'Entry should include the job Id');
        Assert.isTrue(entry.contains('worker blew up'), 'Entry should include the recorded error');
        Assert.areEqual(0, mockLogger.infoMessages.size(), 'A failed job should not also log info');
    }
    
    @IsTest
    static void testTerminalStatusLogsErrorForCompletedWithErrors() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TerminalPartialJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed with Errors';
        update jobRecord;
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(
            CursorBatchSelector.getJobById(jobRecord.Id), mockLogger
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual(1, mockLogger.errorMessages.size(), 'Should emit exactly one error entry');
        Assert.isTrue(
            mockLogger.errorMessages[0].startsWith('[' + CursorBatchLogger.SCOPE_JOB_COMPLETED_WITH_ERRORS + ']'),
            'Entry should be scoped as a partial failure: ' + mockLogger.errorMessages[0]
        );
    }
    
    @IsTest
    static void testTerminalStatusLogsInfoForCompletedAndCancelled() {
        // Arrange
        CursorBatch_Job__c completed = CursorBatchTestUtils.createTestJobRecord(
            'TerminalCompletedJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        completed.Status__c = 'Completed';
        update completed;
        
        CursorBatch_Job__c cancelled = CursorBatchTestUtils.createTestJobRecord(
            'TerminalCancelledJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        cancelled.Status__c = 'Cancelled';
        update cancelled;
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(CursorBatchSelector.getJobById(completed.Id), mockLogger);
        CursorBatchCompletionHandler.logTerminalStatus(CursorBatchSelector.getJobById(cancelled.Id), mockLogger);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(0, mockLogger.errorMessages.size(),
            'Neither a clean completion nor a deliberate cancellation is an error');
        Assert.areEqual(2, mockLogger.infoMessages.size(), 'Both should log at info level');
        Assert.isTrue(mockLogger.hasInfoContaining('[' + CursorBatchLogger.SCOPE_JOB_COMPLETED + ']'),
            'Completed job should carry the completed scope');
        Assert.isTrue(mockLogger.hasInfoContaining('[' + CursorBatchLogger.SCOPE_JOB_CANCELLED + ']'),
            'Cancelled job should carry the cancelled scope');
    }
    
    @IsTest
    static void testTerminalStatusFailureDoesNotRollBackJobUpdate() {
        // Arrange - a logging adapter that persists entries with DML could throw; that must not
        // roll back the terminal job update it runs alongside.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TerminalThrowingLoggerJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Failed';
        update jobRecord;
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(
            CursorBatchSelector.getJobById(jobRecord.Id),
            new CursorBatchTestUtils.ThrowingCursorBatchLogger()
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual('Failed', CursorBatchSelector.getJobById(jobRecord.Id).Status__c,
            'The terminal update must survive a failing logger');
    }
    
    @IsTest
    static void testTerminalStatusTagsFailureWithJobTagAndScope() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TaggedJob', 1, 20);
        CursorBatchCoordinator.testConfig.Logger_Tag__c = 'Billing Engine';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TaggedJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Failed';
        update jobRecord;
        
        // Act - base logger must be Callable for the scope tag to be applied
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(
            CursorBatchSelector.getJobById(jobRecord.Id),
            CursorBatchLogger.resolveLogger('Billing Engine')
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual(
            new Set<String>{ 'Billing Engine', CursorBatchLogger.TAG_JOB_FAILURE },
            CursorBatchTestUtils.lastCapturedTags(),
            'Terminal failure should carry the job tag and the job-failure scope tag'
        );
    }
    
    @IsTest
    static void testTerminalStatusFallsBackToDefaultTagWhenConfigTagBlank() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('UntaggedJob', 1, 20);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'UntaggedJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Failed';
        update jobRecord;
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(
            CursorBatchSelector.getJobById(jobRecord.Id),
            CursorBatchLogger.resolveLogger(null)
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual(
            new Set<String>{ CursorBatchCompletionHandler.DEFAULT_LOG_TAG, CursorBatchLogger.TAG_JOB_FAILURE },
            CursorBatchTestUtils.lastCapturedTags(),
            'A blank Logger_Tag__c must fall back to the default tag rather than emitting untagged'
        );
    }
    
    @IsTest
    static void testTerminalStatusCarriesPlatformFailureCodeTag() {
        // Arrange - the platform code reaches the job record inside Error_Message__c
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TimedOutJob', 1, 20);
        CursorBatchCoordinator.testConfig.Logger_Tag__c = 'Billing Engine';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TimedOutJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Failed';
        jobRecord.Error_Message__c = 'System.UnexpectedException: connection was cancelled here\n\n' +
            'Platform status: [QUERY_TIMEOUT] Your query request was running for too long.';
        update jobRecord;
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.logTerminalStatus(
            CursorBatchSelector.getJobById(jobRecord.Id),
            CursorBatchLogger.resolveLogger('Billing Engine')
        );
        Test.stopTest();
        
        // Assert
        Assert.isTrue(
            CursorBatchTestUtils.lastCapturedTags().contains('CursorBatch Failure QUERY_TIMEOUT'),
            'Terminal failure should be filterable by the platform error code, got: ' +
                CursorBatchTestUtils.lastCapturedTags()
        );
    }
    
    @IsTest
    static void testWorkerFailureEventIsScopedAsWorkerNotJob() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'ScopedWorkerFailJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'page 1 exploded',
                Is_Final__c = true
            )
        };
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        Assert.isTrue(mockLogger.hasErrorContaining('[' + CursorBatchLogger.SCOPE_WORKER_FAILED + ']'),
            'A single worker failure should be scoped as a worker failure');
        Assert.isFalse(mockLogger.hasErrorContaining('[' + CursorBatchLogger.SCOPE_JOB_FAILED + ']'),
            'A worker failure must not be reported as a job-level failure while workers remain');
    }
    
    @IsTest
    static void testWorkerFailuresAggregateToOneEntryPerBatch() {
        // Arrange - a wide fan-out job failing everywhere. One entry per event would make log
        // volume and DML scale with the subscriber batch size.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'WideFanOutFailJob', 100, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>();
        for (Integer i = 0; i < 50; i++) {
            events.add(new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'worker ' + i + ' died',
                Is_Final__c = true
            ));
        }
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(1, mockLogger.errorMessages.size(),
            '50 failed events should produce one summary entry, got: ' + mockLogger.errorMessages.size());
        String entry = mockLogger.errorMessages[0];
        Assert.isTrue(entry.contains('50 worker failure(s) in this event batch'),
            'The summary should report the failure count: ' + entry);
        Assert.isTrue(entry.contains('worker 0 died'), 'The summary should sample the errors');
        Assert.isTrue(entry.contains('more distinct error(s)'),
            'The summary should indicate how many errors were not sampled: ' + entry);
    }
    
    @IsTest
    static void testWorkerFailureSummaryDeduplicatesIdenticalErrors() {
        // Arrange - a shared cause such as a query timeout produces the same text on every worker
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'SharedCauseFailJob', 100, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>();
        for (Integer i = 0; i < 20; i++) {
            events.add(new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Platform status: [QUERY_TIMEOUT] Your query request was running for too long.',
                Is_Final__c = true
            ));
        }
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        String entry = mockLogger.errorMessages[0];
        Assert.isTrue(entry.contains('20 worker failure(s)'), 'Should still report the true count');
        Assert.isFalse(entry.contains('more distinct error(s)'),
            'Identical errors collapse to one sample, so nothing should be reported as omitted: ' + entry);
    }
    
    @IsTest
    static void testFinishFailureLogsOnceScopedAsJobLevel() {
        // Arrange - a metadata-driven job whose worker finish() throws. The callback is reflected
        // onto the worker class, so it must still report as a job-level failure.
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('FinishFailJob', 1, 20);
        CursorBatchCoordinator.testConfig.Query_Builder_Class__c = 'CursorBatchTestUtils';
        CursorBatchCoordinator.testConfig.Worker_Class__c = 'CursorBatchTestUtils.ThrowingFinishWorker';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishFailJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        update jobRecord;
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.routeFinishCallback(
            CursorBatchSelector.getJobById(jobRecord.Id), mockLogger
        );
        Test.stopTest();
        
        // Assert - exactly one entry describes the finish failure, and it is scoped as job-level
        Integer finishFailureEntries = 0;
        for (String msg : mockLogger.exceptionMessages) {
            if (msg.contains('[' + CursorBatchLogger.SCOPE_JOB_FINISH_FAILED + ']')) {
                finishFailureEntries++;
            }
        }
        for (String msg : mockLogger.errorMessages) {
            if (msg.contains('[' + CursorBatchLogger.SCOPE_JOB_FINISH_FAILED + ']')) {
                finishFailureEntries++;
            }
        }
        Assert.areEqual(1, finishFailureEntries,
            'A finish() failure should produce exactly one scoped entry, got: ' +
                mockLogger.exceptionMessages + ' / ' + mockLogger.errorMessages);
        Assert.isTrue(mockLogger.hasErrorContaining('[' + CursorBatchLogger.SCOPE_JOB_COMPLETED_WITH_ERRORS + ']'),
            'The terminal entry should report the status upgraded by the finish failure');
    }
    
    @IsTest
    static void testWorkerLoggerIsTaggedOnTheFinishPath() {
        // Arrange - the worker is constructed by reflection purely to call finish(), so
        // initialize() never runs. Without explicit tagging there, anything a subclass logs
        // inside finish() would be untagged and subscribers would re-call setLogger to fix it.
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('FinishTagJob', 1, 20);
        CursorBatchCoordinator.testConfig.Logger_Tag__c = 'Billing Engine';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FinishTagJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Act
        Test.startTest();
        CursorBatchWorker.invokeFinishCallback(
            'CursorBatchTestUtils.LoggingFinishWorker',
            CursorBatchSelector.getJobById(jobRecord.Id),
            CursorBatchLogger.resolveLogger('Billing Engine')
        );
        Test.stopTest();
        
        // Assert
        Assert.isTrue(
            CursorBatchTestUtils.hasCapturedTagSetContaining(new Set<String>{ 'Billing Engine' }),
            'A worker logging inside finish() should carry the job tag. Captured: ' +
                CursorBatchTestUtils.capturedTagSets
        );
    }
    
    @IsTest
    static void testCoordinatorLoggerIsTaggedOnTheFinishPath() {
        // Arrange - same gap on the coordinator's reflection path, where initializeJobName()
        // runs instead of the tagging constructor.
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('CoordFinishTagJob', 1, 20);
        CursorBatchCoordinator.testConfig.Logger_Tag__c = 'Billing Engine';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'CoordFinishTagJob', 1, 'CursorBatchTestUtils.LoggingFinishCoordinator'
        );
        
        // Act
        Test.startTest();
        CursorBatchCoordinator.invokeFinishCallback(
            'CursorBatchTestUtils.LoggingFinishCoordinator',
            'CoordFinishTagJob',
            CursorBatchSelector.getJobById(jobRecord.Id),
            CursorBatchLogger.resolveLogger('Billing Engine')
        );
        Test.stopTest();
        
        // Assert
        Assert.isTrue(
            CursorBatchTestUtils.hasCapturedTagSetContaining(new Set<String>{ 'Billing Engine' }),
            'A coordinator logging inside finish() should carry the job tag. Captured: ' +
                CursorBatchTestUtils.capturedTagSets
        );
    }
    
    @IsTest
    static void testTerminalStatusReportsUpgradedStatusAfterFinishFailure() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('UpgradeStatusJob', 1, 20);
        CursorBatchCoordinator.testConfig.Query_Builder_Class__c = 'CursorBatchTestUtils';
        CursorBatchCoordinator.testConfig.Worker_Class__c = 'CursorBatchTestUtils.ThrowingFinishWorker';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'UpgradeStatusJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        update jobRecord;
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        CursorBatchCompletionHandler.routeFinishCallback(
            CursorBatchSelector.getJobById(jobRecord.Id), mockLogger
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual('Completed with Errors', CursorBatchSelector.getJobById(jobRecord.Id).Status__c,
            'A throwing finish() should upgrade the status');
        Assert.isFalse(mockLogger.hasInfoContaining('[' + CursorBatchLogger.SCOPE_JOB_COMPLETED + ']'),
            'The terminal entry must not claim a clean completion for a job that ended in error');
    }
}