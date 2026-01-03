/**
 * @description Default logging implementation for CursorBatchFramework using System.debug.
 *              Implement ICursorBatchLogger to integrate with Nebula Logger, Pharos, or
 *              other logging frameworks.
 * @group CursorBatchFramework
 * @see ICursorBatchLogger
 */
public without sharing class CursorBatchLogger implements ICursorBatchLogger {
    
    private static final String LOG_PREFIX = '[CursorBatch] ';
    
    /**
     * @description Returns a new default logger instance using System.debug.
     * @return ICursorBatchLogger instance
     */
    public static ICursorBatchLogger getDefault() {
        return new CursorBatchLogger();
    }
    
    /**
     * @description Logs an informational message at INFO level.
     * @param message Message to log
     */
    public void logInfo(String message) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + message);
    }
    
    /**
     * @description Logs an error message at ERROR level.
     * @param message Error message to log
     */
    public void logError(String message) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + message);
    }
    
    /**
     * @description Logs an exception with context message and stack trace at ERROR level.
     * @param message Context describing where the exception occurred
     * @param e Exception to log
     */
    public void logException(String message, Exception e) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + message + ': ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    }
    
    /**
     * @description Formats an exception into a single error message string with stack trace.
     * @param e Exception to format, or null
     * @return Formatted error message with stack trace, or 'Unknown error' if null
     */
    public static String formatExceptionMessage(Exception e) {
        return e != null ? e.getMessage() + '\n' + e.getStackTraceString() : 'Unknown error';
    }
}