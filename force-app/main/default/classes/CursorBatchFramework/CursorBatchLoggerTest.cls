/**
 * @description Unit tests for CursorBatchLogger default logging implementation.
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
        System.assertNotEquals(null, logger, 'Should return a logger instance');
        System.assert(logger instanceof CursorBatchLogger, 'Should return CursorBatchLogger instance');
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
        System.assert(true, 'All logging methods should complete without exception');
    }
}