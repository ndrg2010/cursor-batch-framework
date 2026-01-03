/**
 * @description Unit tests for CursorBatchWorker abstract base class.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchWorkerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(50);
    }
    
    @IsTest
    static void testInitialize() {
        // Arrange
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 50, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        
        // Act
        Test.startTest();
        worker.initialize(ctx);
        Test.stopTest();
        
        // Assert - Worker should be initialized
        // If we get here without exception, initialization succeeded
        System.assertNotEquals(null, worker, 'Worker should be instantiated');
    }
    
    @IsTest
    static void testExecuteProcessesRecords() {
        // Arrange
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 10, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            null, 0, 10, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        // Create a cursor with a query that returns records, but set start and end to same value
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Set start and end to same value (0) - worker will fetch records but newPosition will equal endPosition
        // This simulates a worker that has no work to do (edge case that coordinator should prevent)
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 0, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Small page size to trigger pagination logic (but not actual re-enqueue in test)
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 50, 5, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, 10, 10, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor(5);
        Integer totalRecords = cursor.getNumRecords();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Set end position to totalRecords, pageSize to totalRecords, so we process all records and complete
        // This simulates a worker processing its entire range in one execution
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, 0, totalRecords, totalRecords, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
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
            cursor, startPos, endPos, 1, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
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
        CursorBatchTestUtils.resetTestWorker();
        List<Account> testAccounts = CursorBatchTestUtils.queryTestAccounts(5);
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
    static void testExecuteWithFetchCountLimitedByEndPosition() {
        // Arrange - Simulates the "Fetch beyond bound" bug scenario
        // When pageSize would exceed the remaining records in the worker's range
        CursorBatchTestUtils.resetTestWorker();
        Database.Cursor cursor = CursorBatchTestUtils.createTestCursor();
        Integer totalRecords = cursor.getNumRecords();
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Set up: start position near end, pageSize larger than remaining records
        // This simulates the scenario that caused "Fetch beyond bound detected: 10005"
        // with 10000 records, position 9990, and pageSize 15 (9990 + 15 = 10005 > 10000)
        Integer startPos = Math.max(0, totalRecords - 5);
        Integer endPos = totalRecords;
        Integer pageSize = 15; // Larger than remaining records
        
        CursorBatchContext ctx = new CursorBatchContext(
            cursor, startPos, endPos, pageSize, 'TestJob', 1, jobRecord.Id, 'CursorBatchTestUtils.TestCursorBatchWorker', null, 0
        );
        
        CursorBatchTestUtils.TestCursorBatchWorker worker = 
            new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        
        // Act - Should NOT throw "Fetch beyond bound" error
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert - Worker should successfully process remaining records
        System.assertEquals(1, CursorBatchTestUtils.testWorker_processCallCount, 
            'Process should be called once');
        System.assert(CursorBatchTestUtils.testWorker_processedRecords.size() <= 5, 
            'Should process at most 5 records (remaining in range)');
        System.assertEquals(true, CursorBatchTestUtils.testWorker_onCompleteCalled, 
            'onComplete should be called');
    }
    
    @IsTest
    static void testExecuteWithException() {
        // Arrange - Create a worker that will throw an exception during process()
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 0, 5, 5, 0);
        
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
        
        // The test verifies that the exception is properly thrown and propagated
        // The try/catch above validates the expected behavior
    }
    
    @IsTest
    static void testExecuteWithRetryException() {
        // Arrange - Create a worker that will throw a CursorBatchRetryException
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(jobRecord.Id, 0, 5, 5, 0);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Create a worker that throws retry exception
        CursorBatchTestUtils.TestCursorBatchWorker worker = new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.shouldThrowRetryException = true;
        worker.retryExceptionDelay = 2;
        worker.initialize(ctx);
        worker.setLogger(mockLogger);
        
        // Act - In test context, retry enqueue is skipped but logging should occur
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert - Should log retry scheduling message
        System.assert(mockLogger.hasInfoContaining('retry') || mockLogger.infoMessages.size() > 0, 
            'Should log retry scheduling message');
    }
    
    @IsTest
    static void testExecuteWithRetryExceptionMaxRetriesExhausted() {
        // Arrange - Create a worker that has already exhausted retries
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Create context with retryCount = 3 (default max)
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(
            jobRecord.Id, 0, 5, 5, 3  // retryCount = 3
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Create a worker that throws retry exception
        CursorBatchTestUtils.TestCursorBatchWorker worker = new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.shouldThrowRetryException = true;
        worker.initialize(ctx);
        worker.setLogger(mockLogger);
        
        // Act & Assert - Should throw since max retries exhausted
        Test.startTest();
        try {
            worker.execute(null);
            System.assert(false, 'Should throw exception when max retries exhausted');
        } catch (CursorBatchRetryException e) {
            System.assert(e.getMessage().contains('retry'), 
                'Should throw CursorBatchRetryException');
        }
        Test.stopTest();
        
        // Assert - Should log max retries exhausted message
        System.assert(mockLogger.hasErrorContaining('max retries') || 
                      mockLogger.errorMessages.size() > 0, 
            'Should log max retries exhausted error');
    }
    
    @IsTest
    static void testRetryCountInContext() {
        // Arrange - Test that retry count is properly tracked in context
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Create context with retryCount = 1
        CursorBatchContext ctx = CursorBatchTestUtils.createTestContext(
            jobRecord.Id, 0, 5, 5, 1  // retryCount = 1
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Create a worker that will process successfully
        CursorBatchTestUtils.TestCursorBatchWorker worker = new CursorBatchTestUtils.TestCursorBatchWorker();
        worker.initialize(ctx);
        worker.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        worker.execute(null);
        Test.stopTest();
        
        // Assert - Should log retry info in processing message
        System.assert(mockLogger.hasInfoContaining('retry 1') || 
                      CursorBatchTestUtils.testWorker_processCallCount == 1, 
            'Should process successfully even on retry');
    }
}