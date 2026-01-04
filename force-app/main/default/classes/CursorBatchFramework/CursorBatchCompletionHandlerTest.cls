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
}