/**
 * @description Unit tests for CursorBatchStalledJobWatchdog and CursorBatchStalledJobWatchdogSchedule.
 *
 *              LastModifiedDate cannot be set in a test, so idle time is simulated by moving the
 *              watchdog's clock forward with nowOverride. AsyncApexJob rows cannot be inserted
 *              either, so whether a worker class is still running comes from
 *              CursorBatchSelector.activeAsyncClassNamesOverride. Test.stopTest() delivers the
 *              failure reports to the completion trigger, so the tests assert on the job's terminal
 *              state rather than on the events themselves.
 *
 *              DML and queries here run explicitly in system mode. This class is saved at API
 *              67.0, where they would otherwise enforce the running user's field-level security,
 *              and the admin running tests in a packaging or scratch org has none on the package's
 *              own fields.
 * @group CursorBatchFramework
 * @see CursorBatchStalledJobWatchdog
 */
@IsTest
private without sharing class CursorBatchStalledJobWatchdogTest {
    
    private static final String JOB_NAME = 'Stalled Watchdog Job';
    private static final String COUNTING_COORDINATOR = 'CursorBatchTestUtils.FinishCountingCoordinator';
    
    /**
     * @description Config whose worker class resolves to the inner test worker. It sets no query
     *              builder, so the completion handler routes finish() to the job's coordinator,
     *              which lets FinishCountingCoordinator observe it.
     */
    private static CursorBatch_Config__mdt useConfig(Decimal stalledJobMinutes) {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig(JOB_NAME, 3, 10);
        config.Worker_Class__c = 'CursorBatchTestUtils.TestCursorBatchWorker';
        config.Stalled_Job_Minutes__c = stalledJobMinutes;
        CursorBatchCoordinator.testConfig = config;
        return config;
    }
    
    private static CursorBatch_Job__c createJob(Integer totalWorkers, Integer workersFinished, String coordinatorClass) {
        CursorBatchTestUtils.resetFinishCountingCoordinator();
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(JOB_NAME, totalWorkers, coordinatorClass);
        job.Workers_Finished__c = workersFinished;
        job.Completed_Batches__c = workersFinished;
        update as system job;
        return job;
    }
    
    private static void idleFor(Integer minutes) {
        CursorBatchStalledJobWatchdog.nowOverride = System.now().addMinutes(minutes);
    }
    
    private static void noWorkersRunning() {
        CursorBatchSelector.activeAsyncClassNamesOverride = new Set<String>();
    }
    
    // ============================================
    // Detection
    // ============================================
    
    @IsTest
    static void stalledJobIsClosedAsCompletedWithErrorsAndFinishRuns() {
        // The 2026-10-14 shape: one of the workers finished its work but its report never arrived.
        useConfig(null);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        CursorBatchTestUtils.MockCursorBatchLogger logger = new CursorBatchTestUtils.MockCursorBatchLogger();
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(logger);
        Test.stopTest();
        
        Assert.areEqual(1, reported, 'The stalled job should be reported.');
        CursorBatch_Job__c reloaded = CursorBatchSelector.getJobById(job.Id);
        Assert.areEqual('Completed with Errors', reloaded.Status__c,
            'A job whose silent worker is presumed failed must finish, not stay Processing.');
        Assert.areEqual(2, reloaded.Workers_Finished__c, 'The workers that did report must stay counted as finished.');
        Assert.areEqual(1, reloaded.Failed_Workers__c, 'Exactly the silent worker must be counted as failed.');
        Assert.isNotNull(reloaded.Completed_At__c,
            'The job must be genuinely terminal so isJobAlreadyRunning stops blocking new submissions.');
        Assert.isTrue(reloaded.Error_Message__c.startsWith('Stalled-job watchdog: 1 of 3 worker(s) never reported'),
            'The job record must say why it was closed. Got: ' + reloaded.Error_Message__c);
        Assert.areEqual(1, CursorBatchTestUtils.finishCountingCoordinator_finishCallCount,
            'finish() must run exactly once, so anything chained to the job is released.');
        Assert.isTrue(logger.hasErrorContaining('[' + CursorBatchLogger.SCOPE_JOB_STALLED + ']'),
            'Closing a stalled job must be logged at ERROR so it can be alerted on.');
    }
    
    @IsTest
    static void jobWithAWorkerStillRunningIsLeftAlone() {
        // AsyncApexJob.ApexClass.Name is the top-level class, so the inner test worker shows up as
        // its outer class. The watchdog has to treat that as the worker still running.
        useConfig(null);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        CursorBatchSelector.activeAsyncClassNamesOverride = new Set<String>{ 'CursorBatchTestUtils' };
        idleFor(240);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(0, reported, 'A job with a worker queueable still queued or running must not be closed.');
        CursorBatch_Job__c reloaded = CursorBatchSelector.getJobById(job.Id);
        Assert.areEqual('Processing', reloaded.Status__c, 'The job must be left running.');
        Assert.areEqual(0, reloaded.Failed_Workers__c, 'No worker may be presumed failed while one is running.');
    }
    
    @IsTest
    static void recentlyActiveJobIsLeftAlone() {
        useConfig(null);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES - 10);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(0, reported, 'A job that heard from a worker within its threshold must not be closed.');
        Assert.areEqual('Processing', CursorBatchSelector.getJobById(job.Id).Status__c, 'The job must be left running.');
    }
    
    @IsTest
    static void perJobThresholdOverridesTheDefault() {
        useConfig(20);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(30);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(1, reported, 'A 20-minute job threshold must apply instead of the 60-minute default.');
        Assert.areEqual('Completed with Errors', CursorBatchSelector.getJobById(job.Id).Status__c,
            'The job must be closed under its own threshold.');
    }
    
    @IsTest
    static void orgThresholdAppliesWhenTheJobSetsNone() {
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Stalled_Job_Minutes__c = 30;
        upsert as system settings;
        useConfig(null);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        
        Test.startTest();
        idleFor(25);
        Integer reportedEarly = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        idleFor(45);
        Integer reportedLate = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(0, reportedEarly, 'Inside the 30-minute org threshold the job must be left alone.');
        Assert.areEqual(1, reportedLate, 'Past the 30-minute org threshold the job must be reported.');
        Assert.areEqual('Completed with Errors', CursorBatchSelector.getJobById(job.Id).Status__c,
            'The job must be closed once past the org threshold.');
    }
    
    @IsTest
    static void thresholdBelowTheFloorIsRaised() {
        // A one-minute threshold would close jobs whose reports are merely queued behind others.
        useConfig(1);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(10);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(0, reported,
            'A threshold below ' + CursorBatchStalledJobWatchdog.MIN_STALLED_JOB_MINUTES + ' minutes must be raised to it.');
        Assert.areEqual('Processing', CursorBatchSelector.getJobById(job.Id).Status__c, 'The job must be left running.');
    }
    
    @IsTest
    static void optedOutJobIsNeverClosed() {
        useConfig(CursorBatchStalledJobWatchdog.OPT_OUT);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(60 * 24 * 7);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(0, reported, 'A job with Stalled_Job_Minutes__c = -1 must be excluded from the watchdog.');
        Assert.areEqual('Processing', CursorBatchSelector.getJobById(job.Id).Status__c, 'The job must be left running.');
    }
    
    @IsTest
    static void workerClassFallsBackToTheCoordinator() {
        // Custom coordinators have no Worker_Class__c on a config; the worker class comes from
        // getWorkerClassName() on a reflectively built coordinator instead.
        CursorBatch_Job__c job = createJob(2, 1, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(1, reported, 'The worker class must resolve through the coordinator when there is no config.');
        Assert.areEqual('Completed with Errors', CursorBatchSelector.getJobById(job.Id).Status__c,
            'The job must be closed.');
        Assert.areEqual(1, CursorBatchTestUtils.finishCountingCoordinator_finishCallCount,
            'finish() must still be routed to the coordinator.');
    }
    
    @IsTest
    static void unresolvableWorkerClassIsLeftAloneAndLogged() {
        // Without a worker class there is no way to prove no worker is running, so the job must be
        // left for a person -- and the entry must say so, because the job is still stuck.
        CursorBatch_Job__c job = createJob(2, 1, 'NoSuchCoordinatorClass');
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        CursorBatchTestUtils.MockCursorBatchLogger logger = new CursorBatchTestUtils.MockCursorBatchLogger();
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(logger);
        Test.stopTest();
        
        Assert.areEqual(0, reported, 'A job whose worker class cannot be resolved must not be closed.');
        Assert.areEqual('Processing', CursorBatchSelector.getJobById(job.Id).Status__c, 'The job must be left running.');
        Assert.isTrue(logger.hasErrorContaining('cannot be resolved'),
            'The still-stuck job must be reported so someone can close it.');
    }
    
    @IsTest
    static void fullyAccountedJobIsNotReported() {
        useConfig(null);
        CursorBatch_Job__c job = createJob(2, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(0, reported, 'A job with no unaccounted workers has nothing for the watchdog to report.');
        Assert.areEqual(0, CursorBatchSelector.getJobById(job.Id).Failed_Workers__c, 'No worker may be presumed failed.');
    }
    
    @IsTest
    static void overlappingRunsCountTheSilentWorkerOnce() {
        // Two runs can race past the throttle. Both publish a report for the same silent worker;
        // the completion handler must count only one of them.
        useConfig(null);
        CursorBatch_Job__c job = createJob(3, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        
        Test.startTest();
        new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        CursorBatch_Job__c reloaded = CursorBatchSelector.getJobById(job.Id);
        Assert.areEqual(1, reloaded.Failed_Workers__c, 'Duplicate watchdog reports must count the silent worker once.');
        Assert.areEqual(1, CursorBatchTestUtils.finishCountingCoordinator_finishCallCount,
            'Duplicate watchdog reports must not fire finish() twice.');
    }
    
    @IsTest
    static void reportsBeyondThePerRunCapWaitForTheNextRun() {
        useConfig(null);
        CursorBatch_Job__c first = createJob(2, 0, COUNTING_COORDINATOR);
        CursorBatch_Job__c second = CursorBatchTestUtils.createTestJobRecord(JOB_NAME, 2, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        CursorBatchStalledJobWatchdog.maxReportsPerRun = 3;
        
        Test.startTest();
        Integer reported = new CursorBatchStalledJobWatchdog().scan(new CursorBatchTestUtils.MockCursorBatchLogger());
        Test.stopTest();
        
        Assert.areEqual(1, reported, 'Only the jobs that fit under the per-run cap should be reported.');
        Set<Id> jobIds = new Set<Id>{ first.Id, second.Id };
        Integer stillProcessing = [
            SELECT COUNT() FROM CursorBatch_Job__c WHERE Id IN :jobIds AND Status__c = 'Processing' WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, stillProcessing, 'The job over the cap must be left for the next run.');
    }
    
    @IsTest
    static void executeRunsTheScan() {
        useConfig(null);
        CursorBatch_Job__c job = createJob(2, 1, COUNTING_COORDINATOR);
        noWorkersRunning();
        idleFor(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES + 5);
        
        Test.startTest();
        new CursorBatchStalledJobWatchdog().execute((QueueableContext) null);
        Test.stopTest();
        
        Assert.areEqual('Completed with Errors', CursorBatchSelector.getJobById(job.Id).Status__c,
            'The queueable entry point must run the same scan.');
    }
    
    // ============================================
    // Threshold and interval resolution
    // ============================================
    
    @IsTest
    static void orgThresholdIgnoresMisconfiguration() {
        Assert.areEqual(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES,
            CursorBatchStalledJobWatchdog.resolveDefaultStalledMinutes(), 'An unset org threshold must use the default.');
        
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Stalled_Job_Minutes__c = -1;
        upsert as system settings;
        Assert.areEqual(CursorBatchStalledJobWatchdog.DEFAULT_STALLED_JOB_MINUTES,
            CursorBatchStalledJobWatchdog.resolveDefaultStalledMinutes(),
            'There is no org-wide off switch; a negative org threshold must fall back to the default.');
        
        settings.Stalled_Job_Minutes__c = 5;
        update as system settings;
        Assert.areEqual(CursorBatchStalledJobWatchdog.MIN_STALLED_JOB_MINUTES,
            CursorBatchStalledJobWatchdog.resolveDefaultStalledMinutes(), 'An org threshold below the floor must be raised.');
    }
    
    @IsTest
    static void jobThresholdResolution() {
        useConfig(null);
        Assert.areEqual(42, CursorBatchStalledJobWatchdog.resolveThresholdMinutes(JOB_NAME, 42),
            'A job without its own threshold must use the org threshold.');
        
        useConfig(-5);
        Assert.areEqual(CursorBatchStalledJobWatchdog.OPT_OUT, CursorBatchStalledJobWatchdog.resolveThresholdMinutes(JOB_NAME, 42),
            'Any negative job threshold must opt the job out.');
        
        useConfig(0);
        Assert.areEqual(CursorBatchStalledJobWatchdog.MIN_STALLED_JOB_MINUTES,
            CursorBatchStalledJobWatchdog.resolveThresholdMinutes(JOB_NAME, 42), 'A zero job threshold must be raised to the floor.');
    }
    
    @IsTest
    static void intervalResolution() {
        CursorBatch_Settings__c settings = new CursorBatch_Settings__c();
        Assert.areEqual(CursorBatchStalledJobWatchdog.DEFAULT_INTERVAL_MINUTES,
            CursorBatchStalledJobWatchdog.resolveIntervalMinutes(settings), 'An unset interval must use the default.');
        
        settings.Watchdog_Interval_Minutes__c = 1;
        Assert.areEqual(CursorBatchStalledJobWatchdog.MIN_INTERVAL_MINUTES,
            CursorBatchStalledJobWatchdog.resolveIntervalMinutes(settings), 'An interval below the floor must be raised.');
        
        settings.Watchdog_Interval_Minutes__c = 45;
        Assert.areEqual(45, CursorBatchStalledJobWatchdog.resolveIntervalMinutes(settings), 'A valid interval must be honored.');
    }
    
    // ============================================
    // Self-throttled trigger
    // ============================================
    
    @IsTest
    static void firstCallStampsTheRunTimestamp() {
        Assert.isNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'Precondition: an org where the watchdog never ran has no timestamp.');
        
        CursorBatchStalledJobWatchdog.maybeRun(new CursorBatchTestUtils.MockCursorBatchLogger());
        
        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'The first job submission must start a run and record that it did.');
    }
    
    @IsTest
    static void secondCallInsideTheIntervalIsSkipped() {
        Datetime recent = System.now().addMinutes(-5);
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Last_Watchdog_Run__c = recent;
        upsert as system settings;
        
        CursorBatchStalledJobWatchdog.maybeRun(new CursorBatchTestUtils.MockCursorBatchLogger());
        
        Assert.areEqual(recent, CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'A submission inside the interval must leave the timestamp untouched.');
    }
    
    @IsTest
    static void callAfterTheIntervalRunsAgain() {
        Datetime stale = System.now().addMinutes(-1 * (CursorBatchStalledJobWatchdog.DEFAULT_INTERVAL_MINUTES + 1));
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Last_Watchdog_Run__c = stale;
        upsert as system settings;
        
        CursorBatchStalledJobWatchdog.maybeRun(new CursorBatchTestUtils.MockCursorBatchLogger());
        
        Assert.isTrue(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c > stale,
            'Once the interval has elapsed the next submission must start another run.');
    }
    
    @IsTest
    static void configuredIntervalIsHonored() {
        Datetime halfAnHourAgo = System.now().addMinutes(-30);
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Watchdog_Interval_Minutes__c = 60;
        settings.Last_Watchdog_Run__c = halfAnHourAgo;
        upsert as system settings;
        
        CursorBatchStalledJobWatchdog.maybeRun(new CursorBatchTestUtils.MockCursorBatchLogger());
        
        Assert.areEqual(halfAnHourAgo, CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'A 60-minute interval must hold off a run half an hour after the last one.');
    }
    
    @IsTest
    static void stampingLeavesTheLedgerSweepTimestampAlone() {
        // The ledger sweep and the watchdog share one settings row and both stamp it during the
        // same submission; neither may write back the other's field.
        Datetime swept = System.now().addHours(-2);
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Last_Ledger_Sweep__c = swept;
        upsert as system settings;
        
        CursorBatchStalledJobWatchdog.maybeRun(new CursorBatchTestUtils.MockCursorBatchLogger());
        
        CursorBatch_Settings__c reloaded = CursorBatch_Settings__c.getOrgDefaults();
        Assert.isNotNull(reloaded.Last_Watchdog_Run__c, 'Precondition: the watchdog must have been armed.');
        Assert.areEqual(swept, reloaded.Last_Ledger_Sweep__c, 'Arming the watchdog must not touch the sweep timestamp.');
    }
    
    @IsTest
    static void maybeRunToleratesANullLogger() {
        CursorBatchStalledJobWatchdog.maybeRun(null);
        
        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'The watchdog must not depend on a logger being available.');
    }
    
    @IsTest
    static void submissionArmsTheWatchdog() {
        Test.startTest();
        new CursorBatchTestUtils.TestCursorBatchCoordinator('Watchdog Arming Job').submit();
        Test.stopTest();
        
        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'Submitting a job must arm the watchdog.');
    }
    
    @IsTest
    static void blockedSubmissionArmsTheWatchdogToo() {
        // A job stuck in Processing is exactly what blocks a submission, so a blocked submission
        // is the moment the watchdog is most needed.
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator =
            new CursorBatchTestUtils.TestCursorBatchCoordinator('Watchdog Blocked Job');
        coordinator.shouldBlockDuplicate = true;
        
        Test.startTest();
        Id jobId = coordinator.submit();
        Test.stopTest();
        
        Assert.isNull(jobId, 'Precondition: the submission must have been blocked.');
        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'A blocked submission must arm the watchdog.');
    }
    
    @IsTest
    static void delayedSubmissionArmsTheWatchdog() {
        Test.startTest();
        new CursorBatchTestUtils.TestCursorBatchCoordinator('Watchdog Delayed Job').submitWithDelay(1);
        Test.stopTest();
        
        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'A delayed submission must arm the watchdog.');
    }
    
    // ============================================
    // Scheduled trigger
    // ============================================
    
    @IsTest
    static void scheduledEntryPointStampsTheTimestamp() {
        Test.startTest();
        new CursorBatchStalledJobWatchdogSchedule().execute((SchedulableContext) null);
        Test.stopTest();
        
        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'A scheduled run must stamp the timestamp too, so the self-throttled path stands down.');
    }
    
    @IsTest
    static void markRunStandsDownTheSelfThrottledPath() {
        CursorBatchStalledJobWatchdog.markRun();
        Datetime stamped = CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c;
        Assert.isNotNull(stamped, 'Precondition: markRun must record the run.');
        
        CursorBatchStalledJobWatchdog.maybeRun(new CursorBatchTestUtils.MockCursorBatchLogger());
        
        Assert.areEqual(stamped, CursorBatch_Settings__c.getOrgDefaults().Last_Watchdog_Run__c,
            'A submission right after a scheduled run must not start another one.');
    }
    
    @IsTest
    static void scheduleCanBeRegisteredWithSystemSchedule() {
        Test.startTest();
        String cronJobId = System.schedule(
            'CursorBatch Stalled Job Watchdog Test', '0 15 * * * ?', new CursorBatchStalledJobWatchdogSchedule()
        );
        Test.stopTest();
        
        Assert.isNotNull(cronJobId, 'The watchdog schedule must be registrable with System.schedule.');
    }
}
