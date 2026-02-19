/**
 * @description Adapter that bridges ICursorBatchLogger to your logging framework for 
 *              CursorBatchFramework integration. This class is automatically discovered
 *              by CursorJob when it exists in the org.
 * 
 *              Rename this class from NebulaLoggerAdapterForCursorBatch to 
 *              CursorBatchLoggerAdapter to enable convention-based logger discovery.
 * 
 * Usage:
 *      The CursorJob class automatically looks for a class named 'CursorBatchLoggerAdapter'
 *      that implements ICursorBatchLogger. If found, it uses this adapter for logging.
 *      If not found, it falls back to CursorBatchLogger (System.debug).
 * 
 * @group CursorBatchFramework
 * @see ICursorBatchLogger
 * @see CursorJob
 */
public inherited sharing class CursorBatchLoggerAdapter implements ICursorBatchLogger, Callable {
    
    private static final String LOG_PREFIX = '[CursorBatch] ';
    
    private Set<String> tags;
    
    // TODO: Replace with your logging framework interface
    // For Nebula Logger: private ILogger nebulaLogger;
    // For LoggerService: private ILoggerService loggerService;
    
    /**
     * @description Default constructor. Initialize your logging framework here.
     */
    public CursorBatchLoggerAdapter() {
        this.tags = new Set<String>();
        // TODO: Initialize your logger
        // this.nebulaLogger = (ILogger) Application.Service.newInstance(ILogger.class);
    }
    
    /**
     * @description Adds a tag to be applied to all subsequent log entries.
     *              Can be chained: adapter.addTag('Tag1').addTag('Tag2')
     * @param tag Tag to add
     * @return This adapter instance for method chaining
     */
    public CursorBatchLoggerAdapter addTag(String tag) {
        if (String.isNotBlank(tag)) {
            this.tags.add(tag);
        }
        return this;
    }
    
    /**
     * @description Adds multiple tags to be applied to all subsequent log entries.
     * @param tagsToAdd Set of tags to add
     * @return This adapter instance for method chaining
     */
    public CursorBatchLoggerAdapter addTags(Set<String> tagsToAdd) {
        if (tagsToAdd != null) {
            this.tags.addAll(tagsToAdd);
        }
        return this;
    }
    
    /**
     * @description Logs an informational message and saves immediately.
     *              Applies configured tags to the log entry.
     * @param message Message to log
     */
    public void logInfo(String message) {
        // TODO: Replace with your logging framework
        // Example for Nebula Logger:
        // ILogEntryBuilder entry = nebulaLogger.info(LOG_PREFIX + message);
        // applyTags(entry);
        // nebulaLogger.save();
        
        // Fallback to System.debug
        System.debug(LoggingLevel.INFO, LOG_PREFIX + formatWithTags(message));
    }
    
    /**
     * @description Logs an error message and saves immediately.
     *              Applies configured tags to the log entry.
     * @param message Error message to log
     */
    public void logError(String message) {
        // TODO: Replace with your logging framework
        // Example for Nebula Logger:
        // ILogEntryBuilder entry = nebulaLogger.error(LOG_PREFIX + message);
        // applyTags(entry);
        // nebulaLogger.save();
        
        // Fallback to System.debug
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + formatWithTags(message));
    }
    
    /**
     * @description Logs an exception with context and saves immediately.
     *              Applies configured tags to the log entry.
     * @param message Context describing where the exception occurred
     * @param e Exception to log
     */
    public void logException(String message, Exception e) {
        // TODO: Replace with your logging framework
        // Example for Nebula Logger:
        // ILogEntryBuilder entry = nebulaLogger.exception(LOG_PREFIX + message, e);
        // applyTags(entry);
        // nebulaLogger.save();
        
        // Fallback to System.debug
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + formatWithTags(message) + ': ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    }
    
    /**
     * @description Formats the message with tags for display.
     * @param message The original message
     * @return Message with tags prepended if any
     */
    private String formatWithTags(String message) {
        if (tags.isEmpty()) {
            return message;
        }
        return '[' + String.join(new List<String>(tags), ', ') + '] ' + message;
    }
    
    /**
     * @description Callable implementation for cross-package tag support. The CursorBatchFramework
     *              package uses Callable to pass Logger_Tag__c from metadata config to the adapter
     *              without requiring a compile-time dependency on this class.
     * @param action Action name: 'addTag' or 'addTags'
     * @param args Map with 'tag' (String) for addTag, or 'tags' (Set<String>) for addTags
     * @return This adapter instance
     */
    public Object call(String action, Map<String, Object> args) {
        if (action == 'addTag') {
            addTag((String) args.get('tag'));
        } else if (action == 'addTags') {
            addTags((Set<String>) args.get('tags'));
        }
        return this;
    }
    
    // TODO: Add this method for Nebula Logger integration
    // private void applyTags(ILogEntryBuilder entry) {
    //     if (!this.tags.isEmpty()) {
    //         entry.addTags(this.tags);
    //     }
    // }
}
