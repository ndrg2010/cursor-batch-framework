/**
 * @description Default logging implementation for CursorBatchFramework using System.debug.
 *              Implement ICursorBatchLogger to integrate with Nebula Logger, Pharos, or
 *              other logging frameworks.
 * @group CursorBatchFramework
 * @see ICursorBatchLogger
 */
public without sharing class CursorBatchLogger implements ICursorBatchLogger {
    
    private static final String LOG_PREFIX = '[CursorBatch] ';
    
    /** Adapter class name resolved by convention. */
    private static final String ADAPTER_CLASS_NAME = 'CursorBatchLoggerAdapter';
    
    /**
     * @description Overrides the adapter class name in tests so the Callable tagging path can be
     *              exercised without a real adapter deployed to the org.
     */
    @TestVisible
    private static String testAdapterClassName;
    
    // ============== Scope tokens ==============
    // Prefixed to log messages so the source of an error is unambiguous. Without these, a
    // once-per-job finish() failure and a per-worker page failure are indistinguishable: both
    // land at ERROR level under the same Logger_Tag__c, and the job-level finish() failure for
    // metadata-driven jobs is even raised from CursorBatchWorker.
    
    public static final String SCOPE_JOB_COMPLETED = 'JOB COMPLETED';
    public static final String SCOPE_JOB_COMPLETED_WITH_ERRORS = 'JOB COMPLETED WITH ERRORS';
    public static final String SCOPE_JOB_FAILED = 'JOB FAILED';
    public static final String SCOPE_JOB_CANCELLED = 'JOB CANCELLED';
    public static final String SCOPE_JOB_FINISH_FAILED = 'JOB FINISH FAILED';
    public static final String SCOPE_JOB_CHAIN_FAILED = 'JOB CHAIN FAILED';
    public static final String SCOPE_WORKER_FAILED = 'WORKER FAILED';
    public static final String SCOPE_EVENT_REPLAY_BLOCKED = 'EVENT REPLAY BLOCKED';
    
    // ============== Scope tags ==============
    // Applied alongside Logger_Tag__c so subscribers can filter by scope without parsing messages.
    
    public static final String TAG_JOB_FAILURE = 'CursorBatch Job Failure';
    public static final String TAG_JOB_PARTIAL_FAILURE = 'CursorBatch Job Partial Failure';
    public static final String TAG_JOB_FINISH_FAILURE = 'CursorBatch Job Finish Failure';
    public static final String TAG_JOB_CHAIN_FAILURE = 'CursorBatch Job Chain Failure';
    public static final String TAG_WORKER_FAILURE = 'CursorBatch Worker Failure';
    public static final String TAG_REPLAY_BLOCKED = 'CursorBatch Replay Blocked';
    
    /** Prefix for the tag derived from a platform error code in AsyncApexJob.ExtendedStatus. */
    public static final String TAG_FAILURE_CODE_PREFIX = 'CursorBatch Failure ';
    
    /** Marks the AsyncApexJob.ExtendedStatus text appended to an otherwise opaque platform error. */
    public static final String PLATFORM_STATUS_PREFIX = 'Platform status: ';
    
    /**
     * ExtendedStatus leads with a bracketed platform error code, e.g. '[QUERY_TIMEOUT] ...'.
     * Multiline with an optional PLATFORM_STATUS_PREFIX so the code is found both in a raw
     * ExtendedStatus value and in a composed error message where it sits on its own line.
     * Anchoring to line start avoids matching bracketed text inside a stack trace.
     */
    private static final Pattern FAILURE_CODE_PATTERN = Pattern.compile(
        '(?m)^\\s*(?:' + PLATFORM_STATUS_PREFIX + ')?\\[([A-Z0-9_]+)\\]'
    );
    
    /**
     * @description Returns a new default logger instance using System.debug.
     * @return ICursorBatchLogger instance
     */
    public static ICursorBatchLogger getDefault() {
        return new CursorBatchLogger();
    }

    /**
     * @description Resolves the logger implementation using convention-based discovery.
     *              Looks for a class named 'CursorBatchLoggerAdapter' that implements ICursorBatchLogger.
     *              Falls back to CursorBatchLogger (System.debug) if not found.
     * @param tag Optional tag to apply to log entries (when adapter supports Callable addTag)
     * @return ICursorBatchLogger instance
     */
    public static ICursorBatchLogger resolveLogger(String tag) {
        return resolveLogger(tag, null);
    }

    /**
     * @description Resolves the logger implementation and applies the job tag plus any additional
     *              scope tags. Always returns a new adapter instance, which matters because
     *              adapters typically accumulate tags in per-instance state: reusing one instance
     *              across differently scoped entries would leak the first entry's tags onto later
     *              ones.
     * @param tag Optional job tag (CursorBatch_Config__mdt.Logger_Tag__c)
     * @param extraTags Optional additional tags, such as the scope and platform failure code
     * @return ICursorBatchLogger instance
     */
    public static ICursorBatchLogger resolveLogger(String tag, Set<String> extraTags) {
        try {
            Type adapterType = Type.forName(getAdapterClassName());
            if (adapterType != null) {
                Object instance = adapterType.newInstance();
                if (instance instanceof ICursorBatchLogger) {
                    ICursorBatchLogger adapter = (ICursorBatchLogger) instance;
                    applyTags(adapter, tag, extraTags);
                    return adapter;
                }
            }
        } catch (Exception e) {
            // Class not found or instantiation failed - use default
        }
        return getDefault();
    }
    
    /**
     * @description Returns a logger carrying the given scope tags for a single scoped emission.
     *              Adapters that cannot be tagged are returned unchanged so callers (and tests
     *              injecting a mock) keep the logger they supplied; taggable adapters get a fresh
     *              instance so the scope tags do not leak onto later entries.
     * @param baseLogger Logger the caller would otherwise have used
     * @param jobTag Job tag to apply to the fresh instance (CursorBatch_Config__mdt.Logger_Tag__c)
     * @param scopeTags Scope tags for this emission
     * @return Logger to emit the scoped entry through
     */
    public static ICursorBatchLogger withScopeTags(ICursorBatchLogger baseLogger, String jobTag, Set<String> scopeTags) {
        if (scopeTags == null || scopeTags.isEmpty() || !(baseLogger instanceof Callable)) {
            return baseLogger;
        }
        return resolveLogger(jobTag, scopeTags);
    }
    
    /**
     * @description Prefixes a message with its scope token.
     * @param scope Scope token, e.g. SCOPE_JOB_FINISH_FAILED
     * @param message Message to prefix
     * @return Message prefixed with the scope, or unchanged when scope is blank
     */
    public static String scoped(String scope, String message) {
        return String.isBlank(scope) ? message : '[' + scope + '] ' + message;
    }
    
    /**
     * @description Derives a filterable tag from the platform error code that leads
     *              AsyncApexJob.ExtendedStatus, e.g. '[QUERY_TIMEOUT] Your query request was
     *              running for too long.' yields 'CursorBatch Failure QUERY_TIMEOUT'. Parsed
     *              generically so any platform code is supported without a hardcoded list.
     *              Accepts either a raw ExtendedStatus or a composed error message containing a
     *              'Platform status: ' line.
     * @param text ExtendedStatus or composed error message, may be null or blank
     * @return Tag for the failure code, or null when no code is present
     */
    public static String failureCodeTag(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        Matcher codeMatcher = FAILURE_CODE_PATTERN.matcher(text);
        return codeMatcher.find() ? TAG_FAILURE_CODE_PREFIX + codeMatcher.group(1) : null;
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
        return formatExceptionMessage(e, null);
    }
    
    /**
     * @description Formats an exception and appends the platform status recovered from
     *              AsyncApexJob.ExtendedStatus. Uncatchable platform aborts reach Apex as
     *              'System.UnexpectedException: connection was cancelled here' with no detail,
     *              while the actionable text (for example '[QUERY_TIMEOUT] Your query request was
     *              running for too long.') exists only on the AsyncApexJob record.
     * @param e Exception to format, or null
     * @param platformStatus AsyncApexJob.ExtendedStatus value, or null/blank when unavailable
     * @return Formatted error message, with the platform status appended when present
     */
    public static String formatExceptionMessage(Exception e, String platformStatus) {
        String message = e != null ? e.getMessage() + '\n' + e.getStackTraceString() : 'Unknown error';
        if (String.isNotBlank(platformStatus)) {
            message += '\n\n' + PLATFORM_STATUS_PREFIX + platformStatus;
        }
        return message;
    }
    
    private static String getAdapterClassName() {
        return (Test.isRunningTest() && String.isNotBlank(testAdapterClassName))
            ? testAdapterClassName
            : ADAPTER_CLASS_NAME;
    }
    
    /**
     * @description Passes tags to a Callable adapter. Uses the single-tag action when there is
     *              only one so adapters that implement addTag but not addTags keep working.
     * @param logger Adapter to tag
     * @param tag Job tag
     * @param extraTags Additional scope tags
     */
    private static void applyTags(ICursorBatchLogger logger, String tag, Set<String> extraTags) {
        if (!(logger instanceof Callable)) {
            return;
        }
        
        Set<String> allTags = new Set<String>();
        if (String.isNotBlank(tag)) {
            allTags.add(tag);
        }
        if (extraTags != null) {
            for (String extraTag : extraTags) {
                if (String.isNotBlank(extraTag)) {
                    allTags.add(extraTag);
                }
            }
        }
        if (allTags.isEmpty()) {
            return;
        }
        
        try {
            if (allTags.size() == 1) {
                ((Callable) logger).call('addTag', new Map<String, Object>{ 'tag' => new List<String>(allTags)[0] });
            } else {
                ((Callable) logger).call('addTags', new Map<String, Object>{ 'tags' => allTags });
            }
        } catch (Exception e) {
            // Adapter rejected the tags; the entry is still logged, just without them.
        }
    }
}
