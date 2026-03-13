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
        Assert.areEqual(cursor, ctx.cursor, 'Cursor should be set');
        Assert.areEqual(startPosition, ctx.startPosition, 'Start position should be set');
        Assert.areEqual(endPosition, ctx.endPosition, 'End position should be set');
        Assert.areEqual(pageSize, ctx.pageSize, 'Page size should be set');
        Assert.areEqual(jobName, ctx.jobName, 'Job name should be set');
        Assert.areEqual(workerNum, ctx.workerNum, 'Worker number should be set');
        Assert.areEqual(jobRecordId, ctx.jobRecordId, 'Job record ID should be set');
        Assert.areEqual(workerClassName, ctx.workerClassName, 'Worker class name should be set');
        Assert.areEqual(0, ctx.retryCount, 'Retry count should default to 0');
        Assert.areEqual(null, ctx.cursorQueryId, 'Cursor query ID should default to null');
        Assert.areEqual(null, ctx.workerState, 'workerState should default to null');
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
        Assert.areEqual(cursorQueryId, ctx.cursorQueryId, 'Cursor query ID should be set');
        Assert.areEqual(retryCount, ctx.retryCount, 'Retry count should be set');
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
        Assert.areEqual(nextPosition, newCtx.startPosition, 'Start position should be updated');
        Assert.areEqual(originalCtx.endPosition, newCtx.endPosition, 'End position should remain same');
        Assert.areEqual(originalCtx.pageSize, newCtx.pageSize, 'Page size should remain same');
        Assert.areEqual(originalCtx.jobName, newCtx.jobName, 'Job name should remain same');
        Assert.areEqual(originalCtx.workerNum, newCtx.workerNum, 'Worker number should remain same');
        Assert.areEqual(originalCtx.cursor, newCtx.cursor, 'Cursor should remain same');
        Assert.areEqual(originalCtx.workerClassName, newCtx.workerClassName, 'Worker class name should remain same');
        Assert.areEqual(originalCtx.cursorQueryId, newCtx.cursorQueryId, 'Cursor query ID should remain same');
        Assert.areEqual(0, newCtx.retryCount, 'Retry count should be reset to 0 for next page');
    }
    
    @IsTest
    static void testWithNextPositionAndWorkerState() {
        // Arrange
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor, 0, 100, 20, 'TestJob', 1, null,
            'CursorBatchTestUtils.TestCursorBatchWorker',
            'TestQueryId', 2
        );
        Integer nextPosition = 20;
        String workerStateForNextPage = '{"recordsProcessed":15}';
        
        // Act
        Test.startTest();
        CursorBatchContext newCtx = originalCtx.withNextPosition(nextPosition, workerStateForNextPage);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(nextPosition, newCtx.startPosition, 'Start position should be updated');
        Assert.areEqual(0, newCtx.retryCount, 'Retry count should be reset to 0 for next page');
        Assert.areEqual(workerStateForNextPage, newCtx.workerState, 'workerState should be set for next page');
    }
    
    @IsTest
    static void testWithNextPositionPreservesWorkerState() {
        // Arrange - withNextPosition(Integer) uses copy(), which copies workerState
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor, 0, 100, 20, 'TestJob', 1, null,
            'CursorBatchTestUtils.TestCursorBatchWorker',
            'TestQueryId', 1
        );
        originalCtx.workerState = '{"accumulated":10}';
        Integer nextPosition = 20;
        
        // Act
        Test.startTest();
        CursorBatchContext newCtx = originalCtx.withNextPosition(nextPosition);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(nextPosition, newCtx.startPosition, 'Start position should be updated');
        Assert.areEqual('{"accumulated":10}', newCtx.workerState, 'workerState should be preserved via copy');
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
        Assert.areEqual(newRetryCount, newCtx.retryCount, 'Retry count should be updated');
        Assert.areEqual(originalCtx.startPosition, newCtx.startPosition, 'Start position should remain same');
        Assert.areEqual(originalCtx.endPosition, newCtx.endPosition, 'End position should remain same');
        Assert.areEqual(originalCtx.pageSize, newCtx.pageSize, 'Page size should remain same');
        Assert.areEqual(originalCtx.jobName, newCtx.jobName, 'Job name should remain same');
        Assert.areEqual(originalCtx.workerNum, newCtx.workerNum, 'Worker number should remain same');
        Assert.areEqual(originalCtx.cursor, newCtx.cursor, 'Cursor should remain same');
        Assert.areEqual(originalCtx.workerClassName, newCtx.workerClassName, 'Worker class name should remain same');
        Assert.areEqual(originalCtx.cursorQueryId, newCtx.cursorQueryId, 'Cursor query ID should remain same');
    }
    
    @IsTest
    static void testWithRetryPreservesWorkerState() {
        // Arrange - withRetry uses copy(), which copies workerState
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor, 10, 100, 20, 'TestJob', 1, null,
            'CursorBatchTestUtils.TestCursorBatchWorker',
            'TestQueryId', 0
        );
        originalCtx.workerState = '{"retryState":true}';
        Integer newRetryCount = 1;
        
        // Act
        Test.startTest();
        CursorBatchContext newCtx = originalCtx.withRetry(newRetryCount);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(newRetryCount, newCtx.retryCount, 'Retry count should be updated');
        Assert.areEqual('{"retryState":true}', newCtx.workerState, 'workerState should be preserved via copy');
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
        Assert.areEqual(cursor2, newCtx.cursor, 'Cursor should be updated');
        Assert.areEqual(originalCtx.startPosition, newCtx.startPosition, 'Start position should remain same');
        Assert.areEqual(originalCtx.endPosition, newCtx.endPosition, 'End position should remain same');
        Assert.areEqual(originalCtx.pageSize, newCtx.pageSize, 'Page size should remain same');
        Assert.areEqual(originalCtx.retryCount, newCtx.retryCount, 'Retry count should remain same');
        Assert.areEqual(originalCtx.cursorQueryId, newCtx.cursorQueryId, 'Cursor query ID should remain same');
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
        Assert.areEqual(cursor, ctx.cursor, 'Cursor should be set from parameter');
        Assert.areEqual(10, ctx.startPosition, 'Start position should be from event');
        Assert.areEqual(50, ctx.endPosition, 'End position should be from event');
        Assert.areEqual(20, ctx.pageSize, 'Page size should be from event');
        Assert.areEqual('TestJob', ctx.jobName, 'Job name should be from event');
        Assert.areEqual(3, ctx.workerNum, 'Worker number should be from event');
        Assert.areEqual(jobRecord.Id, ctx.jobRecordId, 'Job record ID should be from event');
        Assert.areEqual('CursorBatchTestUtils.TestCursorBatchWorker', ctx.workerClassName, 'Worker class should be from event');
        Assert.areEqual('TestQueryId', ctx.cursorQueryId, 'Cursor query ID should be from event');
        Assert.areEqual(1, ctx.retryCount, 'Retry count should be from event');
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
        Assert.areEqual(0, ctx.retryCount, 'Retry count should default to 0 when null');
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
        Assert.areEqual('TestCursorBatchCoordinator', coordClassName, 
            'Should return the simple coordinator class name (Apex String.valueOf limitation)');
        Assert.areEqual('TestCursorBatchWorker', workerClassName, 
            'Should return the simple worker class name (Apex String.valueOf limitation)');
    }
}