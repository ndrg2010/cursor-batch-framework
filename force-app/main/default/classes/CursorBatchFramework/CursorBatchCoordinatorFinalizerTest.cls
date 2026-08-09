/**
 * @description Unit tests for CursorBatchCoordinatorFinalizer.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCoordinatorFinalizerTest {
    
    private static final String TEST_QUERY = 'SELECT Id FROM Account';
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(10);
    }
    
    @IsTest
    static void testConstructor() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        ICursorBatchLogger logger = CursorBatchLogger.getDefault();
        
        // Act
        Test.startTest();
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            logger,
            null
        );
        Test.stopTest();
        
        // Assert
        Assert.areNotEqual(null, finalizer, 'Finalizer should be instantiated');
    }
    
    @IsTest
    static void testExecuteInternalWithSuccess() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            null
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(true, null);
        Test.stopTest();
        
        // Assert - No errors should be logged, job unchanged
        Assert.areEqual(0, mockLogger.errorMessages.size(), 
            'Should not log errors for successful execution');
        
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Preparing', updatedJob.Status__c, 
            'Status should remain unchanged on success');
        Assert.areEqual(0, updatedJob.Total_Cursor_Retries__c, 
            'Retry count should remain 0 on success');
    }
    
    @IsTest
    static void testExecuteInternalWithFailure_RetryAvailable() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20, 3
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            null
        );
        
        Exception testEx = new System.QueryException('Cursor query timeout');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should increment retry count and re-enqueue
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(1, updatedJob.Total_Cursor_Retries__c, 
            'Retry count should be incremented to 1');
        Assert.areEqual('Preparing', updatedJob.Status__c, 
            'Status should remain Preparing for retry');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Retry 1'), 
            'Error message should indicate retry attempt');
        
        // Verify warn log was emitted
        Assert.isTrue(mockLogger.hasInfoContaining('WARN') && mockLogger.hasInfoContaining('Cursor query failed'), 
            'Should log warning about cursor query failure');
    }
    
    @IsTest
    static void testExecuteInternalWithFailure_MaxRetriesExhausted() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20, 2
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 2  // Already at max
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            TEST_QUERY
        );
        
        Exception testEx = new System.QueryException('Cursor query timeout');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should mark as Failed
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c, 
            'Status should be Failed when max retries exhausted');
        Assert.areEqual(2, updatedJob.Total_Cursor_Retries__c, 
            'Retry count should not be incremented past max');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Max retries exhausted'), 
            'Error message should indicate max retries exhausted');
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 
            'Completed_At should be set');
        
        // Verify finish() callback was invoked
        Assert.isTrue(mockLogger.hasInfoContaining('Invoked finish() callback'), 
            'Should log that finish() callback was invoked');
    }
    
    @IsTest
    static void testExecuteInternalWithFailure_NullException() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20, 3
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            null
        );
        
        // Act - Pass null exception
        Test.startTest();
        finalizer.executeInternal(false, null);
        Test.stopTest();
        
        // Assert - Should handle null exception gracefully
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(1, updatedJob.Total_Cursor_Retries__c, 
            'Retry count should be incremented even with null exception');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Unknown error'), 
            'Error message should indicate unknown error');
    }
    
    @IsTest
    static void testExecuteInternalWithMissingJobRecord() {
        // Arrange
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Use a fake job ID that doesn't exist
        String fakeJobId = CursorBatch_Job__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            Id.valueOf(fakeJobId), 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            TEST_QUERY
        );
        
        Exception testEx = new System.QueryException('Cursor query timeout');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should log error about missing job record
        Assert.isTrue(mockLogger.hasErrorContaining('Could not find job record'), 
            'Should log error about missing job record');
    }
    
    @IsTest
    static void testExecuteInternalWithInvalidCoordinatorClass() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20, 3
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'InvalidClassName', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'NonExistentCoordinatorClass',
            mockLogger,
            TEST_QUERY
        );
        
        Exception testEx = new System.QueryException('Cursor query timeout');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should mark as Failed when coordinator class not found
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c, 
            'Status should be Failed when coordinator class not found');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Could not find coordinator class'), 
            'Error message should mention coordinator class not found');
    }
    
    @IsTest
    static void testExecuteWithMockFinalizerContext_Success() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            TEST_QUERY
        );
        
        CursorBatchTestUtils.MockFinalizerContext successCtx = 
            new CursorBatchTestUtils.MockFinalizerContext(System.ParentJobResult.SUCCESS);
        
        // Act
        Test.startTest();
        finalizer.execute(successCtx);
        Test.stopTest();
        
        // Assert - No changes on success
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Preparing', updatedJob.Status__c, 
            'Status should remain Preparing on success');
    }
    
    @IsTest
    static void testExecuteWithMockFinalizerContext_Failure() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20, 3
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            TEST_QUERY
        );
        
        CursorBatchTestUtils.MockFinalizerContext failureCtx = 
            new CursorBatchTestUtils.MockFinalizerContext(System.ParentJobResult.UNHANDLED_EXCEPTION);
        
        // Act
        Test.startTest();
        finalizer.execute(failureCtx);
        Test.stopTest();
        
        // Assert - Should retry
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(1, updatedJob.Total_Cursor_Retries__c, 
            'Retry count should be incremented on failure');
    }
    
    @IsTest
    static void testDefaultMaxRetriesUsedWhenConfigMissing() {
        // Arrange
        CursorBatchCoordinator.testConfig = null;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'UnknownJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 2  // Below default max of 3
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'UnknownJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger,
            TEST_QUERY
        );
        
        Exception testEx = new System.QueryException('Cursor query timeout');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, testEx);
        Test.stopTest();
        
        // Assert - Should retry (default max is 3, current is 2)
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual(3, updatedJob.Total_Cursor_Retries__c, 
            'Retry count should be incremented using default max retries');
        Assert.areEqual('Preparing', updatedJob.Status__c, 
            'Status should remain Preparing (not Failed yet)');
    }
    
    // ============================================
    // Terminal Logging and Platform Status Tests
    // ============================================
    
    @IsTest
    static void testMaxRetriesExhaustedLogsExactlyOneError() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 2);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 2  // Already at max
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger, TEST_QUERY
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.QueryException('Cursor query timeout'));
        Test.stopTest();
        
        // Assert - the terminal entry is the single error; the attempt itself is reported at info
        Assert.areEqual(1, mockLogger.errorMessages.size(),
            'A failed job should produce one error entry, got: ' + mockLogger.errorMessages);
        Assert.isTrue(mockLogger.errorMessages[0].startsWith('[' + CursorBatchLogger.SCOPE_JOB_FAILED + ']'),
            'The single error should be the scoped terminal entry: ' + mockLogger.errorMessages[0]);
    }
    
    @IsTest
    static void testMaxRetriesExhaustedAppendsPlatformStatus() {
        // Arrange - cursor creation timing out is this finalizer's known failure mode
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 2);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 2
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger, TEST_QUERY
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('connection was cancelled here'),
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c, 'Status should be Failed');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Platform status: [QUERY_TIMEOUT]'),
            'The job record should carry the recovered platform status, got: ' + updatedJob.Error_Message__c);
        Assert.isTrue(mockLogger.hasErrorContaining('[QUERY_TIMEOUT]'),
            'The terminal entry should surface the underlying platform error');
    }
    
    @IsTest
    static void testRetryablePathStillReportsTheAttempt() {
        // Arrange - retryable failures must not be silent now that the up-front error was removed
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 3);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator',
            mockLogger, TEST_QUERY
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('connection was cancelled here'),
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert
        Assert.isTrue(mockLogger.hasInfoContaining('Cursor query failed'),
            'The retry attempt should still be reported');
        Assert.isTrue(mockLogger.hasInfoContaining('[QUERY_TIMEOUT]'),
            'The retry report should include the recovered platform status');
        Assert.areEqual(0, mockLogger.errorMessages.size(),
            'A retryable attempt is not a job failure, got: ' + mockLogger.errorMessages);
    }
}