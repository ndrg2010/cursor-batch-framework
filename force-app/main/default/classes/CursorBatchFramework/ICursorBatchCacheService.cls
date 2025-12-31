/**
 * @description Interface defining cursor caching operations for the cursor batch framework.
 *              Manages Database.Cursor instances in Platform Cache for cross-transaction access.
 * @group CursorBatchFramework
 */
public interface ICursorBatchCacheService {
    
    /**
     * @description Stores a Database.Cursor in Platform Cache with default TTL.
     * @param key Alphanumeric cache key
     * @param cursor Database cursor to cache
     */
    void cacheCursor(String key, Database.Cursor cursor);
    
    /**
     * @description Retrieves a Database.Cursor from Platform Cache.
     * @param key Cache key to look up
     * @return Cached cursor or null if not found/expired
     */
    Database.Cursor getCursor(String key);
    
    /**
     * @description Generates a unique alphanumeric cache key for a job execution.
     * @param jobName Job name to incorporate into the key
     * @return Unique cache key
     */
    String generateCacheKey(String jobName);
    
    /**
     * @description Removes a cached cursor to free Platform Cache capacity.
     * @param key Cache key to remove
     */
    void removeCursor(String key);
}