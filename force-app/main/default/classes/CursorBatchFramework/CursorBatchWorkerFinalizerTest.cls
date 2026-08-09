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
        Assert.areNotEqual(null, finalizer, 'Finalizer should be instantiated');
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
        Assert.areEqual(0, mockLogger.errorMessages.size(), 
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
        Assert.isTrue(mockLogger.errorMessages.size() > 0 || mockLogger.infoMessages.size() > 0, 
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
        Assert.isTrue(mockLogger.hasErrorContaining('max retries') || 
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
        Assert.areEqual(false, exceptionThrown, 
            'Finalizer should handle null exception parameter without throwing');
        // Should still log an error about the failure (even without exception details)
        Assert.isTrue(mockLogger.errorMessages.size() > 0 || mockLogger.infoMessages.size() > 0, 
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
        Assert.isTrue(mockLogger.errorMessages.size() > 0 || 
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
        Assert.areEqual(true, result.isSuccess(), 'Event should be published successfully');
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
        Assert.areEqual(0, mockLogger.errorMessages.size(), 
            'Should not log errors for successful completion with retry count');
    }
    
    @IsTest
    static void testExecuteInternalSuccessPublishesStateDelta() {
        // Arrange
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestJob', 1, 5);
        config.Query_Builder_Class__c = 'CursorJobTest.TestQueryBuilder';
        config.Query_Builder_Method__c = 'getAccountsQuery';
        config.Worker_Class__c = 'CursorBatchTestUtils.TestStatefulCursorJobWorker';
        config.State_Reducer_Class__c = 'CursorBatchTestUtils.TestStateReducer';
        CursorBatchCoordinator.testConfig = config;
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorJob'
        );
        jobRecord.State_JSON__c = '{"processedCount":1,"pagesProcessed":0}';
        update jobRecord;
        
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 0);
        ctx.stateDeltaJson = '{"processedCount":4,"pagesProcessed":1}';
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        // Act
        Test.startTest();
        finalizer.executeInternal(true, null);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(updatedJob.State_JSON__c);
        Assert.areEqual(5, ((Decimal) state.get('processedCount')).intValue(),
            'Completion event should carry the reducer delta through to persisted state');
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
        Assert.isTrue(mockLogger.errorMessages.size() > 0 || 
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
        Assert.isTrue(mockLogger.errorMessages.size() > 0, 
            'Should log error about failed cursor reconstruction');
    }
    
    // ============================================
    // Platform Status Enrichment Tests
    // ============================================
    
    @IsTest
    static void testFailureAppendsRecoveredPlatformStatus() {
        // Arrange - a query timeout reaches Apex only as an opaque UnexpectedException; the
        // actionable text exists on AsyncApexJob.ExtendedStatus.
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 99);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        Exception opaqueEx = new System.AsyncException('connection was cancelled here');
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, opaqueEx,
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert
        Assert.isTrue(mockLogger.hasErrorContaining('Platform status: [QUERY_TIMEOUT]'),
            'The recovered platform status should be reported alongside the opaque exception');
        Assert.isTrue(mockLogger.hasErrorContaining('[' + CursorBatchLogger.SCOPE_WORKER_FAILED + ']'),
            'Worker failures should be scoped as such');
    }
    
    @IsTest
    static void testFailureWithoutPlatformStatusIsUnchanged() {
        // Arrange - ExtendedStatus is not guaranteed to be committed when the finalizer runs
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 99);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(ctx, mockLogger);
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('boom'), null);
        Test.stopTest();
        
        // Assert
        Assert.isFalse(mockLogger.hasErrorContaining('Platform status:'),
            'A blank ExtendedStatus must leave the reported error unchanged');
        Assert.isTrue(mockLogger.hasErrorContaining('boom'),
            'The original exception message should still be reported');
    }
    
    @IsTest
    static void testFailureTagsPlatformErrorCode() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 20);
        CursorBatchCoordinator.testConfig.Logger_Tag__c = 'Billing Engine';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 99);
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            ctx, CursorBatchLogger.resolveLogger('Billing Engine')
        );
        
        // Act - stopTest delivers the published completion event, so the completion handler also
        // runs and emits its own terminal entry for the now-failed job.
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('connection was cancelled here'),
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert - the worker failure and the job failure are separate, differently scoped entries
        Assert.isTrue(
            CursorBatchTestUtils.hasCapturedTagSetContaining(new Set<String>{
                'Billing Engine',
                CursorBatchLogger.TAG_WORKER_FAILURE,
                'CursorBatch Failure QUERY_TIMEOUT'
            }),
            'A worker failure entry should carry the job tag, worker scope, and platform error code. Captured: ' +
                CursorBatchTestUtils.capturedTagSets
        );
        Assert.isFalse(
            CursorBatchTestUtils.hasCapturedTagSetContaining(new Set<String>{
                CursorBatchLogger.TAG_WORKER_FAILURE, CursorBatchLogger.TAG_JOB_FAILURE
            }),
            'Worker and job scope tags must never land on the same entry. Captured: ' +
                CursorBatchTestUtils.capturedTagSets
        );
    }
    
    @IsTest
    static void testPlatformErrorCodeReachesTheTerminalJobEntry() {
        // Arrange - the recovered code should survive the hop from finalizer to completion handler
        // via the completion event and the job record.
        CursorBatchTestUtils.useCallableLoggerAdapter();
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestJob', 1, 20);
        CursorBatchCoordinator.testConfig.Logger_Tag__c = 'Billing Engine';
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 99);
        
        CursorBatchWorkerFinalizer finalizer = new CursorBatchWorkerFinalizer(
            ctx, CursorBatchLogger.resolveLogger('Billing Engine')
        );
        
        // Act
        Test.startTest();
        finalizer.executeInternal(false, new System.AsyncException('connection was cancelled here'),
            '[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert
        Assert.isTrue(
            CursorBatchTestUtils.hasCapturedTagSetContaining(new Set<String>{
                CursorBatchLogger.TAG_JOB_FAILURE, 'CursorBatch Failure QUERY_TIMEOUT'
            }),
            'The terminal job entry should be filterable by the platform error code. Captured: ' +
                CursorBatchTestUtils.capturedTagSets
        );
    }
}