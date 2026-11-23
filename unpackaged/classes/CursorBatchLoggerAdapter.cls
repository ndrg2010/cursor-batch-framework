/**
 * @description Adapter that bridges ICursorBatchLogger to your logging framework for 
 *              CursorBatchFramework integration. This class is automatically discovered
 *              by CursorJob when it exists in the org.
 * 
 * Usage:
 *      The framework looks for a class named 'CursorBatchLoggerAdapter' that implements
 *      ICursorBatchLogger. If found, it uses this adapter for logging. If not found, it
 *      falls back to CursorBatchLogger (System.debug). Keep the class name exactly as-is:
 *      discovery is by name, so a renamed adapter is never found.
 * 
 *      Callable is required, not optional. It is how the framework passes
 *      CursorBatch_Config__mdt.Logger_Tag__c to this adapter without a compile-time
 *      dependency. An adapter without Callable can never receive Logger_Tag__c.
 * 
 *      Do not call setLogger() from coordinators or workers. As of v0.33.0 the framework
 *      applies Logger_Tag__c on both the processing path and the finish() path, so a
 *      setLogger() call inside finish() replaces an already-tagged logger with an
 *      untagged one.
 * 
 *      Each entry saves immediately while the transaction has platform-event publish budget
 *      left. Saving immediately is what keeps an entry when the transaction later dies from
 *      an uncatchable limit or timeout, so do not switch to saving once at the end. But a
 *      Nebula save publishes an immediate platform event, and those are capped at 150 per
 *      transaction: an adapter that saves unconditionally makes any caller that logs in a
 *      loop fail at the cap. hasPublishBudget() keeps INFO saves clear of it and lets errors
 *      use what is left.
 * 
 * @group CursorBatchFramework
 * @see ICursorBatchLogger
 * @see CursorJob
 */
public inherited sharing class CursorBatchLoggerAdapter implements ICursorBatchLogger, Callable {
    
    private static final String LOG_PREFIX = '[CursorBatch] ';
    
    /** Publishes left untouched by INFO saves, so errors logged later can still be saved. */
    private static final Integer INFO_PUBLISH_RESERVE = 10;
    
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
     * @description Logs an informational message. Saves immediately while at least
     *              INFO_PUBLISH_RESERVE platform-event publishes remain in the transaction;
     *              otherwise the entry stays buffered and goes out with the next save.
     *              Applies configured tags to the log entry.
     * @param message Message to log
     */
    public void logInfo(String message) {
        // TODO: Replace with your logging framework
        // Example for Nebula Logger:
        // ILogEntryBuilder entry = nebulaLogger.info(LOG_PREFIX + message);
        // applyTags(entry);
        // if (hasPublishBudget(INFO_PUBLISH_RESERVE)) {
        //     nebulaLogger.save();
        // }
        
        // Fallback to System.debug
        System.debug(LoggingLevel.INFO, LOG_PREFIX + formatWithTags(message));
    }
    
    /**
     * @description Logs an error message and saves immediately while any platform-event
     *              publish budget remains. Applies configured tags to the log entry.
     * @param message Error message to log
     */
    public void logError(String message) {
        // TODO: Replace with your logging framework
        // Example for Nebula Logger:
        // ILogEntryBuilder entry = nebulaLogger.error(LOG_PREFIX + message);
        // applyTags(entry);
        // if (hasPublishBudget(0)) {
        //     nebulaLogger.save();
        // }
        
        // Fallback to System.debug
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + formatWithTags(message));
    }
    
    /**
     * @description Logs an exception with context and saves immediately while any
     *              platform-event publish budget remains. Applies configured tags to the
     *              log entry.
     * @param message Context describing where the exception occurred
     * @param e Exception to log
     */
    public void logException(String message, Exception e) {
        // TODO: Replace with your logging framework
        // Example for Nebula Logger:
        // ILogEntryBuilder entry = nebulaLogger.exception(LOG_PREFIX + message, e);
        // applyTags(entry);
        // if (hasPublishBudget(0)) {
        //     nebulaLogger.save();
        // }
        
        // Fallback to System.debug
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + formatWithTags(message) + ': ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    }
    
    /**
     * @description Reports whether one more immediate platform-event publish fits in this
     *              transaction with the given number of publishes still left over.
     * @param reserve Publishes that must remain after this save
     * @return true when a save can publish without eating into the reserve
     */
    @TestVisible
    private static Boolean hasPublishBudget(Integer reserve) {
        return Limits.getPublishImmediateDML() + 1 + reserve <= Limits.getLimitPublishImmediateDML();
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
