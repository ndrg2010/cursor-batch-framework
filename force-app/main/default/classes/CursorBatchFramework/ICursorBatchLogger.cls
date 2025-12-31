/**
 * @description Logging interface for the CursorBatchFramework. Implement to integrate with
 *              Nebula Logger, Pharos, custom objects, or other logging frameworks.
 * @group CursorBatchFramework
 */
public interface ICursorBatchLogger {
    
    /**
     * @description Logs an informational message.
     * @param message Message to log
     */
    void logInfo(String message);
    
    /**
     * @description Logs an error message.
     * @param message Error message to log
     */
    void logError(String message);
    
    /**
     * @description Logs an exception with context.
     * @param message Context describing where the exception occurred
     * @param e Exception to log
     */
    void logException(String message, Exception e);
}
