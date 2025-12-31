/**
 * @description Unit tests for CursorBatchCacheServiceImpl Platform Cache operations.
 *              Tests gracefully skip when Platform Cache is not available (e.g., in scratch orgs).
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchCacheServiceImplTest {
    
    /**
     * @description Checks if Platform Cache is available in the current org.
     * @return True if Platform Cache can be used, false otherwise
     */
    private static Boolean isPlatformCacheAvailable() {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition('local.CursorBatch');
            // Try to put a simple value to verify capacity
            partition.put('CacheTest', 'test', 60);
            partition.remove('CacheTest');
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(10);
    }
    
    @IsTest
    static void testNewInstance() {
        // Act
        Test.startTest();
        ICursorBatchCacheService service = new CursorBatchCacheServiceImpl();
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, service, 'Should return a service instance');
        System.assert(service instanceof CursorBatchCacheServiceImpl, 
            'Should return CursorBatchCacheServiceImpl instance');
    }
    
    @IsTest
    static void testGenerateCacheKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        String jobName = 'Test-Job_123';
        
        // Act
        Test.startTest();
        String cacheKey = service.generateCacheKey(jobName);
        Test.stopTest();
        
        // Assert
        System.assert(cacheKey.startsWith('CursorBatch'), 'Key should start with CursorBatch');
        System.assert(cacheKey.contains('TestJob123'), 'Key should contain sanitized job name');
        System.assert(!cacheKey.contains('-'), 'Key should not contain special characters');
        System.assert(!cacheKey.contains('_'), 'Key should not contain underscores');
    }
    
    @IsTest
    static void testCacheCursorAndGetCursor() {
        // Skip if Platform Cache not available
        if (!isPlatformCacheAvailable()) {
            System.debug('Skipping test: Platform Cache not available');
            return;
        }
        
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        Database.Cursor cursor = Database.getCursor('SELECT Id, Name FROM Account ORDER BY Name');
        String cacheKey = 'TestCacheKey' + System.currentTimeMillis();
        
        // Act
        Test.startTest();
        service.cacheCursor(cacheKey, cursor);
        Database.Cursor retrievedCursor = service.getCursor(cacheKey);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, retrievedCursor, 'Should retrieve cached cursor');
        System.assertEquals(cursor.getNumRecords(), retrievedCursor.getNumRecords(), 
            'Retrieved cursor should have same record count');
    }
    
    @IsTest
    static void testCacheCursorWithNullKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        
        // Act & Assert
        Test.startTest();
        try {
            service.cacheCursor(null, cursor);
            System.assert(false, 'Should throw exception for null key');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('required'), 
                'Exception should mention required parameters');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testCacheCursorWithBlankKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        
        // Act & Assert
        Test.startTest();
        try {
            service.cacheCursor('', cursor);
            System.assert(false, 'Should throw exception for blank key');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('required'), 
                'Exception should mention required parameters');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testCacheCursorWithNullCursor() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        
        // Act & Assert
        Test.startTest();
        try {
            service.cacheCursor('ValidKey', null);
            System.assert(false, 'Should throw exception for null cursor');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('required'), 
                'Exception should mention required parameters');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetCursorWithNullKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        
        // Act
        Test.startTest();
        Database.Cursor result = service.getCursor(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(null, result, 'Should return null for null key');
    }
    
    @IsTest
    static void testGetCursorWithBlankKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        
        // Act
        Test.startTest();
        Database.Cursor result = service.getCursor('');
        Test.stopTest();
        
        // Assert
        System.assertEquals(null, result, 'Should return null for blank key');
    }
    
    @IsTest
    static void testGetCursorNotFound() {
        // Skip if Platform Cache not available
        if (!isPlatformCacheAvailable()) {
            System.debug('Skipping test: Platform Cache not available');
            return;
        }
        
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        
        // Act
        Test.startTest();
        Database.Cursor result = service.getCursor('NonExistentKey12345');
        Test.stopTest();
        
        // Assert
        System.assertEquals(null, result, 'Should return null for non-existent key');
    }
    
    @IsTest
    static void testInterfaceImplementation() {
        // Skip if Platform Cache not available
        if (!isPlatformCacheAvailable()) {
            System.debug('Skipping test: Platform Cache not available');
            return;
        }
        
        // Arrange
        ICursorBatchCacheService service = new CursorBatchCacheServiceImpl();
        Database.Cursor cursor = Database.getCursor('SELECT Id FROM Account');
        String key = service.generateCacheKey('InterfaceTest');
        
        // Act
        Test.startTest();
        service.cacheCursor(key, cursor);
        Database.Cursor retrieved = service.getCursor(key);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, retrieved, 'Interface methods should work correctly');
    }
    
    @IsTest
    static void testCacheNotAvailableError() {
        // This test verifies the error message constant exists and is properly formatted
        String errorMessage = CursorBatchCacheServiceImpl.CACHE_NOT_AVAILABLE_ERROR;
        
        System.assert(errorMessage.contains('Platform Cache'), 
            'Error message should mention Platform Cache');
        System.assert(errorMessage.contains('Enterprise Edition'), 
            'Error message should mention edition requirements');
        System.assert(errorMessage.contains('CursorBatch'), 
            'Error message should mention the partition name');
    }
    
    @IsTest
    static void testRemoveCursorWithNullKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        
        // Act - Should not throw exception
        Test.startTest();
        service.removeCursor(null);
        Test.stopTest();
        
        // Assert - No exception means success
        System.assert(true, 'Should handle null key gracefully');
    }
    
    @IsTest
    static void testRemoveCursorWithBlankKey() {
        // Arrange
        CursorBatchCacheServiceImpl service = new CursorBatchCacheServiceImpl();
        
        // Act - Should not throw exception
        Test.startTest();
        service.removeCursor('');
        Test.stopTest();
        
        // Assert - No exception means success
        System.assert(true, 'Should handle blank key gracefully');
    }
}
