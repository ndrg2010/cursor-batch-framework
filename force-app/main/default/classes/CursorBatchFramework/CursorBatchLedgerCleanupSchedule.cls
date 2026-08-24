/**
 * @description Schedulable wrapper around CursorBatchLedgerCleanup, for orgs that would rather
 *              sweep the replay-guard ledger in a known window than let it happen on whichever
 *              job submission happens to trip the 24-hour threshold.
 *
 *              Optional. The framework sweeps on its own without this; see
 *              CursorBatchLedgerCleanup.maybeSweep. Scheduling it simply makes the timing
 *              predictable, and stamps the same timestamp so the self-throttled path stands down.
 *
 *              A separate class only because Apex does not allow one class to implement both
 *              Queueable and Schedulable.
 *
 *              To schedule nightly at 02:00:
 *
 *                  System.schedule(
 *                      'CursorBatch Ledger Cleanup',
 *                      '0 0 2 * * ?',
 *                      new CursorBatchLedgerCleanupSchedule()
 *                  );
 * @group CursorBatchFramework
 * @see CursorBatchLedgerCleanup
 */
public without sharing class CursorBatchLedgerCleanupSchedule implements Schedulable {
    
    /**
     * @description Stamps the sweep timestamp and enqueues the sweep.
     * @param ctx Schedulable context (unused)
     */
    public void execute(SchedulableContext ctx) {
        CursorBatchLedgerCleanup.markSwept();
        if (!Test.isRunningTest()) {
            System.enqueueJob(new CursorBatchLedgerCleanup());
        }
    }
}
