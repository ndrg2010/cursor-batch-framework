/**
 * @description Mock implementation of ICursorBatchCacheService for testing.
 *              Stores cursors in memory instead of Platform Cache, allowing tests
 *              to run without Platform Cache availability.
 * @group CursorBatchFramework
 */
@IsTest
public class MockCursorBatchCacheService implements ICursorBatchCacheService {
    
    private Map<String, Database.Cursor> cursorCache = new Map<String, Database.Cursor>();
    
    // Track method calls for test assertions
    public List<String> cachedKeys = new List<String>();
    public List<String> retrievedKeys = new List<String>();
    public List<String> removedKeys = new List<String>();
    
    /**
     * @description Stores a cursor in the in-memory cache.
     * @param key Cache key
     * @param cursor Database cursor to cache
     */
    public void cacheCursor(String key, Database.Cursor cursor) {
        if (String.isBlank(key) || cursor == null) {
            throw new CursorBatchCoordinator.CursorBatchException('Cache key and cursor are required');
        }
        cursorCache.put(key, cursor);
        cachedKeys.add(key);
    }
    
    /**
     * @description Retrieves a cursor from the in-memory cache.
     * @param key Cache key to look up
     * @return Cached cursor or null if not found
     */
    public Database.Cursor getCursor(String key) {
        if (String.isBlank(key)) {
            return null;
        }
        retrievedKeys.add(key);
        return cursorCache.get(key);
    }
    
    /**
     * @description Generates a unique cache key.
     * @param jobName Job name to incorporate
     * @return Unique cache key
     */
    public String generateCacheKey(String jobName) {
        String sanitized = jobName.replaceAll('[^a-zA-Z0-9]', '');
        return 'MockCache' + sanitized + System.currentTimeMillis();
    }
    
    /**
     * @description Removes a cursor from the in-memory cache.
     * @param key Cache key to remove
     */
    public void removeCursor(String key) {
        if (String.isNotBlank(key)) {
            cursorCache.remove(key);
            removedKeys.add(key);
        }
    }
    
    /**
     * @description Clears all cached cursors. Useful for test isolation.
     */
    public void clearAll() {
        cursorCache.clear();
        cachedKeys.clear();
        retrievedKeys.clear();
        removedKeys.clear();
    }
    
    /**
     * @description Returns whether a key exists in the cache.
     * @param key Cache key to check
     * @return True if key exists
     */
    public Boolean containsKey(String key) {
        return cursorCache.containsKey(key);
    }
}

