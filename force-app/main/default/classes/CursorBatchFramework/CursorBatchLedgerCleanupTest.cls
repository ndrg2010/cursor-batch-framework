/**
 * @description Unit tests for CursorBatchLedgerCleanup.
 *
 *              The enqueue itself is suppressed under Test.isRunningTest(), matching the rest of
 *              the framework, so these tests assert the throttle decision and the delete
 *              behaviour separately rather than trying to observe an async chain.
 * @group CursorBatchFramework
 * @see CursorBatchLedgerCleanup
 */
@IsTest
private without sharing class CursorBatchLedgerCleanupTest {

    @IsTest
    static void firstCallStampsTheSweepTimestamp() {
        Assert.isNull(CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c,
            'Precondition: an org that has never swept has no timestamp.');

        CursorBatchLedgerCleanup.maybeSweep(new CursorBatchTestUtils.MockCursorBatchLogger());

        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c,
            'The first job submission after install must start a sweep and record that it did.');
    }

    @IsTest
    static void secondCallInsideTheIntervalIsSkipped() {
        // The throttle is what makes it safe to call this from every job submission.
        Datetime recent = System.now().addHours(-1);
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Last_Ledger_Sweep__c = recent;
        upsert settings;

        CursorBatchLedgerCleanup.maybeSweep(new CursorBatchTestUtils.MockCursorBatchLogger());

        Assert.areEqual(recent, CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c,
            'A submission an hour after the last sweep must leave the timestamp untouched.');
    }

    @IsTest
    static void callAfterTheIntervalSweepsAgain() {
        Datetime stale = System.now().addHours(-1 * (CursorBatchLedgerCleanup.SWEEP_INTERVAL_HOURS + 1));
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Last_Ledger_Sweep__c = stale;
        upsert settings;

        CursorBatchLedgerCleanup.maybeSweep(new CursorBatchTestUtils.MockCursorBatchLogger());

        Assert.isTrue(CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c > stale,
            'Once the interval has elapsed the next submission must sweep again.');
    }

    @IsTest
    static void maybeSweepToleratesANullLogger() {
        CursorBatchLedgerCleanup.maybeSweep(null);

        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c,
            'Housekeeping must not depend on a logger being available.');
    }

    @IsTest
    static void retentionDefaultsWhenUnset() {
        Assert.areEqual(CursorBatchLedgerCleanup.DEFAULT_RETENTION_DAYS,
            CursorBatchLedgerCleanup.resolveRetentionDays(),
            'An unconfigured org must fall back to the framework default.');
    }

    @IsTest
    static void configuredRetentionIsHonored() {
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Ledger_Retention_Days__c = 14;
        upsert settings;

        Assert.areEqual(14, CursorBatchLedgerCleanup.resolveRetentionDays(),
            'An org that wants a longer window must get it.');
    }

    @IsTest
    static void zeroRetentionIsClampedToTheDefault() {
        // Zero would put the cutoff at "now", which could delete a marker the guard wrote moments
        // earlier and leave a live replay window.
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Ledger_Retention_Days__c = 0;
        upsert settings;

        Assert.areEqual(CursorBatchLedgerCleanup.DEFAULT_RETENTION_DAYS,
            CursorBatchLedgerCleanup.resolveRetentionDays(),
            'A retention of zero must be treated as a misconfiguration, not obeyed.');
    }

    @IsTest
    static void defaultRetentionOutlastsTheObservedReplayHorizon() {
        // The 2026-08-24 redelivery reached back 103 hours on a channel documented to retain 24.
        // A default shorter than that would leave the guard blind to the exact event it exists for.
        Assert.isTrue(CursorBatchLedgerCleanup.DEFAULT_RETENTION_DAYS * 24 > 103,
            'The default retention must exceed the longest replay actually observed in production.');
    }

    @IsTest
    static void sweepDeletesPastTheCutoffAndKeepsWhatIsInsideIt() {
        // Exercises the `WHERE CreatedDate < :cutoff` predicate itself, which is the one thing
        // that -- if it broke -- would silently erase the guard's memory and let a replay through.
        // Test.setCreatedDate is what makes the boundary reachable.
        CursorBatch_Event_Ledger__c expired = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'expired-1', Channel__c = 'Worker'
        );
        CursorBatch_Event_Ledger__c current = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'current-1', Channel__c = 'Worker'
        );
        insert new List<CursorBatch_Event_Ledger__c>{ expired, current };
        Test.setCreatedDate(
            expired.Id,
            System.now().addDays(-1 * (CursorBatchLedgerCleanup.DEFAULT_RETENTION_DAYS + 3))
        );

        Test.startTest();
        new CursorBatchLedgerCleanup().execute((QueueableContext) null);
        Test.stopTest();

        List<CursorBatch_Event_Ledger__c> survivors = [
            SELECT Event_Key__c FROM CursorBatch_Event_Ledger__c
        ];
        Assert.areEqual(1, survivors.size(), 'Exactly the row past the cutoff must be swept.');
        Assert.areEqual('current-1', survivors[0].Event_Key__c,
            'The row inside the retention window must survive; deleting it would blind the guard.');
    }

    @IsTest
    static void sweepHonorsALongerConfiguredRetention() {
        // A row that the default window would delete must survive a longer configured window.
        CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
        settings.Ledger_Retention_Days__c = 30;
        upsert settings;

        CursorBatch_Event_Ledger__c row = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'ten-days-old', Channel__c = 'Worker'
        );
        insert row;
        Test.setCreatedDate(row.Id, System.now().addDays(-10));

        Test.startTest();
        new CursorBatchLedgerCleanup().execute((QueueableContext) null);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'A 10-day-old row must survive a 30-day retention window.');
    }

    @IsTest
    static void sweepToleratesRowsAnotherChainAlreadyDeleted() {
        // Overlapping sweeps are an ordinary case: this is one shared org-wide table, so two
        // callers past the interval check both enqueue, and a scheduled sweep can overlap a
        // self-throttled one. A bare delete would throw and kill the chain silently.
        CursorBatch_Event_Ledger__c expired = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'raced-1', Channel__c = 'Worker'
        );
        insert expired;
        Test.setCreatedDate(
            expired.Id,
            System.now().addDays(-1 * (CursorBatchLedgerCleanup.DEFAULT_RETENTION_DAYS + 3))
        );

        CursorBatchLedgerCleanup sweep = new CursorBatchLedgerCleanup();
        delete expired;

        Test.startTest();
        Boolean threw = false;
        try {
            sweep.execute((QueueableContext) null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw,
            'A row deleted by a concurrent sweep must not kill this chain and leave the ledger unswept.');
    }

    @IsTest
    static void sweepIsANoOpWhenThereIsNothingToDelete() {
        Test.startTest();
        new CursorBatchLedgerCleanup().execute((QueueableContext) null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'An empty ledger must sweep cleanly rather than throwing.');
    }

    @IsTest
    static void chainedSweepWithABlankCursorIsANoOp() {
        // Guards the chaining constructor against a cursor that could not be extracted.
        Test.startTest();
        new CursorBatchLedgerCleanup(null, 0).execute((QueueableContext) null);
        Test.stopTest();

        Assert.isTrue(true, 'A blank cursor queryId must return without throwing.');
    }

    @IsTest
    static void chainedSweepPastTheEndIsANoOp() {
        insert new CursorBatch_Event_Ledger__c(Event_Key__c = 'past-end', Channel__c = 'Worker');
        Database.Cursor cursor = Database.getCursorWithBinds(
            'SELECT Id FROM CursorBatch_Event_Ledger__c WHERE Event_Key__c = :key',
            new Map<String, Object>{ 'key' => 'past-end' },
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        new CursorBatchLedgerCleanup(CursorBatchContext.extractQueryId(cursor), 500)
            .execute((QueueableContext) null);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'Resuming beyond the end of the cursor must delete nothing.');
    }

    @IsTest
    static void chainedSweepDeletesThePageItIsPointedAt() {
        insert new List<CursorBatch_Event_Ledger__c>{
            new CursorBatch_Event_Ledger__c(Event_Key__c = 'sweep-1', Channel__c = 'Worker'),
            new CursorBatch_Event_Ledger__c(Event_Key__c = 'sweep-2', Channel__c = 'Worker')
        };
        Database.Cursor cursor = Database.getCursorWithBinds(
            'SELECT Id FROM CursorBatch_Event_Ledger__c WHERE Event_Key__c LIKE :pattern',
            new Map<String, Object>{ 'pattern' => 'sweep-%' },
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        new CursorBatchLedgerCleanup(CursorBatchContext.extractQueryId(cursor), 0)
            .execute((QueueableContext) null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'The cursor page the sweep was pointed at must be deleted.');
    }

    @IsTest
    static void aRowAnotherChainDeletedIsSilent() {
        // Tests the tolerance policy directly. A live cursor will not hand back a row that has
        // already been deleted, so the only honest way to reach this branch is to call it with
        // one. An overlapping sweep is expected and must not be reported as a problem.
        CursorBatch_Event_Ledger__c row = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'already-gone', Channel__c = 'Worker'
        );
        insert row;
        Id deletedId = row.Id;
        delete row;

        Test.startTest();
        CursorBatchLedgerCleanup.deleteTolerantly(
            new List<SObject>{ new CursorBatch_Event_Ledger__c(Id = deletedId) }
        );
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'Re-deleting a row a concurrent sweep already removed must be a silent no-op.');
    }

    @IsTest
    static void aPartialFailureDoesNotTakeTheHealthyRowsWithIt()  {
        // Partial-success is the property that keeps a sweep alive. A bare `delete` fails the
        // whole page when any one row is already gone, which would kill the chain and leave the
        // rest of the ledger unswept until the next interval.
        CursorBatch_Event_Ledger__c gone = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'gone', Channel__c = 'Worker'
        );
        CursorBatch_Event_Ledger__c present = new CursorBatch_Event_Ledger__c(
            Event_Key__c = 'present', Channel__c = 'Worker'
        );
        insert new List<CursorBatch_Event_Ledger__c>{ gone, present };
        Id goneId = gone.Id;
        delete gone;

        Test.startTest();
        CursorBatchLedgerCleanup.deleteTolerantly(new List<SObject>{
            new CursorBatch_Event_Ledger__c(Id = goneId),
            new CursorBatch_Event_Ledger__c(Id = present.Id)
        });
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Event_Ledger__c],
            'The row that was still there must be deleted even though another row in the page was already gone.');
    }

    @IsTest
    static void scheduledEntryPointStampsTheTimestamp() {
        // Scheduling is optional, but when an org does schedule it the self-throttled path must
        // stand down rather than sweeping a second time the same day.
        Test.startTest();
        new CursorBatchLedgerCleanupSchedule().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.isNotNull(CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c,
            'A scheduled sweep must stamp the timestamp too, so the self-throttled path stands down.');
    }

    @IsTest
    static void markSweptStandsDownTheSelfThrottledPath() {
        CursorBatchLedgerCleanup.markSwept();
        Datetime stamped = CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c;
        Assert.isNotNull(stamped, 'Precondition: markSwept must record the sweep.');

        CursorBatchLedgerCleanup.maybeSweep(new CursorBatchTestUtils.MockCursorBatchLogger());

        Assert.areEqual(stamped, CursorBatch_Settings__c.getOrgDefaults().Last_Ledger_Sweep__c,
            'A job submission right after a scheduled sweep must not start another one.');
    }

    @IsTest
    static void scheduleCanBeRegisteredWithSystemSchedule() {
        // Pins that the class is genuinely Schedulable, which it could not be while it also
        // implemented Queueable.
        Test.startTest();
        String jobId = System.schedule(
            'CursorBatch Ledger Cleanup Test', '0 0 2 * * ?', new CursorBatchLedgerCleanupSchedule()
        );
        Test.stopTest();

        Assert.isNotNull(jobId, 'The cleanup schedule must be registrable with System.schedule.');
    }
}
