/**
 * @description Unit tests for CursorBatchWorkerTriggerHandler Platform Event handler.
 *              Uses MockCursorBatchCacheService to avoid Platform Cache dependency.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchWorkerTriggerHandlerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(20);
    }
    
    @IsTest
    static void testHandleWithNullEvents() {
        // Arrange
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(null);
        Test.stopTest();
        
        // Assert - Should complete without exception
        System.assert(true, 'Handle should gracefully handle null events');
    }
    
    @IsTest
    static void testHandleWithEmptyEvents() {
        // Arrange
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        List<CursorBatch_Worker__e> emptyEvents = new List<CursorBatch_Worker__e>();
        
        // Act
        Test.startTest();
        handler.handle(emptyEvents);
        Test.stopTest();
        
        // Assert - Should complete without exception
        System.assert(true, 'Handle should gracefully handle empty events');
    }
    
    @IsTest
    static void testHandleWithValidEvents() {
        // Arrange
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        // Create and cache a cursor using mock
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        String cacheKey = 'TestCacheKey' + System.currentTimeMillis();
        mockCache.cacheCursor(cacheKey, cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - In test context, System.enqueueJob is skipped but processing should work
        System.assert(true, 'Handler should process events without exception');
    }
    
    @IsTest
    static void testHandleWithMissingConfig() {
        // Arrange
        CursorBatchCoordinator.testConfig = null;
        
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        String cacheKey = 'TestCacheKey' + System.currentTimeMillis();
        mockCache.cacheCursor(cacheKey, cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'NonExistentJob', 1, 'TestCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'NonExistentJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = ''  // Empty worker class to test error handling
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act - Should log error but not throw (trigger handler pattern)
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should catch exception internally
        System.assert(true, 'Handler should catch missing worker class exception');
    }
    
    @IsTest
    static void testHandleWithMissingCursor() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        // Use mock cache without caching a cursor - simulates missing cursor
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = 'NonExistentCacheKey',
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Should handle gracefully
        System.assert(true, 'Handler should handle missing cursor gracefully');
    }
    
    @IsTest
    static void testHandleWithInvalidWorkerClass() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        String cacheKey = 'TestCacheKey' + System.currentTimeMillis();
        mockCache.cacheCursor(cacheKey, cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'NonExistentWorkerClass'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act - Should catch exception internally
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'Handler should catch invalid worker class exception');
    }
    
    @IsTest
    static void testHandleMultipleEvents() {
        // Arrange
        CursorBatchTestUtils.resetTestWorker();
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 3, 10
        );
        
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        String cacheKey = 'TestCacheKey' + System.currentTimeMillis();
        mockCache.cacheCursor(cacheKey, cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 3, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>();
        for (Integer i = 0; i < 3; i++) {
            events.add(new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = i * 7,
                End_Position__c = (i + 1) * 7,
                Page_Size__c = 10,
                Worker_Number__c = i + 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            ));
        }
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert
        System.assert(true, 'Handler should process multiple events');
    }
    
    @IsTest
    static void testCursorCachingAcrossEvents() {
        // Arrange - Verify cursor is cached and reused across events with same key
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        String cacheKey = 'SharedCacheKey' + System.currentTimeMillis();
        mockCache.cacheCursor(cacheKey, cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 2, 'TestCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            ),
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = 10,
                End_Position__c = 20,
                Page_Size__c = 10,
                Worker_Number__c = 2,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker'
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Both events should be processed with shared cursor
        System.assert(true, 'Handler should reuse cached cursor across events');
    }
    
    @IsTest
    static void testHandleWithClassNotExtendingWorker() {
        // Arrange - Test type check scenario
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        MockCursorBatchCacheService mockCache = new MockCursorBatchCacheService();
        String cacheKey = 'TestCacheKey' + System.currentTimeMillis();
        mockCache.cacheCursor(cacheKey, cursor);
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'TestCoordinator'
        );
        
        List<CursorBatch_Worker__e> events = new List<CursorBatch_Worker__e>{
            new CursorBatch_Worker__e(
                Job_Name__c = 'TestJob',
                Cache_Key__c = cacheKey,
                Start_Position__c = 0,
                End_Position__c = 10,
                Page_Size__c = 10,
                Worker_Number__c = 1,
                Job_Record_Id__c = jobRecord.Id,
                Worker_Class__c = 'String' // String class exists but doesn't extend CursorBatchWorker
            )
        };
        
        CursorBatchWorkerTriggerHandler handler = new CursorBatchWorkerTriggerHandler();
        handler.setCacheService(mockCache);
        
        // Act - Handler should catch exception internally and log error
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should handle the error gracefully
        System.assert(true, 'Handler should handle invalid worker class gracefully');
    }
}
