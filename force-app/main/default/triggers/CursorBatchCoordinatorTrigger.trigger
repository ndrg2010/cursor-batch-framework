/**
 * @description Platform Event trigger for CursorBatch_Coordinator__e events. Delegates to
 *              CursorBatchCoordinatorTriggerHandler for processing. This trigger ensures the
 *              coordinator runs as the dedicated trigger user, enabling cursor access from workers.
 * @group CursorBatchFramework
 */
trigger CursorBatchCoordinatorTrigger on CursorBatch_Coordinator__e (after insert) {
    new CursorBatchCoordinatorTriggerHandler().handle(Trigger.new);
}
