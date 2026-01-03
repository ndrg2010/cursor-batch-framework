/**
 * @description Platform Event trigger for CursorBatch_Worker__e events. Delegates to
 *              CursorBatchWorkerTriggerHandler for processing.
 * @group CursorBatchFramework
 */
trigger CursorBatchWorkerTrigger on CursorBatch_Worker__e (after insert) {
    new CursorBatchWorkerTriggerHandler().handle(Trigger.new);
}