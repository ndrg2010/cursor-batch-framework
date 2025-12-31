/**
 * @description Unit tests for CursorBatchLogger default logging implementation.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchLoggerTest {
    
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
    static void testLogInfo() {
        // Arrange
        CursorBatchLogger logger = new CursorBatchLogger();
        String testMessage = 'Test info message';
        
        // Act - No exception should be thrown
        Test.startTest();
        logger.logInfo(testMessage);
        Test.stopTest();
        
        // Assert - We can't easily verify System.debug output, 
        // but we can verify no exception was thrown
        System.assert(true, 'logInfo should complete without exception');
    }
    
    @IsTest
    static void testLogError() {
        // Arrange
        CursorBatchLogger logger = new CursorBatchLogger();
        String testMessage = 'Test error message';
        
        // Act
        Test.startTest();
        logger.logError(testMessage);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'logError should complete without exception');
    }
    
    @IsTest
    static void testLogException() {
        // Arrange
        CursorBatchLogger logger = new CursorBatchLogger();
        String testMessage = 'Test exception context';
        Exception testException;
        
        try {
            Integer x = 1 / 0;
        } catch (Exception e) {
            testException = e;
        }
        
        // Act
        Test.startTest();
        logger.logException(testMessage, testException);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'logException should complete without exception');
    }
    
    @IsTest
    static void testLogExceptionWithNullMessage() {
        // Arrange
        CursorBatchLogger logger = new CursorBatchLogger();
        Exception testException = new System.MathException('Test');
        
        // Act
        Test.startTest();
        logger.logException(null, testException);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'logException should handle null message');
    }
    
    @IsTest
    static void testInterfaceImplementation() {
        // Arrange
        ICursorBatchLogger logger = CursorBatchLogger.getDefault();
        
        // Act & Assert - Verify interface methods are callable
        Test.startTest();
        logger.logInfo('Info via interface');
        logger.logError('Error via interface');
        logger.logException('Exception via interface', new System.MathException('Test'));
        Test.stopTest();
        
        System.assert(true, 'All interface methods should be callable');
    }
}

