/**
 * @description Closes jobs left in Processing because a worker never reported its completion.
 *
 *              A job only goes terminal when Workers_Finished__c + Failed_Workers__c reaches
 *              Total_Workers__c, and each worker reports through the completion event its own
 *              finalizer publishes. On 2026-10-14 Salesforce never ran the finalizer for one of 93
 *              Lump Payment Automation workers, although the queueable itself completed. The job
 *              sat at 92 of 93 for 13 hours: finish() never fired, so the nightly chain stopped,
 *              and because isJobAlreadyRunning treats Processing as running, every submission of
 *              the job in the meantime silently returned null. Nothing else in the framework could
 *              notice, because everything else waits on a report that was never going to arrive.
 *
 *              A job is treated as stalled when all of the following hold:
 *              - it is Processing and still has workers unaccounted for;
 *              - it has not changed for its threshold: CursorBatch_Config__mdt.Stalled_Job_Minutes__c,
 *                else CursorBatch_Settings__c.Stalled_Job_Minutes__c, else 60, and never below 15.
 *                Every completion batch writes the job, so LastModifiedDate is the time of the last
 *                report. -1 on the config excludes the job;
 *              - no async job for its worker class is queued or running. A worker chains its next
 *                page or its retry before the current queueable ends, so a worker that is still
 *                going always shows up here.
 *
 *              The watchdog never writes the job. For each unaccounted worker it publishes the
 *              failure report a worker that exhausted its retries would publish, marked
 *              Reported_By__c = Watchdog, so the terminal transition, parent mirror, logging, and
 *              finish() routing stay in CursorBatchCompletionHandler. That handler counts watchdog
 *              reports only into whatever gap remains, so a real report that turns up late, an
 *              overlapping run, or a completion backlog the reports queue behind can never count a
 *              worker twice.
 *
 *              Trigger mechanism: as with CursorBatchLedgerCleanup, unlocked packages have no
 *              post-install hook, so maybeRun() is called on job submission and throttles itself
 *              through CursorBatch_Settings__c. Orgs that prefer a fixed cadence can schedule
 *              CursorBatchStalledJobWatchdogSchedule, which stamps the same timestamp.
 * @group CursorBatchFramework
 * @see CursorBatchCompletionHandler
 * @see CursorBatchStalledJobWatchdogSchedule
 * @see CursorBatchLedgerCleanup
 */
public without sharing class CursorBatchStalledJobWatchdog implements Queueable {
    
    /** Threshold used when neither the job's config nor the org setting sets one. */
    public static final Integer DEFAULT_STALLED_JOB_MINUTES = 60;
    
    /** Lowest threshold honored. A tighter one risks closing a job whose reports are only queued. */
    public static final Integer MIN_STALLED_JOB_MINUTES = 15;
    
    /** CursorBatch_Config__mdt.Stalled_Job_Minutes__c value that excludes a job from the watchdog. */
    public static final Integer OPT_OUT = -1;
    
    /** Gap between self-throttled runs when the org setting does not set one. */
    public static final Integer DEFAULT_INTERVAL_MINUTES = 15;
    
    /** Lowest gap between self-throttled runs that is honored. */
    public static final Integer MIN_INTERVAL_MINUTES = 5;
    
    /** Jobs examined per run; any beyond this wait for the next run. */
    @TestVisible
    private static final Integer MAX_JOBS_PER_RUN = 50;
    
    /**
     * Failure reports published per run. Each report counts against the org's platform event
     * publishing allocation, so once a run has this many, further jobs wait for the next run.
     * A single job is always reported in full, so a very wide job is never split across runs.
     */
    @TestVisible
    private static Integer maxReportsPerRun = 2000;
    
    /** Overrides "now" so the idle-time comparison can be tested without waiting. */
    @TestVisible
    private static Datetime nowOverride;
    
    /**
     * @description Enqueues a watchdog run if none has started within the interval, stamping the
     *              settings row first so a second caller in the same window does not enqueue
     *              another. Two callers racing past the check may both enqueue, which is harmless:
     *              the completion handler never counts a worker twice.
     *
     *              Adds one DML statement to the calling transaction when it decides to run. It
     *              does not throw for any reason it can control.
     * @param logger Logger for reporting a failure to start
     */
    public static void maybeRun(ICursorBatchLogger logger) {
        try {
            CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
            Datetime lastRun = settings.Last_Watchdog_Run__c;
            if (lastRun != null && lastRun > System.now().addMinutes(-1 * resolveIntervalMinutes(settings))) {
                return;
            }
            
            if (!hasSpareQueueableSlot()) {
                return;
            }
            
            stampLastRun(settings);
            
            if (!Test.isRunningTest()) {
                System.enqueueJob(new CursorBatchStalledJobWatchdog());
            }
        } catch (Exception e) {
            if (logger != null) {
                logger.logException('CursorBatchStalledJobWatchdog: Could not start the stalled-job watchdog', e);
            }
        }
    }
    
    /**
     * @description Stamps the run timestamp so a scheduled run stands the self-throttled path down
     *              for the rest of the interval. Called by CursorBatchStalledJobWatchdogSchedule.
     */
    public static void markRun() {
        try {
            stampLastRun(CursorBatch_Settings__c.getOrgDefaults());
        } catch (Exception e) {
            // A failure to stamp only means the self-throttled path may also run this interval,
            // which costs one redundant scan and nothing else.
        }
    }
    
    /**
     * @description Scans for stalled jobs and reports their silent workers as failed.
     * @param ctx Queueable context (unused)
     */
    public void execute(QueueableContext ctx) {
        ICursorBatchLogger logger = CursorBatchLogger.resolveLogger(CursorBatchLogger.TAG_JOB_STALLED);
        try {
            scan(logger);
        } catch (Exception e) {
            logger.logException('CursorBatchStalledJobWatchdog: Scan failed; stalled jobs will be picked up by the next run', e);
        }
    }
    
    /**
     * @description Finds stalled jobs and publishes one failure report per unaccounted worker.
     * @param logger Logger for the per-job entries
     * @return Number of jobs whose workers were reported
     */
    @TestVisible
    private Integer scan(ICursorBatchLogger logger) {
        Datetime evaluatedAt = now();
        Integer defaultMinutes = resolveDefaultStalledMinutes();
        
        List<CursorBatch_Job__c> idleJobs = new List<CursorBatch_Job__c>();
        Map<Id, Integer> thresholdByJobId = new Map<Id, Integer>();
        Map<Id, Set<String>> classNamesByJobId = new Map<Id, Set<String>>();
        Set<String> classNamesToCheck = new Set<String>();
        
        List<CursorBatch_Job__c> candidates = CursorBatchSelector.getIdleProcessingJobs(
            evaluatedAt.addMinutes(-1 * MIN_STALLED_JOB_MINUTES), MAX_JOBS_PER_RUN
        );
        for (CursorBatch_Job__c job : candidates) {
            if (unaccountedWorkers(job) <= 0) {
                continue;
            }
            
            Integer thresholdMinutes = resolveThresholdMinutes(job.Job_Name__c, defaultMinutes);
            if (thresholdMinutes == OPT_OUT || job.LastModifiedDate >= evaluatedAt.addMinutes(-1 * thresholdMinutes)) {
                continue;
            }
            
            String workerClass = resolveWorkerClassName(job);
            if (String.isBlank(workerClass)) {
                jobLogger(logger, job).logError(CursorBatchLogger.scoped(
                    CursorBatchLogger.SCOPE_JOB_STALLED,
                    describe(job) + ' has been idle past its ' + thresholdMinutes + '-minute threshold, but its ' +
                        'worker class cannot be resolved, so the watchdog cannot tell whether workers are still ' +
                        'running and left it alone. Close it with CursorBatchCoordinator.killJob() once you have ' +
                        'confirmed nothing is running.'
                ));
                continue;
            }
            
            Set<String> classNames = classNameSegments(workerClass);
            idleJobs.add(job);
            thresholdByJobId.put(job.Id, thresholdMinutes);
            classNamesByJobId.put(job.Id, classNames);
            classNamesToCheck.addAll(classNames);
        }
        
        if (idleJobs.isEmpty()) {
            return 0;
        }
        
        Set<String> activeClassNames = CursorBatchSelector.getActiveAsyncClassNames(classNamesToCheck);
        
        List<CursorBatch_WorkerComplete__e> reports = new List<CursorBatch_WorkerComplete__e>();
        List<CursorBatch_Job__c> reportedJobs = new List<CursorBatch_Job__c>();
        for (CursorBatch_Job__c job : idleJobs) {
            if (containsAny(activeClassNames, classNamesByJobId.get(job.Id))) {
                continue;
            }
            
            Integer missing = unaccountedWorkers(job);
            if (!reports.isEmpty() && reports.size() + missing > maxReportsPerRun) {
                continue;
            }
            
            String message = buildReportMessage(job, missing, thresholdByJobId.get(job.Id));
            for (Integer i = 0; i < missing; i++) {
                reports.add(CursorBatchCompletionHandler.buildFailureReport(
                    job.Id, null, CursorBatchCompletionHandler.REPORTED_BY_WATCHDOG, message
                ));
            }
            reportedJobs.add(job);
        }
        
        if (reports.isEmpty()) {
            return 0;
        }
        
        CursorBatchCompletionHandler.publishFailureReports(reports, logger);
        
        for (CursorBatch_Job__c job : reportedJobs) {
            jobLogger(logger, job).logError(CursorBatchLogger.scoped(
                CursorBatchLogger.SCOPE_JOB_STALLED,
                describe(job) + ' stalled in Processing: ' + unaccountedWorkers(job) + ' of ' +
                    job.Total_Workers__c.intValue() + ' worker(s) never reported, nothing has changed since ' +
                    formatTimestamp(job.LastModifiedDate) + ' (threshold ' + thresholdByJobId.get(job.Id) +
                    ' min), and no worker queueable is queued or running. Reported them as failed so the job ' +
                    'can finish.'
            ));
        }
        return reportedJobs.size();
    }
    
    /**
     * @description Resolves the worker class whose async jobs show whether the job is still
     *              running: the config's Worker_Class__c, or getWorkerClassName() on a reflectively
     *              built coordinator for jobs without one.
     * @param job The job being checked
     * @return Worker class name, or null when it cannot be determined
     */
    private static String resolveWorkerClassName(CursorBatch_Job__c job) {
        try {
            CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig(job.Job_Name__c);
            if (config != null && String.isNotBlank(config.Worker_Class__c)) {
                return config.Worker_Class__c;
            }
            
            Type coordinatorType = String.isBlank(job.Coordinator_Class__c) ? null : Type.forName(job.Coordinator_Class__c);
            if (coordinatorType == null) {
                return null;
            }
            Object instance = coordinatorType.newInstance();
            if (!(instance instanceof CursorBatchCoordinator)) {
                return null;
            }
            CursorBatchCoordinator coordinator = (CursorBatchCoordinator) instance;
            coordinator.initializeJobName(job.Job_Name__c);
            return coordinator.getWorkerClassName();
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Resolves a job's idle threshold.
     * @param jobName Job name (CursorBatch_Config__mdt MasterLabel)
     * @param defaultMinutes Org-level threshold, already resolved
     * @return Threshold in minutes, or OPT_OUT when the job is excluded
     */
    @TestVisible
    private static Integer resolveThresholdMinutes(String jobName, Integer defaultMinutes) {
        Decimal configured = null;
        try {
            configured = CursorBatchCoordinator.getConfig(jobName)?.Stalled_Job_Minutes__c;
        } catch (Exception e) {
            // A config lookup failure must not decide anything; fall back to the org threshold.
        }
        if (configured == null) {
            return defaultMinutes;
        }
        if (configured < 0) {
            return OPT_OUT;
        }
        return Math.max(configured.intValue(), MIN_STALLED_JOB_MINUTES);
    }
    
    /**
     * @description Resolves the org-level idle threshold. Zero or negative is treated as a
     *              misconfiguration and ignored: there is deliberately no org-wide off switch.
     * @return Threshold in minutes
     */
    @TestVisible
    private static Integer resolveDefaultStalledMinutes() {
        Decimal configured = CursorBatch_Settings__c.getOrgDefaults().Stalled_Job_Minutes__c;
        if (configured == null || configured < 1) {
            return DEFAULT_STALLED_JOB_MINUTES;
        }
        return Math.max(configured.intValue(), MIN_STALLED_JOB_MINUTES);
    }
    
    /**
     * @description Resolves the gap between self-throttled runs.
     * @param settings Org-level settings
     * @return Interval in minutes
     */
    @TestVisible
    private static Integer resolveIntervalMinutes(CursorBatch_Settings__c settings) {
        Decimal configured = settings?.Watchdog_Interval_Minutes__c;
        if (configured == null || configured < 1) {
            return DEFAULT_INTERVAL_MINUTES;
        }
        return Math.max(configured.intValue(), MIN_INTERVAL_MINUTES);
    }
    
    /**
     * @description Writes only Last_Watchdog_Run__c, never the whole settings row, so a stale copy
     *              cannot overwrite a field another writer changed -- such as the ledger sweep
     *              stamping Last_Ledger_Sweep__c earlier in the same submission.
     *
     *              System mode is explicit because this class is saved at API 67.0, where database
     *              operations otherwise run with the permissions of the user whose submission armed
     *              the watchdog.
     * @param settings Org-level settings as read by the caller
     */
    private static void stampLastRun(CursorBatch_Settings__c settings) {
        if (settings?.Id != null) {
            update as system new CursorBatch_Settings__c(Id = settings.Id, Last_Watchdog_Run__c = System.now());
            return;
        }
        
        Id orgId = UserInfo.getOrganizationId();
        try {
            insert as system new CursorBatch_Settings__c(SetupOwnerId = orgId, Last_Watchdog_Run__c = System.now());
        } catch (DmlException e) {
            // The ledger sweep may have created the org-level row earlier in this transaction,
            // after the caller read the settings.
            List<CursorBatch_Settings__c> existing = [
                SELECT Id FROM CursorBatch_Settings__c WHERE SetupOwnerId = :orgId WITH SYSTEM_MODE LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw e;
            }
            update as system new CursorBatch_Settings__c(Id = existing[0].Id, Last_Watchdog_Run__c = System.now());
        }
    }
    
    /**
     * @description Reports whether a queueable can be enqueued and still leave one slot for the
     *              caller. Inside a Queueable, Batch, or Finalizer the limit is 1, and consuming it
     *              would break a caller that runs CursorJob.run() and then chains its own
     *              continuation. Checked rather than caught, because the LimitException is not
     *              catchable.
     * @return true when enqueueing would leave at least one slot unused
     */
    private static Boolean hasSpareQueueableSlot() {
        return Limits.getQueueableJobs() + 1 < Limits.getLimitQueueableJobs();
    }
    
    private static Integer unaccountedWorkers(CursorBatch_Job__c job) {
        Decimal total = job.Total_Workers__c != null ? job.Total_Workers__c : 0;
        Decimal finished = job.Workers_Finished__c != null ? job.Workers_Finished__c : 0;
        Decimal failed = job.Failed_Workers__c != null ? job.Failed_Workers__c : 0;
        return Math.max(0, (total - finished - failed).intValue());
    }
    
    private static Set<String> classNameSegments(String className) {
        Set<String> segments = new Set<String>();
        for (String segment : className.split('\\.')) {
            if (String.isNotBlank(segment)) {
                segments.add(segment.trim());
            }
        }
        return segments;
    }
    
    private static Boolean containsAny(Set<String> haystack, Set<String> needles) {
        for (String needle : needles) {
            if (haystack.contains(needle)) {
                return true;
            }
        }
        return false;
    }
    
    private static String buildReportMessage(CursorBatch_Job__c job, Integer missing, Integer thresholdMinutes) {
        return 'Stalled-job watchdog: ' + missing + ' of ' + job.Total_Workers__c.intValue() +
            ' worker(s) never reported completion. No worker queueable for this job was queued or running, and ' +
            'the job had not changed since ' + formatTimestamp(job.LastModifiedDate) + ' (threshold ' +
            thresholdMinutes + ' min). Whether the silent worker(s) processed their records is unknown.';
    }
    
    private static ICursorBatchLogger jobLogger(ICursorBatchLogger logger, CursorBatch_Job__c job) {
        return CursorBatchLogger.withScopeTags(
            logger,
            CursorBatchCompletionHandler.resolveJobTag(job.Job_Name__c),
            new Set<String>{ CursorBatchLogger.TAG_JOB_STALLED }
        );
    }
    
    private static String describe(CursorBatch_Job__c job) {
        return 'Job: ' + job.Job_Name__c + ' (' + job.Id + ')';
    }
    
    private static String formatTimestamp(Datetime value) {
        return value != null ? value.formatGmt('yyyy-MM-dd HH:mm:ss') + ' UTC' : 'an unknown time';
    }
    
    private static Datetime now() {
        return nowOverride != null ? nowOverride : System.now();
    }
}
