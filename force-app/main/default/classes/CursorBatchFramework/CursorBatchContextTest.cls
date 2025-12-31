/**
 * @description Unit tests for CursorBatchContext value object.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchContextTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(10);
    }
    
    @IsTest
    static void testConstructor() {
        // Arrange
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
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
            cursor, startPosition, endPosition, pageSize, jobName, workerNum, jobRecordId, workerClassName
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
    }
    
    @IsTest
    static void testWithNextPosition() {
        // Arrange
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        CursorBatchContext originalCtx = new CursorBatchContext(
            cursor, 0, 100, 20, 'TestJob', 1, null, 'CursorBatchTestUtils.TestCursorBatchWorker'
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
    }
    
    @IsTest
    static void testFromEvent() {
        // Arrange
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        
        CursorBatch_Worker__e evt = new CursorBatch_Worker__e(
            Job_Name__c = 'TestJob',
            Cache_Key__c = 'TestCacheKey',
            Start_Position__c = 10,
            End_Position__c = 50,
            Page_Size__c = 20,
            Worker_Number__c = 3,
            Job_Record_Id__c = jobRecord.Id,
            Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
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
    }
    
    @IsTest
    static void testGetClassName() {
        // Arrange - Note: String.valueOf() in Apex returns only simple class name, not fully qualified
        // For top-level classes, this works fine. For inner classes, it only returns the inner class name.
        // In production, coordinators should be top-level classes, so this limitation is acceptable.
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        
        // Act
        Test.startTest();
        String className = CursorBatchContext.getClassName(coordinator);
        Test.stopTest();
        
        // Assert - String.valueOf() returns simple class name (Apex limitation)
        // The $ to . conversion is for cases where String.valueOf() might include $ (rare)
        System.assertEquals('TestCursorBatchCoordinator', className, 
            'Should return the simple class name (Apex String.valueOf limitation)');
    }
    
    @IsTest
    static void testGetClassNameWithWorker() {
        // Arrange - Note: String.valueOf() in Apex returns only simple class name
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        
        // Act
        Test.startTest();
        String className = CursorBatchContext.getClassName(worker);
        Test.stopTest();
        
        // Assert - String.valueOf() returns simple class name (Apex limitation)
        System.assertEquals('TestCursorBatchWorker', className, 
            'Should return the simple worker class name (Apex String.valueOf limitation)');
    }
}

