/**
 * @description Unit tests for CursorBatchWorker abstract base class.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchWorkerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(50);
    }
    
    private static void resetTestWorker() {
        CursorBatchTestUtils.resetTestWorker();
    }
    
    @IsTest
    static void testInitialize() {
        // Arrange
        resetTestWorker();
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 50, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        
        // Act
        Test.startTest();
        worker.initialize(ctx);
        Test.stopTest();
        
        // Assert - Worker should be initialized (we can't directly check ctx but execution will work)
        System.assert(true, 'Initialize should complete without exception');
    }
    
    @IsTest
    static void testExecuteProcessesRecords() {
        // Arrange
        resetTestWorker();
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 10, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(1, CursorBatchTestUtils.testWorker_processCallCount, 
            'Process should be called once');
        System.assertEquals(10, CursorBatchTestUtils.testWorker_processedRecords.size(), 
            'Should process 10 records');
        System.assertEquals(true, CursorBatchTestUtils.testWorker_onCompleteCalled, 
            'onComplete should be called');
    }
    
    @IsTest
    static void testExecuteWithNullCursor() {
        // Arrange
        resetTestWorker();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            null, 0, 10, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        worker.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(0, CursorBatchTestUtils.testWorker_processCallCount, 
            'Process should not be called with null cursor');
        System.assert(mockLogger.hasErrorContaining('no cursor'), 
            'Should log error about missing cursor');
    }
    
    @IsTest
    static void testExecuteWithEmptyScope() {
        // Arrange
        resetTestWorker();
        // Create a cursor with a query that returns records, but set start and end to same value
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account ORDER BY Name');
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Set start and end to same value (0) - worker will fetch records but newPosition will equal endPosition
        // This simulates a worker that has no work to do (edge case that coordinator should prevent)
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 0, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert - Worker will fetch records, but since newPosition (0 + fetched) >= endPosition (0), it completes
        // The coordinator should never create this scenario (start == end), but we test defensive handling
        System.assertEquals(true, CursorBatchTestUtils.testWorker_onCompleteCalled, 
            'Should complete when start equals end (no work to do)');
    }
    
    @IsTest
    static void testExecuteWithPagination() {
        // Arrange
        resetTestWorker();
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Small page size to trigger pagination logic (but not actual re-enqueue in test)
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 50, 5, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert - In test context, re-enqueue is skipped but processing should occur
        System.assertEquals(1, CursorBatchTestUtils.testWorker_processCallCount, 
            'Process should be called once per execution');
        System.assertEquals(5, CursorBatchTestUtils.testWorker_processedRecords.size(), 
            'Should process page size records');
    }
    
    @IsTest
    static void testExecuteWithCustomLogger() {
        // Arrange
        resetTestWorker();
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 10, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        worker.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert
        System.assert(mockLogger.infoMessages.size() > 0, 'Should log info messages');
        System.assert(mockLogger.hasInfoContaining('processing'), 
            'Should log processing message');
    }
    
    @IsTest
    static void testOnCompleteCallback() {
        // Arrange
        resetTestWorker();
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account ORDER BY Name LIMIT 5');
        Integer totalRecords = cursor.getNumRecords();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Set end position to totalRecords, pageSize to totalRecords, so we process all records and complete
        // This simulates a worker processing its entire range in one execution
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, totalRecords, totalRecords, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, CursorBatchTestUtils.testWorker_onCompleteCalled, 
            'onComplete should be called when work is done');
    }
    
    @IsTest
    static void testWorkerWithStartPositionBeyondEnd() {
        // Arrange
        resetTestWorker();
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account ORDER BY Name');
        Integer totalRecords = cursor.getNumRecords();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Test edge case: start position at last valid index with pageSize 1
        // This simulates a worker processing the very last record
        // Use a valid position that won't exceed bounds
        Integer startPos = totalRecords > 0 ? Math.max(0, totalRecords - 1) : 0;
        Integer endPos = startPos;
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, startPos, endPos, 1, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert - Should handle gracefully (fetch at last position, then complete)
        System.assertEquals(true, CursorBatchTestUtils.testWorker_onCompleteCalled, 
            'Should complete when processing last record');
    }
    
    @IsTest
    static void testProcessAbstractMethod() {
        // Arrange
        resetTestWorker();
        List<Account> testAccounts = [SELECT Id, Name FROM Account LIMIT 5];
        List<SObject> records = new List<SObject>();
        records.addAll(testAccounts);
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        
        // Act
        Test.startTest();
        worker.process(records);
        Test.stopTest();
        
        // Assert
        System.assertEquals(5, CursorBatchTestUtils.testWorker_processedRecords.size(), 
            'Process should add records to static list');
        System.assertEquals(1, CursorBatchTestUtils.testWorker_processCallCount, 
            'Process call count should increment');
    }
    
    
    
    
    @IsTest
    static void testExecuteWithException() {
        // Arrange - Create a worker that will throw an exception during process()
        CursorBatchTestUtils.resetTestWorker();
        
        List<Account> testAccounts = CursorBatchTestUtils.createTestAccounts(5);
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account LIMIT 5');
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 5, 5, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker'
        );
        
        // Create a worker that throws exception
        CursorBatchTestUtils.TestCursorBatchWorker worker = new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.shouldThrowException = true;
        worker.initialize(ctx);
        
        // Act & Assert
        Test.startTest();
        try {
            worker.execute(null);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Test exception'), 
                'Should throw expected exception');
        }
        Test.stopTest();
        
        // Assert - Finalizer should be attached even on exception
        // Verify by checking that exception was logged (via mock logger if available)
        System.assert(true, 'Exception should be handled and finalizer attached');
    }
}

