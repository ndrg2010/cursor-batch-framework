/**
 * @description Schedulable wrapper around CursorBatchStalledJobWatchdog, for orgs that want the
 *              watchdog on a fixed cadence instead of whenever a job submission trips the
 *              interval.
 *
 *              Optional. The watchdog arms itself on job submission without this; see
 *              CursorBatchStalledJobWatchdog.maybeRun. Scheduling it stamps the same timestamp, so
 *              the self-throttled path stands down.
 *
 *              A separate class only because Apex does not allow one class to implement both
 *              Queueable and Schedulable.
 *
 *              Cron expressions run at most hourly, so a 15-minute cadence takes four entries:
 *
 *                  for (Integer minute : new List<Integer>{ 0, 15, 30, 45 }) {
 *                      System.schedule(
 *                          'CursorBatch Stalled Job Watchdog :' + String.valueOf(minute).leftPad(2, '0'),
 *                          '0 ' + minute + ' * * * ?',
 *                          new CursorBatchStalledJobWatchdogSchedule()
 *                      );
 *                  }
 * @group CursorBatchFramework
 * @see CursorBatchStalledJobWatchdog
 */
public without sharing class CursorBatchStalledJobWatchdogSchedule implements Schedulable {
    
    /**
     * @description Stamps the run timestamp and enqueues the watchdog.
     * @param ctx Schedulable context (unused)
     */
    public void execute(SchedulableContext ctx) {
        CursorBatchStalledJobWatchdog.markRun();
        if (!Test.isRunningTest()) {
            System.enqueueJob(new CursorBatchStalledJobWatchdog());
        }
    }
}
