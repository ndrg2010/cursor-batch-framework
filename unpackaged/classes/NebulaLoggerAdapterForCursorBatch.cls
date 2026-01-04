/**
 * @description Adapter that bridges ICursorBatchLogger to NebulaLoggerAdapter for 
 *              CursorBatchFramework integration. Enables Nebula Logger persistence 
 *              for all cursor batch operations.
 * @group CursorBatchFramework
 * @see ICursorBatchLogger
 * @see NebulaLoggerAdapter
 */
public inherited sharing class NebulaLoggerAdapterForCursorBatch implements ICursorBatchLogger {
    
    private static final String LOG_PREFIX = '[CursorBatch] ';
    
    private ILogger nebulaLogger;
    
    /**
     * @description Default constructor. Uses Application.Service to resolve ILogger.
     */
    public NebulaLoggerAdapterForCursorBatch() {
        this.nebulaLogger = (ILogger) Application.Service.newInstance(ILogger.class);
    }
    
    /**
     * @description Constructor with explicit logger injection for testing.
     * @param logger ILogger implementation to use
     */
    @TestVisible
    private NebulaLoggerAdapterForCursorBatch(ILogger logger) {
        this.nebulaLogger = logger;
    }
    
    /**
     * @description Returns a new instance using Nebula Logger.
     * @return ICursorBatchLogger instance wrapping Nebula Logger
     */
    public static ICursorBatchLogger getInstance() {
        return new NebulaLoggerAdapterForCursorBatch();
    }
    
    /**
     * @description Logs an informational message via Nebula Logger and saves immediately.
     * @param message Message to log
     */
    public void logInfo(String message) {
        nebulaLogger.info(LOG_PREFIX + message);
        nebulaLogger.save();
    }
    
    /**
     * @description Logs an error message via Nebula Logger and saves immediately.
     * @param message Error message to log
     */
    public void logError(String message) {
        nebulaLogger.error(LOG_PREFIX + message);
        nebulaLogger.save();
    }
    
    /**
     * @description Logs an exception with context via Nebula Logger and saves immediately.
     * @param message Context describing where the exception occurred
     * @param e Exception to log
     */
    public void logException(String message, Exception e) {
        nebulaLogger.exception(LOG_PREFIX + message, e);
        nebulaLogger.save();
    }
}
