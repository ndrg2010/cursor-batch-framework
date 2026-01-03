/**
 * @description Platform Event trigger for CursorBatch_WorkerComplete__e. Delegates to
 *              CursorBatchCompletionHandler for tracking worker completion and invoking callbacks.
 */
trigger CursorBatchWorkerCompleteTrigger on CursorBatch_WorkerComplete__e (after insert) {
    new CursorBatchCompletionHandler().handle(Trigger.new);
}