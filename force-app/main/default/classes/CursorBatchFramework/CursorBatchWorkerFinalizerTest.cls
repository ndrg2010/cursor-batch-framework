/**
 * @description Unit tests for CursorBatchWorkerFinalizer.
 *              Note: System.FinalizerContext cannot be easily mocked, so tests focus on
 *              constructor initialization and event structure validation.
 *              Uses MockCursorBatchCacheService to avoid Platform Cache dependency.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchWorkerFinalizerTest {
    
    @IsTest
    static void testConstructor() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        Integer workerNum = 3;
        ICursorBatchLogger logger = CursorBatchLogger.getDefault();
        
        // Act
        Test.startTest();
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            jobRecord.Id, workerNum, logger
        );
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, finalizer, 'Finalizer should be instantiated');
    }
    
    @IsTest
    static void testIntegrationWithCompletionHandler() {
        // Arrange - Create a complete flow from event to handler
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Simulate what the finalizer would publish
        CursorBatch_WorkerComplete__e evt = new CursorBatch_WorkerComplete__e(
            Job_Id__c = jobRecord.Id,
            Success__c = true,
            Error_Message__c = null
        );
        
        // Act - Only manually invoke the handler (not EventBus.publish + handler)
        // to avoid double-counting in test context where triggers may fire synchronously
        CursorBatchCompletionHandler handler = new CursorBatchCompletionHandler();
        handler.setCacheService(new MockCursorBatchCacheService());
        
        Test.startTest();
        handler.handle(new List<CursorBatch_WorkerComplete__e>{evt});
        Test.stopTest();
        
        // Assert - The handler should update the job
        CursorBatch_Job__c updatedJob = [SELECT Status__c, Completed_Workers__c 
                                          FROM CursorBatch_Job__c WHERE Id = :jobRecord.Id];
        System.assertEquals('Complete', updatedJob.Status__c, 'Job should be marked complete');
        System.assertEquals(1, updatedJob.Completed_Workers__c, 'Completed count should be 1');
    }
    
    @IsTest
    static void testExecuteInternalWithSuccess() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            jobRecord.Id, 1, mockLogger
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(true, null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(0, mockLogger.errorMessages.size(), 
            'Should not log errors for successful execution');
    }
    
    @IsTest
    static void testExecuteInternalWithFailure() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            jobRecord.Id, 1, mockLogger
        );
        
        Exception testEx = new System.AsyncException('Test exception');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert
        System.assert(mockLogger.errorMessages.size() > 0 || 
                      mockLogger.loggedExceptions.size() > 0, 
            'Should log error for failed execution');
    }
    
    @IsTest
    static void testExecuteInternalWithFailureAndNullException() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            jobRecord.Id, 1, mockLogger
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, null);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'Should handle null exception without error');
    }
    
    @IsTest
    static void testExecuteWithFailure() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            jobRecord.Id, 1, mockLogger
        );
        
        MockFinalizerContext failureCtx = new MockFinalizerContext(System.ParentJobResult.UNHANDLED_EXCEPTION);
        
        // Act
        Test.startTest();
        finalizer.execute(failureCtx);
        Test.stopTest();
        
        // Assert
        System.assert(mockLogger.errorMessages.size() > 0 || 
                      mockLogger.loggedExceptions.size() > 0, 
            'Should log error for failed execution');
    }
    
    @IsTest
    static void testEventPublishWithMockHandler() {
        // Arrange - Test event publishing via EventBus
        // Note: In test context, Platform Events may or may not fire triggers synchronously
        // This test verifies that events can be published without errors
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatch_WorkerComplete__e evt = new CursorBatch_WorkerComplete__e(
            Job_Id__c = jobRecord.Id,
            Success__c = true,
            Error_Message__c = null
        );
        
        // Act
        Test.startTest();
        Database.SaveResult result = EventBus.publish(evt);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.isSuccess(), 'Event should be published successfully');
    }
    
    /**
     * @description Mock implementation of System.FinalizerContext for testing
     */
    private class MockFinalizerContext implements System.FinalizerContext {
        private System.ParentJobResult result;
        private Exception ex;
        
        public MockFinalizerContext(System.ParentJobResult result) {
            this.result = result;
            this.ex = new System.AsyncException('Test exception');
        }
        
        public void setException(Exception e) {
            this.ex = e;
        }
        
        public void setExceptionToNull() {
            this.ex = null;
        }
        
        public Id getAsyncApexJobId() {
            String prefix = AsyncApexJob.SObjectType.getDescribe().getKeyPrefix();
            return Id.valueOf(prefix + '000000000001');
        }
        
        public Exception getException() {
            return this.ex;
        }
        
        public String getRequestId() {
            return 'testRequestId';
        }
        
        public System.ParentJobResult getResult() {
            return this.result;
        }
    }
}
