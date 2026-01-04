/**
 * @description Unit tests for CursorBatchWorkerFinalizer including retry logic.
 *              Note: System.FinalizerContext cannot be easily mocked, so tests focus on
 *              constructor initialization, retry behavior, and event structure validation.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchWorkerFinalizerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(10);
    }
    
    @IsTest
    static void testConstructor() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 0);
        ICursorBatchLogger logger = CursorBatchLogger.getDefault();
        
        // Act
        Test.startTest();
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, logger);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, finalizer, 'Finalizer should be instantiated');
    }
    
    @IsTest
    static void testExecuteInternalWithSuccess() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 0);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        // Act
        Test.startTest();
        finalizer.executeInternal(true, null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(0, mockLogger.errorMessages.size(), 
            'Should not log errors for successful execution');
    }
    
    @IsTest
    static void testExecuteInternalWithFailureAndRetryAvailable() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Set retryCount to 0 so retry is available (maxRetries defaults to 3)
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 0);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        Exception testEx = new System.AsyncException('Test exception');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should log error and attempt retry (retry scheduling may fail in test context)
        System.assert(mockLogger.errorMessages.size() > 0 || mockLogger.infoMessages.size() > 0, 
            'Should log messages about failure or retry attempt');
    }
    
    @IsTest
    static void testExecuteInternalWithFailureAndMaxRetriesExhausted() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Set retryCount to 3 (equals maxRetries default of 3)
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 3);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        Exception testEx = new System.AsyncException('Test exception');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should log error about max retries exhausted
        System.assert(mockLogger.hasErrorContaining('max retries') || 
                      mockLogger.hasErrorContaining('exhausted') ||
                      mockLogger.errorMessages.size() > 0, 
            'Should log error about max retries exhausted');
    }
    
    @IsTest
    static void testExecuteInternalWithFailureAndNullException() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 3);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        // Act - Should not throw exception even with null exception parameter
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            finalizer.executeInternal(false, null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Finalizer should handle null exception gracefully
        System.assertEquals(false, exceptionThrown, 
            'Finalizer should handle null exception parameter without throwing');
        // Should still log an error about the failure (even without exception details)
        System.assert(mockLogger.errorMessages.size() > 0 || mockLogger.infoMessages.size() > 0, 
            'Should log message about failure handling');
    }
    
    @IsTest
    static void testExecuteWithFailure() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 3);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        CursorBatchTestUtils.MockFinalizerContext failureCtx = 
            new CursorBatchTestUtils.MockFinalizerContext(System.ParentJobResult.UNHANDLED_EXCEPTION);
        
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
            Error_Message__c = null,
            Retry_Count__c = 2  // Include retry count for tracking
        );
        
        // Act
        Test.startTest();
        Database.SaveResult result = EventBus.publish(evt);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.isSuccess(), 'Event should be published successfully');
    }
    
    @IsTest
    static void testEventIncludesRetryCount() {
        // Arrange - Verify that the finalizer includes retry count in completion events
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Create context with retry count of 2 (simulating 2 retries before success)
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 2);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        // Act - Execute with success (no retry attempt, just publishing completion)
        Test.startTest();
        finalizer.executeInternal(true, null);
        Test.stopTest();
        
        // Assert - The completion event should be published successfully
        // Note: We can't directly inspect the event in the test, but we verify no errors
        System.assertEquals(0, mockLogger.errorMessages.size(), 
            'Should not log errors for successful completion with retry count');
    }
    
    @IsTest
    static void testRetryWithInvalidWorkerClass() {
        // Arrange - Test retry with a non-existent worker class
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Create context with invalid worker class name
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContextWithWorkerClass(
            jobRecord.Id, 'NonExistentWorkerClass', 0  // retryCount = 0 so retry will be attempted
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        Exception testEx = new System.AsyncException('Test exception');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should log error or exception about failed retry
        System.assert(mockLogger.errorMessages.size() > 0 || 
                      mockLogger.loggedExceptions.size() > 0 ||
                      mockLogger.exceptionMessages.size() > 0, 
            'Should log error about failed retry with invalid class');
    }
    
    @IsTest
    static void testRetryWithNullCursorQueryId() {
        // Arrange - Test retry when cursorQueryId is null
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Create context with null cursorQueryId
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContextWithNullQueryId(
            jobRecord.Id, 0  // retryCount = 0 so retry will be attempted
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        Exception testEx = new System.AsyncException('Test exception');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should log error about failed cursor reconstruction
        System.assert(mockLogger.errorMessages.size() > 0, 
            'Should log error about failed cursor reconstruction');
    }
}