/**
 * @description Unit tests for CursorBatchLogger default logging implementation, scope helpers,
 *              and convention-based adapter resolution with tagging.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchLoggerTest {
    
    @IsTest
    static void testGetDefault() {
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorBatchLogger.getDefault();
        Test.stopTest();
        
        // Assert
        Assert.areNotEqual(null, logger, 'Should return a logger instance');
        Assert.isTrue(logger instanceof CursorBatchLogger, 'Should return CursorBatchLogger instance');
    }
    
    @IsTest
    static void testLoggingMethodsDoNotThrowExceptions() {
        // Arrange - Test all logging methods in one test
        CursorBatchLogger logger = new CursorBatchLogger();
        Exception testException;
        
        try {
            Integer x = 1 / 0;
        } catch (Exception e) {
            testException = e;
        }
        
        // Act - Verify all logging methods can be called without exceptions
        Test.startTest();
        logger.logInfo('Test info message');
        logger.logError('Test error message');
        logger.logException('Test exception context', testException);
        logger.logException(null, new System.MathException('Test'));
        Test.stopTest();
        
        // Assert - We can't easily verify System.debug output, 
        // but we can verify no exception was thrown
        Assert.isTrue(true, 'All logging methods should complete without exception');
    }
    
    @IsTest
    static void testScopedPrefixesMessage() {
        // Act
        Test.startTest();
        String scopedMessage = CursorBatchLogger.scoped(CursorBatchLogger.SCOPE_JOB_FAILED, 'Job: X');
        String unscopedMessage = CursorBatchLogger.scoped(null, 'Job: X');
        Test.stopTest();
        
        // Assert
        Assert.areEqual('[JOB FAILED] Job: X', scopedMessage, 'Should prefix the scope token');
        Assert.areEqual('Job: X', unscopedMessage, 'Blank scope should leave the message unchanged');
    }
    
    @IsTest
    static void testFailureCodeTagParsesLeadingCode() {
        // Act
        Test.startTest();
        String tag = CursorBatchLogger.failureCodeTag('[QUERY_TIMEOUT] Your query request was running for too long.');
        Test.stopTest();
        
        // Assert
        Assert.areEqual('CursorBatch Failure QUERY_TIMEOUT', tag,
            'Should derive the tag from the leading platform error code');
    }
    
    @IsTest
    static void testFailureCodeTagParsesFromComposedErrorMessage() {
        // Arrange - the shape produced by formatExceptionMessage when ExtendedStatus is recovered
        String composed = 'System.UnexpectedException: connection was cancelled here\n' +
            'Class.SomeWorker.process: line 48, column 1\n\n' +
            'Platform status: [UNABLE_TO_LOCK_ROW] unable to obtain exclusive access to this record';
        
        // Act
        Test.startTest();
        String tag = CursorBatchLogger.failureCodeTag(composed);
        Test.stopTest();
        
        // Assert
        Assert.areEqual('CursorBatch Failure UNABLE_TO_LOCK_ROW', tag,
            'Should find the code on the Platform status line');
    }
    
    @IsTest
    static void testFailureCodeTagReturnsNullWithoutCode() {
        // Act
        Test.startTest();
        String noCode = CursorBatchLogger.failureCodeTag('connection was cancelled here');
        String blank = CursorBatchLogger.failureCodeTag('');
        String nullInput = CursorBatchLogger.failureCodeTag(null);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(null, noCode, 'Text with no bracketed code should yield no tag');
        Assert.areEqual(null, blank, 'Blank text should yield no tag');
        Assert.areEqual(null, nullInput, 'Null text should yield no tag');
    }
    
    @IsTest
    static void testFormatExceptionMessageAppendsPlatformStatus() {
        // Arrange
        Exception ex = new System.MathException('boom');
        
        // Act
        Test.startTest();
        String enriched = CursorBatchLogger.formatExceptionMessage(ex, '[QUERY_TIMEOUT] too long');
        String plain = CursorBatchLogger.formatExceptionMessage(ex, null);
        Test.stopTest();
        
        // Assert
        Assert.isTrue(enriched.contains('Platform status: [QUERY_TIMEOUT] too long'),
            'Should append the recovered platform status');
        Assert.isTrue(enriched.contains('boom'), 'Should retain the original exception message');
        Assert.isFalse(plain.contains('Platform status:'),
            'A blank platform status must leave the message unchanged');
    }
    
    @IsTest
    static void testResolveLoggerAppliesJobTagToCallableAdapter() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorBatchLogger.resolveLogger('Billing Engine');
        logger.logError('something broke');
        Test.stopTest();
        
        // Assert
        Assert.areEqual(new Set<String>{ 'Billing Engine' }, CursorBatchTestUtils.lastCapturedTags(),
            'Adapter should receive the job tag');
    }
    
    @IsTest
    static void testResolveLoggerAppliesJobAndScopeTags() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorBatchLogger.resolveLogger(
            'Billing Engine',
            new Set<String>{ CursorBatchLogger.TAG_WORKER_FAILURE, 'CursorBatch Failure QUERY_TIMEOUT' }
        );
        logger.logError('something broke');
        Test.stopTest();
        
        // Assert
        Assert.areEqual(
            new Set<String>{ 'Billing Engine', CursorBatchLogger.TAG_WORKER_FAILURE, 'CursorBatch Failure QUERY_TIMEOUT' },
            CursorBatchTestUtils.lastCapturedTags(),
            'Adapter should receive the job tag alongside every scope tag'
        );
    }
    
    @IsTest
    static void testResolveLoggerWithBlankTagAppliesNoTags() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorBatchLogger.resolveLogger(null);
        logger.logInfo('no tag');
        Test.stopTest();
        
        // Assert
        Assert.areEqual(0, CursorBatchTestUtils.lastCapturedTags().size(),
            'A blank tag with no scope tags should leave the entry untagged');
    }
    
    @IsTest
    static void testWithScopeTagsReturnsFreshInstanceSoTagsDoNotLeak() {
        // Arrange
        CursorBatchTestUtils.useCallableLoggerAdapter();
        ICursorBatchLogger base = CursorBatchLogger.resolveLogger('Billing Engine');
        
        // Act - a worker failure followed by a differently scoped job failure
        Test.startTest();
        CursorBatchLogger.withScopeTags(base, 'Billing Engine',
            new Set<String>{ CursorBatchLogger.TAG_WORKER_FAILURE }).logError('worker');
        Set<String> workerTags = CursorBatchTestUtils.lastCapturedTags();
        
        CursorBatchLogger.withScopeTags(base, 'Billing Engine',
            new Set<String>{ CursorBatchLogger.TAG_JOB_FAILURE }).logError('job');
        Set<String> jobTags = CursorBatchTestUtils.lastCapturedTags();
        Test.stopTest();
        
        // Assert
        Assert.areEqual(new Set<String>{ 'Billing Engine', CursorBatchLogger.TAG_WORKER_FAILURE }, workerTags,
            'Worker failure should carry only its own scope tag');
        Assert.areEqual(new Set<String>{ 'Billing Engine', CursorBatchLogger.TAG_JOB_FAILURE }, jobTags,
            'Job failure must not inherit the worker scope tag from the earlier emission');
    }
    
    @IsTest
    static void testWithScopeTagsPassesThroughNonCallableLogger() {
        // Arrange - a mock logger cannot be tagged, so callers must keep the instance they supplied
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger =
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        ICursorBatchLogger resolved = CursorBatchLogger.withScopeTags(
            mockLogger, 'Billing Engine', new Set<String>{ CursorBatchLogger.TAG_JOB_FAILURE }
        );
        Test.stopTest();
        
        // Assert
        Assert.isTrue(resolved == mockLogger, 'Non-taggable loggers should be returned unchanged');
    }
}
