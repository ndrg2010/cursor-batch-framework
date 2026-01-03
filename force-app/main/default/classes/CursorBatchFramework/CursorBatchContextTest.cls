/**
 * @description Unit tests for CursorBatchContext value object.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchContextTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(10);
    }
    
    @IsTest
    static void testConstructor() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        Integer startPosition = 0;
        Integer endPosition = 100;
        Integer pageSize = 20;
        String jobName = 'TestJob';
        Integer workerNum = 1;
        Id jobRecordId = null;
        String workerClassName = 'CursorBatchTestUtils.TestCursorBatchWorker';
        
        // Act
        Test.startTest();
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, startPosition, endPosition, pageSize, jobName, workerNum, jobRecordId, workerClassName, null, 0
        );
        Test.stopTest();
        
        // Assert
        System.assertEquals(cursor, ctx.cursor, 'Cursor should be set');
        System.assertEquals(startPosition, ctx.startPosition, 'Start position should be set');
        System.assertEquals(endPosition, ctx.endPosition, 'End position should be set');
        System.assertEquals(pageSize, ctx.pageSize, 'Page size should be set');
        System.assertEquals(jobName, ctx.jobName, 'Job name should be set');
        System.assertEquals(workerNum, ctx.workerNum, 'Worker number should be set');
        System.assertEquals(jobRecordId, ctx.jobRecordId, 'Job record ID should be set');
        System.assertEquals(workerClassName, ctx.workerClassName, 'Worker class name should be set');
        System.assertEquals(0, ctx.retryCount, 'Retry count should default to 0');
        System.assertEquals(null, ctx.cursorQueryId, 'Cursor query ID should default to null');
    }
    
    @IsTest
    static void testConstructorWithRetryParams() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        String cursorQueryId = 'TestQueryId123';
        Integer retryCount = 2;
        
        // Act
        Test.startTest();
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 100, 20, 'TestJob', 1, null, 
            'CursorBatchTestUtils.TestCursorBatchWorker',
            cursorQueryId, retryCount
        );
        Test.stopTest();
        
        // Assert
        System.assertEquals(cursorQueryId, ctx.cursorQueryId, 'Cursor query ID should be set');
        System.assertEquals(retryCount, ctx.retryCount, 'Retry count should be set');
    }
    
    @IsTest
    static void testWithNextPosition() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor, 0, 100, 20, 'TestJob', 1, null, 
            'CursorBatchTestUtils.TestCursorBatchWorker',
            'TestQueryId', 2
        );
        Integer nextPosition = 20;
        
        // Act
        Test.startTest();
        CursorBatchContext newCtx = originalCtx.withNextPosition(nextPosition);
        Test.stopTest();
        
        // Assert
        System.assertEquals(nextPosition, newCtx.startPosition, 'Start position should be updated');
        System.assertEquals(originalCtx.endPosition, newCtx.endPosition, 'End position should remain same');
        System.assertEquals(originalCtx.pageSize, newCtx.pageSize, 'Page size should remain same');
        System.assertEquals(originalCtx.jobName, newCtx.jobName, 'Job name should remain same');
        System.assertEquals(originalCtx.workerNum, newCtx.workerNum, 'Worker number should remain same');
        System.assertEquals(originalCtx.cursor, newCtx.cursor, 'Cursor should remain same');
        System.assertEquals(originalCtx.workerClassName, newCtx.workerClassName, 'Worker class name should remain same');
        System.assertEquals(originalCtx.cursorQueryId, newCtx.cursorQueryId, 'Cursor query ID should remain same');
        System.assertEquals(0, newCtx.retryCount, 'Retry count should be reset to 0 for next page');
    }
    
    @IsTest
    static void testWithRetry() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor, 10, 100, 20, 'TestJob', 1, null, 
            'CursorBatchTestUtils.TestCursorBatchWorker',
            'TestQueryId', 0
        );
        Integer newRetryCount = 2;
        
        // Act
        Test.startTest();
        CursorBatchContext newCtx = originalCtx.withRetry(newRetryCount);
        Test.stopTest();
        
        // Assert
        System.assertEquals(newRetryCount, newCtx.retryCount, 'Retry count should be updated');
        System.assertEquals(originalCtx.startPosition, newCtx.startPosition, 'Start position should remain same');
        System.assertEquals(originalCtx.endPosition, newCtx.endPosition, 'End position should remain same');
        System.assertEquals(originalCtx.pageSize, newCtx.pageSize, 'Page size should remain same');
        System.assertEquals(originalCtx.jobName, newCtx.jobName, 'Job name should remain same');
        System.assertEquals(originalCtx.workerNum, newCtx.workerNum, 'Worker number should remain same');
        System.assertEquals(originalCtx.cursor, newCtx.cursor, 'Cursor should remain same');
        System.assertEquals(originalCtx.workerClassName, newCtx.workerClassName, 'Worker class name should remain same');
        System.assertEquals(originalCtx.cursorQueryId, newCtx.cursorQueryId, 'Cursor query ID should remain same');
    }
    
    @IsTest
    static void testWithCursor() {
        // Arrange
        Database.Cursor cursor1 = CursorBatchTestUtils.createTestCursor();
        Database.Cursor cursor2 = CursorBatchTestUtils.createTestCursor();
        
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor1, 10, 100, 20, 'TestJob', 1, null, 
            'CursorBatchTestUtils.TestCursorBatchWorker',
            'TestQueryId', 1
        );
        
        // Act
        Test.startTest();
        CursorBatchContext newCtx = originalCtx.withCursor(cursor2);
        Test.stopTest();
        
        // Assert
        System.assertEquals(cursor2, newCtx.cursor, 'Cursor should be updated');
        System.assertEquals(originalCtx.startPosition, newCtx.startPosition, 'Start position should remain same');
        System.assertEquals(originalCtx.endPosition, newCtx.endPosition, 'End position should remain same');
        System.assertEquals(originalCtx.pageSize, newCtx.pageSize, 'Page size should remain same');
        System.assertEquals(originalCtx.retryCount, newCtx.retryCount, 'Retry count should remain same');
        System.assertEquals(originalCtx.cursorQueryId, newCtx.cursorQueryId, 'Cursor query ID should remain same');
    }
    
    @IsTest
    static void testFromEvent() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        
        CursorBatch_Worker__e evt = new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cursor_Query_Id__c = 'TestQueryId',
            Start_Position__c = 10,
            End_Position__c = 50,
            Page_Size__c = 20,
            Worker_Number__c = 3,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker',
            Retry_Count__c = 1
        );
        
        // Act
        Test.startTest();
        CursorBatchContext ctx = CursorBatchContext.fromEvent(evt, cursor);
        Test.stopTest();
        
        // Assert
        System.assertEquals(cursor, ctx.cursor, 'Cursor should be set from parameter');
        System.assertEquals(10, ctx.startPosition, 'Start position should be from event');
        System.assertEquals(50, ctx.endPosition, 'End position should be from event');
        System.assertEquals(20, ctx.pageSize, 'Page size should be from event');
        System.assertEquals('TestJob', ctx.jobName, 'Job name should be from event');
        System.assertEquals(3, ctx.workerNum, 'Worker number should be from event');
        System.assertEquals(jobRecord.Id, ctx.jobRecordId, 'Job record ID should be from event');
        System.assertEquals('CursorBatchTestUtils.TestCursorBatchWorker', ctx.workerClassName, 'Worker class should be from event');
        System.assertEquals('TestQueryId', ctx.cursorQueryId, 'Cursor query ID should be from event');
        System.assertEquals(1, ctx.retryCount, 'Retry count should be from event');
    }
    
    @IsTest
    static void testFromEventWithNullRetryCount() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        
        CursorBatch_Worker__e evt = new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cursor_Query_Id__c = 'TestQueryId',
            Start_Position__c = 10,
            End_Position__c = 50,
            Page_Size__c = 20,
            Worker_Number__c = 3,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker',
            Retry_Count__c = null
        );
        
        // Act
        Test.startTest();
        CursorBatchContext ctx = CursorBatchContext.fromEvent(evt, cursor);
        Test.stopTest();
        
        // Assert
        System.assertEquals(0, ctx.retryCount, 'Retry count should default to 0 when null');
    }
    
    @IsTest
    static void testGetClassName() {
        // Arrange - Note: String.valueOf() in Apex returns only simple class name, not fully qualified
        // For top-level classes, this works fine. For inner classes, it only returns the inner class name.
        // In production, coordinators should be top-level classes, so this limitation is acceptable.
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        
        // Act - Test with both coordinator and worker
        Test.startTest();
        String coordClassName = CursorBatchContext.getClassName(coordinator);
        String workerClassName = CursorBatchContext.getClassName(worker);
        Test.stopTest();
        
        // Assert - String.valueOf() returns simple class name (Apex limitation)
        // The $ to . conversion is for cases where String.valueOf() might include $ (rare)
        System.assertEquals('TestCursorBatchCoordinator', coordClassName, 
            'Should return the simple coordinator class name (Apex String.valueOf limitation)');
        System.assertEquals('TestCursorBatchWorker', workerClassName, 
            'Should return the simple worker class name (Apex String.valueOf limitation)');
    }
}