/**
 * @description Unit tests for CursorBatchCoordinatorFinalizer.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCoordinatorFinalizerTest {
    
    private static final String TEST_QUERY = 'SELECT Id FROM Account';
    
    /**
     * Coordinator with a public no-arg constructor. The finalizer's retry path re-instantiates
     * the coordinator via Type.newInstance(), which throws for TestCursorBatchCoordinator (no
     * no-arg constructor) and is now terminal. Tests that expect a retry to be scheduled use this.
     */
    private static final String RETRYABLE_COORDINATOR = 'CursorBatchTestUtils.RetryableTestCoordinator';
    
    /** Coordinator without a no-arg constructor; used to prove that shape is terminal, not stranding. */
    private static final String NO_ARG_LESS_COORDINATOR = 'CursorBatchTestUtils.TestCursorBatchCoordinator';
    
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
            'TestJob', RETRYABLE_COORDINATOR, 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            RETRYABLE_COORDINATOR,
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
        
        // Verify warn log was emitted and the retry path reached the enqueue
        Assert.isTrue(mockLogger.hasInfoContaining('WARN') && mockLogger.hasInfoContaining('Cursor query failed'), 
            'Should log warning about cursor query failure');
        Assert.isTrue(mockLogger.hasInfoContaining('Re-enqueued coordinator for retry 1'),
            'The coordinator should have been instantiated and re-enqueued, got: ' + mockLogger.infoMessages);
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
            'TestJob', RETRYABLE_COORDINATOR, 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            RETRYABLE_COORDINATOR,
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
            'TestJob', RETRYABLE_COORDINATOR, 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'TestJob', 
            RETRYABLE_COORDINATOR,
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
            'UnknownJob', RETRYABLE_COORDINATOR, 2  // Below default max of 3
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 
            'UnknownJob', 
            RETRYABLE_COORDINATOR,
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
            'TestJob', RETRYABLE_COORDINATOR, 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', RETRYABLE_COORDINATOR,
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
    
    // ============================================
    // Platform Re-enqueue Limit Tests
    //
    // Salesforce lets a finalizer re-enqueue a failed Queueable at most 5 consecutive times.
    // A job configured above that (prod had 20) used to strand in Preparing: the 6th enqueue
    // threw, the catch logged at INFO, and nothing ever ran again for the job.
    // ============================================
    
    @IsTest
    static void testConfiguredMaxAbovePlatformLimitIsClamped() {
        // Arrange - configured for 20 retries, job has already used 5
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 20);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', RETRYABLE_COORDINATOR, CursorBatchCoordinatorFinalizer.PLATFORM_FINALIZER_RETRY_LIMIT
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', RETRYABLE_COORDINATOR, mockLogger, TEST_QUERY
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('connection was cancelled here'),
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert - the platform limit, not the configured 20, decides when the job is terminal
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c,
            'Retry count at the platform limit must mark the job Failed instead of attempting a 6th enqueue');
        Assert.areEqual(CursorBatchCoordinatorFinalizer.PLATFORM_FINALIZER_RETRY_LIMIT, updatedJob.Total_Cursor_Retries__c,
            'Retry count should not be incremented past the platform limit');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Max retries exhausted'),
            'Error message should indicate max retries exhausted, got: ' + updatedJob.Error_Message__c);
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 'Completed_At should be set');
        Assert.isTrue(mockLogger.hasInfoContaining('exceeds the platform finalizer re-enqueue limit'),
            'The clamp should be reported so the misconfiguration is visible, got: ' + mockLogger.infoMessages);
        Assert.areEqual(1, CursorBatchTestUtils.retryableCoordinatorFinishCount,
            'finish() should be invoked exactly once for the failed job');
        Assert.areEqual(1, mockLogger.errorMessages.size(),
            'A failed job should produce one error entry, got: ' + mockLogger.errorMessages);
    }
    
    @IsTest
    static void testConfiguredMaxAbovePlatformLimitStillRetriesBelowLimit() {
        // Arrange - configured for 20, job has used 4: one more retry is allowed
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 20);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', RETRYABLE_COORDINATOR, CursorBatchCoordinatorFinalizer.PLATFORM_FINALIZER_RETRY_LIMIT - 1
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', RETRYABLE_COORDINATOR, mockLogger, TEST_QUERY
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.QueryException('Cursor query timeout'));
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Preparing', updatedJob.Status__c, 'Below the platform limit the job should still retry');
        Assert.areEqual(CursorBatchCoordinatorFinalizer.PLATFORM_FINALIZER_RETRY_LIMIT, updatedJob.Total_Cursor_Retries__c,
            'Retry count should advance to the platform limit');
        Assert.isTrue(mockLogger.hasInfoContaining('Scheduling retry 5 of 5'),
            'The retry report should show the clamped maximum, got: ' + mockLogger.infoMessages);
        Assert.areEqual(0, mockLogger.errorMessages.size(),
            'A retryable attempt is not a job failure, got: ' + mockLogger.errorMessages);
    }
    
    @IsTest
    static void testEnqueueFailureMarksJobFailed() {
        // Arrange - retries remain per config, but the platform refuses the enqueue
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 3);
        
        CursorBatch_Job_Parent__c parent = new CursorBatch_Job_Parent__c(
            Config_Developer_Name__c = 'EnqueueFailureJob',
            Config_Label__c = 'EnqueueFailureJob',
            Last_Job_Started_At__c = System.now(),
            Last_Job_Status__c = 'Preparing'
        );
        insert parent;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', RETRYABLE_COORDINATOR, 0
        );
        jobRecord.Job_Parent__c = parent.Id;
        update jobRecord;
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', RETRYABLE_COORDINATOR, mockLogger, TEST_QUERY
        );
        CursorBatchCoordinatorFinalizer.simulateEnqueueFailure = true;
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('connection was cancelled here'),
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert - nothing else will ever run for this job, so it must be terminal
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c,
            'A retry that cannot be enqueued must mark the job Failed, not leave it Preparing');
        Assert.areEqual(1, updatedJob.Total_Cursor_Retries__c,
            'The retry count persisted before the enqueue should be kept so the record shows the attempt');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Could not re-enqueue coordinator for retry 1 of 3'),
            'Error message should explain the enqueue failure, got: ' + updatedJob.Error_Message__c);
        Assert.isTrue(updatedJob.Error_Message__c.contains('Maximum stack depth has been reached'),
            'Error message should carry the platform exception, got: ' + updatedJob.Error_Message__c);
        Assert.isTrue(updatedJob.Error_Message__c.contains('[QUERY_TIMEOUT]'),
            'Error message should keep the original coordinator failure, got: ' + updatedJob.Error_Message__c);
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 'Completed_At should be set');
        
        CursorBatch_Job_Parent__c updatedParent = [
            SELECT Last_Job_Status__c FROM CursorBatch_Job_Parent__c WHERE Id = :parent.Id
        ];
        Assert.areEqual('Failed', updatedParent.Last_Job_Status__c,
            'The terminal status should be mirrored onto the parent');
        
        Assert.areEqual(1, CursorBatchTestUtils.retryableCoordinatorFinishCount,
            'finish() should be invoked exactly once for the failed job');
        Assert.areEqual('Failed', CursorBatchTestUtils.retryableCoordinatorFinishedJob?.Status__c,
            'finish() should see the Failed job record');
        Assert.areEqual(1, mockLogger.errorMessages.size(),
            'A failed job should produce one error entry, got: ' + mockLogger.errorMessages);
        Assert.isTrue(mockLogger.errorMessages[0].startsWith('[' + CursorBatchLogger.SCOPE_JOB_FAILED + ']'),
            'The single error should be the scoped terminal entry: ' + mockLogger.errorMessages[0]);
    }
    
    @IsTest
    static void testCoordinatorWithoutNoArgConstructorMarksJobFailed() {
        // Arrange - README requires a no-arg constructor for retries; Type.newInstance() throws
        // without one. That used to be swallowed and the job stranded in Preparing.
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 5, 20, 3);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', NO_ARG_LESS_COORDINATOR, 0
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchCoordinatorFinalizer finalizer = new CursorBatchCoordinatorFinalizer(
            jobRecord.Id, 'TestJob', NO_ARG_LESS_COORDINATOR, mockLogger, TEST_QUERY
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.QueryException('Cursor query timeout'));
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Assert.areEqual('Failed', updatedJob.Status__c,
            'A coordinator that cannot be re-instantiated must mark the job Failed');
        Assert.areEqual(1, updatedJob.Total_Cursor_Retries__c,
            'The retry count persisted before instantiation should be kept');
        Assert.isTrue(updatedJob.Error_Message__c.contains('Could not re-enqueue coordinator for retry 1 of 3'),
            'Error message should explain why the retry could not run, got: ' + updatedJob.Error_Message__c);
        Assert.areNotEqual(null, updatedJob.Completed_At__c, 'Completed_At should be set');
        Assert.isFalse(mockLogger.hasInfoContaining('Re-enqueued coordinator'),
            'No retry should be reported as enqueued, got: ' + mockLogger.infoMessages);
    }
}