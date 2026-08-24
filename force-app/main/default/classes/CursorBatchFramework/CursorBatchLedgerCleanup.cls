/**
 * @description Deletes aged CursorBatch_Event_Ledger__c rows in chunks, and decides when that
 *              needs doing.
 *
 *              The ledger is what makes CursorBatchReplayGuard able to recognise an event it has
 *              already processed, so it has to be retained longer than the longest replay the
 *              event bus could deliver. On 2026-08-24 that was 103 hours on a channel whose
 *              documented retention is 24, so the default is deliberately a full week rather
 *              than a day.
 *
 *              Trigger mechanism: unlocked packages support no post-install script, so nothing
 *              here can schedule itself at install time. Instead maybeSweep() is called from the
 *              coordinator's job submission path and throttles itself to once a day using
 *              CursorBatch_Settings__c. getOrgDefaults() is a free cached read, so the check
 *              costs nothing on a path that already performs DML.
 *
 *              It is deliberately not called on job completion. During the 2026-08-24 replay
 *              11,425 jobs went terminal inside 28 minutes; a completion-triggered sweep would
 *              have enqueued 11,425 cleanup jobs, each running a cursor query and a delete, on
 *              top of the 314,453 asynchronous jobs already in flight. A cleanup mechanism that
 *              multiplies during a replay storm is worse than no cleanup at all.
 *
 *              Orgs that would rather sweep in a known window than let it happen on whichever
 *              job submission trips the threshold can schedule CursorBatchLedgerCleanupSchedule
 *              instead. That is a separate class because Apex does not allow one class to
 *              implement both Queueable and Schedulable.
 * @group CursorBatchFramework
 * @see CursorBatchReplayGuard
 * @see CursorBatchLedgerCleanupSchedule
 * @see CursorBatchCoordinator
 */
public without sharing class CursorBatchLedgerCleanup implements Queueable {
    
    /** Ledger rows deleted per chained execution. */
    private static final Integer PAGE_SIZE = 2000;
    
    /** Retention used when CursorBatch_Settings__c.Ledger_Retention_Days__c is not set. */
    public static final Integer DEFAULT_RETENTION_DAYS = 7;
    
    /** Minimum gap between self-throttled sweeps. */
    public static final Integer SWEEP_INTERVAL_HOURS = 24;
    
    private final String cursorQueryId;
    private final Integer position;
    
    /**
     * @description Builds a sweep over every ledger row older than the configured retention.
     *              The cutoff is resolved here rather than in execute() so a chained continuation
     *              keeps working against the same boundary instead of drifting as it runs.
     */
    public CursorBatchLedgerCleanup() {
        Datetime cutoff = System.now().addDays(-1 * resolveRetentionDays());
        String soql = 'SELECT Id FROM CursorBatch_Event_Ledger__c WHERE CreatedDate < :cutoff';
        Map<String, Object> bindVars = new Map<String, Object>{ 'cutoff' => cutoff };
        Database.Cursor cursor = Database.getCursorWithBinds(soql, bindVars, AccessLevel.SYSTEM_MODE);
        this.cursorQueryId = CursorBatchContext.extractQueryId(cursor);
        this.position = 0;
    }
    
    /**
     * @description Private constructor for chaining when more pages remain.
     * @param cursorQueryId Cursor queryId to resume from
     * @param position Position within the cursor to resume at
     */
    @TestVisible
    private CursorBatchLedgerCleanup(String cursorQueryId, Integer position) {
        this.cursorQueryId = cursorQueryId;
        this.position = position;
    }
    
    /**
     * @description Enqueues a sweep if the org has not had one in SWEEP_INTERVAL_HOURS, stamping
     *              the settings row first so a second caller in the same window does not enqueue
     *              a duplicate. Two callers racing at the same instant may both enqueue, which is
     *              harmless: the sweep tolerates rows another chain already deleted.
     *
     *              Adds one DML statement to the calling transaction when it decides to sweep,
     *              plus one query for the cursor. It does not throw for any reason it can
     *              control, but it cannot promise never to throw: a governor LimitException is
     *              not catchable in Apex, which is why the async-slot check below is a check
     *              rather than a try/catch.
     * @param logger Logger for reporting a failure to sweep
     */
    public static void maybeSweep(ICursorBatchLogger logger) {
        try {
            CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
            Datetime lastSweep = settings.Last_Ledger_Sweep__c;
            if (lastSweep != null && lastSweep > System.now().addHours(-1 * SWEEP_INTERVAL_HOURS)) {
                return;
            }
            
            if (!hasSpareQueueableSlot()) {
                return;
            }
            
            settings.Last_Ledger_Sweep__c = System.now();
            upsert settings;
            
            if (!Test.isRunningTest()) {
                System.enqueueJob(new CursorBatchLedgerCleanup());
            }
        } catch (Exception e) {
            if (logger != null) {
                logger.logException('CursorBatchLedgerCleanup: Could not start the event ledger sweep', e);
            }
        }
    }
    
    /**
     * @description Reports whether a queueable can be enqueued and still leave one slot for the
     *              caller.
     *
     *              Checked rather than caught, because exceeding the queueable limit raises a
     *              LimitException and Apex will not let us catch it.
     *
     *              The spare slot is the point. Inside a Queueable, Batch, or Finalizer the limit
     *              is 1, so consuming it would break a consumer that calls CursorJob.run() and
     *              then chains its own continuation -- an uncatchable failure in code that worked
     *              before this housekeeping existed. Retention must never change the async budget
     *              a caller can rely on, so it only sweeps out of genuine slack. Standing down
     *              costs nothing: the timestamp is not stamped, so the next submission from a
     *              context with room tries again.
     * @return true when enqueueing would leave at least one slot unused
     */
    private static Boolean hasSpareQueueableSlot() {
        return Limits.getQueueableJobs() + 1 < Limits.getLimitQueueableJobs();
    }
    
    /**
     * @description Stamps the sweep timestamp so a scheduled run stands the self-throttled path
     *              down for the rest of the interval. Called by
     *              CursorBatchLedgerCleanupSchedule.
     */
    public static void markSwept() {
        try {
            CursorBatch_Settings__c settings = CursorBatch_Settings__c.getOrgDefaults();
            settings.Last_Ledger_Sweep__c = System.now();
            upsert settings;
        } catch (Exception e) {
            // A failure to stamp only means the self-throttled path may also fire today, which
            // costs one redundant sweep and nothing else.
        }
    }
    
    /**
     * @description Deletes one page of aged ledger rows and chains while more remain.
     *
     *              Written to tolerate a second sweep running over the same rows. Unlike the
     *              per-job cleanup this pattern came from, the ledger is one shared org-wide
     *              table, so overlapping chains are an ordinary case rather than a corner one --
     *              two callers racing past the interval check both enqueue, and a scheduled sweep
     *              can overlap a self-throttled one. Two consequences are handled explicitly:
     *
     *              Deletes are partial-success. A bare `delete` throws when another chain has
     *              already removed a row in the page, which would kill this chain silently and
     *              leave the rest of the ledger unswept until tomorrow.
     *
     *              The cursor advances by the page size rather than by the number of rows
     *              returned. Advancing by the row count cannot guarantee forward progress: an
     *              empty page while position is still short of the end would re-enqueue at the
     *              same offset forever, which is an unbounded self-perpetuating queueable. Rows
     *              skipped this way were deleted by the other chain anyway.
     * @param ctx Queueable context (unused)
     */
    public void execute(QueueableContext ctx) {
        if (String.isBlank(cursorQueryId)) {
            return;
        }
        Database.Cursor cursor = CursorBatchContext.reconstructCursor(cursorQueryId);
        if (cursor == null) {
            return;
        }
        Integer numRecords = cursor.getNumRecords();
        if (position >= numRecords) {
            return;
        }
        
        Integer fetchSize = Math.min(PAGE_SIZE, numRecords - position);
        List<SObject> toDelete = cursor.fetch(position, fetchSize);
        if (!toDelete.isEmpty()) {
            deleteTolerantly(toDelete);
        }
        
        Integer nextPosition = position + fetchSize;
        if (nextPosition < numRecords && !Test.isRunningTest()) {
            System.enqueueJob(new CursorBatchLedgerCleanup(cursorQueryId, nextPosition));
        }
    }
    
    /**
     * @description Deletes a page, reporting rows it could not remove instead of throwing. An
     *              ALREADY_DELETED-style failure is expected when sweeps overlap and is not worth
     *              reporting; anything else means the ledger is not draining and needs to be
     *              visible, because an undrained ledger grows without bound.
     * @param toDelete Rows fetched from the cursor page
     */
    @TestVisible
    private static void deleteTolerantly(List<SObject> toDelete) {
        Integer unexpectedFailures = 0;
        String firstError = null;
        for (Database.DeleteResult result : Database.delete(toDelete, false, AccessLevel.SYSTEM_MODE)) {
            if (result.isSuccess()) {
                continue;
            }
            for (Database.Error error : result.getErrors()) {
                if (error.getStatusCode() == StatusCode.ENTITY_IS_DELETED) {
                    continue;
                }
                unexpectedFailures++;
                if (firstError == null) {
                    firstError = error.getStatusCode() + ': ' + error.getMessage();
                }
            }
        }
        
        if (unexpectedFailures > 0) {
            CursorBatchLogger.resolveLogger(CursorBatchLogger.TAG_REPLAY_BLOCKED).logError(
                'CursorBatchLedgerCleanup: ' + unexpectedFailures + ' ledger row(s) could not be ' +
                'deleted, so the ledger is not draining. First error: ' + firstError
            );
        }
    }
    
    /**
     * @description Resolves the retention window, clamping to at least one day so a misconfigured
     *              zero cannot delete the ledger out from under the guard mid-transaction.
     * @return Retention in days
     */
    @TestVisible
    private static Integer resolveRetentionDays() {
        Decimal configured = CursorBatch_Settings__c.getOrgDefaults().Ledger_Retention_Days__c;
        if (configured == null || configured < 1) {
            return DEFAULT_RETENTION_DAYS;
        }
        return configured.intValue();
    }
}
