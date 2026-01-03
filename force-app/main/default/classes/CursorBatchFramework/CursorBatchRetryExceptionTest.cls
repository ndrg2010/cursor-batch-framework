/**
 * @description Unit tests for CursorBatchRetryException.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchRetryExceptionTest {
    
    @IsTest
    static void testConstructorWithMessageOnly() {
        // Arrange
        String testMessage = 'Callout timeout, please retry';
        
        // Act
        Test.startTest();
        CursorBatchRetryException ex = new CursorBatchRetryException(testMessage);
        Test.stopTest();
        
        // Assert
        System.assertEquals(testMessage, ex.getMessage(), 'Message should be set');
        System.assertEquals(null, ex.suggestedDelayMinutes, 'Suggested delay should be null');
    }
    
    @IsTest
    static void testCreateWithMessageAndDelay() {
        // Arrange
        String testMessage = 'Rate limited, retry after delay';
        Integer delayMinutes = 5;
        
        // Act
        Test.startTest();
        CursorBatchRetryException ex = CursorBatchRetryException.create(testMessage, delayMinutes);
        Test.stopTest();
        
        // Assert
        System.assertEquals(testMessage, ex.getMessage(), 'Message should be set');
        System.assertEquals(delayMinutes, ex.suggestedDelayMinutes, 'Suggested delay should be set');
    }
    
    @IsTest
    static void testCreateWithZeroDelay() {
        // Arrange
        String testMessage = 'Immediate retry requested';
        Integer delayMinutes = 0;
        
        // Act
        Test.startTest();
        CursorBatchRetryException ex = CursorBatchRetryException.create(testMessage, delayMinutes);
        Test.stopTest();
        
        // Assert
        System.assertEquals(0, ex.suggestedDelayMinutes, 'Zero delay should be accepted');
    }
    
    @IsTest
    static void testCreateWithNullDelay() {
        // Arrange
        String testMessage = 'Default backoff requested';
        
        // Act
        Test.startTest();
        CursorBatchRetryException ex = CursorBatchRetryException.create(testMessage, null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(null, ex.suggestedDelayMinutes, 'Null delay should be accepted');
    }
    
    @IsTest
    static void testThrowAndCatch() {
        // Arrange
        String testMessage = 'Test retry exception';
        Integer delayMinutes = 3;
        
        // Act & Assert
        Test.startTest();
        try {
            throw CursorBatchRetryException.create(testMessage, delayMinutes);
        } catch (CursorBatchRetryException ex) {
            System.assertEquals(testMessage, ex.getMessage(), 'Caught exception should have message');
            System.assertEquals(delayMinutes, ex.suggestedDelayMinutes, 'Caught exception should have delay');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testIsInstanceOfException() {
        // Arrange
        Exception ex = new CursorBatchRetryException('Test');
        
        // Act & Assert - Use a variable typed as Exception to verify polymorphism
        System.assertNotEquals(null, ex, 'Should be instance of Exception');
        System.assert(ex.getMessage() == 'Test', 'Should have correct message');
    }
}