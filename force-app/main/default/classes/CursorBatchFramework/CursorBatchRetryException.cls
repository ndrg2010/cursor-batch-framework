/**
 * @description Custom exception that callers can throw from CursorBatchWorker.process() to 
 *              explicitly signal that the current page should be retried. This provides caller
 *              control over retry behavior, distinguishing retryable failures from permanent ones.
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 */
public class CursorBatchRetryException extends Exception {
    
    /**
     * @description Optional suggested delay in minutes for the retry. If null, the framework
     *              uses exponential backoff based on the retry count.
     */
    public Integer suggestedDelayMinutes { get; private set; }
    
    /**
     * @description Creates a retry exception with a message and suggested delay.
     *              For message-only exceptions, use the two-argument version with null delay.
     * @param message Error message describing why retry is needed
     * @param delayMinutes Suggested delay in minutes before retry (null for default exponential backoff)
     * @return CursorBatchRetryException instance
     */
    public static CursorBatchRetryException create(String message, Integer delayMinutes) {
        CursorBatchRetryException ex = new CursorBatchRetryException();
        ex.setMessage(message);
        ex.suggestedDelayMinutes = delayMinutes;
        return ex;
    }
}