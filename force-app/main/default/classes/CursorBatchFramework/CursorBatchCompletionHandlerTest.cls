/**
 * @description Unit tests for CursorBatchCompletionHandler Platform Event handler.
 *              Uses MockCursorBatchCacheService to avoid Platform Cache dependency.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchCompletionHandlerTest {
    
    @IsTest
    static void testHandleWithNullEvents() {
        // Arrange
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(null);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'Handle should gracefully handle null events');
    }
    
    @IsTest
    static void testHandleWithEmptyEvents() {
        // Arrange
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        List<CursorBatch_WorkerComplete__e> emptyEvents = new List<CursorBatch_WorkerComplete__e>();
        
        // Act
        Test.startTest();
        handler.handle(emptyEvents);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'Handle should gracefully handle empty events');
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
                Error_Message__c = null
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Completed_Workers__c, Failed_Workers__c, Status__c 
                                          FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals(2, updatedJob.Completed_Workers__c, 'Should increment completed count');
        System.assertEquals(0, updatedJob.Failed_Workers__c, 'Failed count should be 0');
        System.assertEquals('Running', updatedJob.Status__c, 'Status should still be Running (not all complete)');
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
                Error_Message__c = 'Test error message'
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Completed_Workers__c, Failed_Workers__c, 
                                          Status__c, Error_Message__c 
                                          FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals(0, updatedJob.Completed_Workers__c, 'Completed count should be 0');
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
                Error_Message__c = null
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker 2 failed'
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Completed_Workers__c, Failed_Workers__c, 
                                          Status__c, Error_Message__c 
                                          FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals(2, updatedJob.Completed_Workers__c, 'Should have 2 completed');
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
                Error_Message__c = null
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Completed_Workers__c, Failed_Workers__c, 
                                          Status__c, Completed_At__c 
                                          FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals(2, updatedJob.Completed_Workers__c, 'Should have 2 completed');
        System.assertEquals('Complete', updatedJob.Status__c, 'Status should be Complete');
        System.assertNotEquals(null, updatedJob.Completed_At__c, 'Completed_At should be set');
    }
    
    @IsTest
    static void testHandleAllWorkersCompleteWithFailures() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Worker failed'
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Completed_Workers__c, Failed_Workers__c, 
                                          Status__c, Completed_At__c 
                                          FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals(1, updatedJob.Completed_Workers__c, 'Should have 1 completed');
        System.assertEquals(1, updatedJob.Failed_Workers__c, 'Should have 1 failed');
        System.assertEquals('Failed', updatedJob.Status__c, 'Status should be Failed');
        System.assertNotEquals(null, updatedJob.Completed_At__c, 'Completed_At should be set');
    }
    
    @IsTest
    static void testHandleWithMissingJobRecord() {
        // Arrange
        Id fakeJobId = CursorBatch_Job__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = fakeJobId,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'Handler should handle missing job record gracefully');
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
                Error_Message__c = null
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord2.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob1 = [SELECT Status__c FROM CursorBatch_Job__c WHERE Id = :jobRecord1.Id];
        CursorBatch_Job__c updatedJob2 = [SELECT Status__c FROM CursorBatch_Job__c WHERE Id = :jobRecord2.Id];
        System.assertEquals('Complete', updatedJob1.Status__c, 'Job 1 should be Complete');
        System.assertEquals('Complete', updatedJob2.Status__c, 'Job 2 should be Complete');
    }
    
    @IsTest
    static void testCallbackWithClassNotExtendingCoordinator() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'String'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Status__c FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals('Complete', updatedJob.Status__c, 'Job should complete');
    }
    
    @IsTest
    static void testCallbackWithInvalidCoordinatorClass() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'NonExistentCoordinatorClass'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Status__c FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals('Complete', updatedJob.Status__c, 'Job should still complete');
    }
    
    @IsTest
    static void testOnlyFirstErrorCaptured() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 3, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'First error'
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = false,
                Error_Message__c = 'Second error'
            ),
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = jobRecord.Id,
                Success__c = true,
                Error_Message__c = null
            )
        };
        
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = [SELECT Error_Message__c FROM CursorBatch_Job__c 
                                          WHERE Id = :jobRecord.Id];
        System.assertEquals('First error', updatedJob.Error_Message__c, 
            'Should only capture first error message');
    }
}
