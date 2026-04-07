@IsTest
private class CursorBatchCsvWorkerTest {

    @IsTest
    static void fetchAndProcess_delegatesToCsvProcess() {
        CursorBatchTestUtils.resetCsvWorker();

        List<Map<String, Object>> mockRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => 'Alice' },
            new Map<String, Object>{ 'Name' => 'Bob' }
        };
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withRows(mockRows));

        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord('CsvTest', 1, 'CursorJob');
        CursorBatchContext ctx = CursorBatchTestUtils.createCsvTestContext(job.Id, 'cq_test123');

        CursorBatchTestUtils.TestCsvWorker worker = new CursorBatchTestUtils.TestCsvWorker();
        worker.initialize(ctx);

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        System.assertEquals(1, CursorBatchTestUtils.testCsvWorker_processCallCount);
        System.assertEquals(2, CursorBatchTestUtils.testCsvWorker_processedRows.size());
        System.assertEquals('Alice', CursorBatchTestUtils.testCsvWorker_processedRows[0].get('Name'));
    }

    @IsTest
    static void fetchAndProcess_emptyRows_marksFinal() {
        CursorBatchTestUtils.resetCsvWorker();

        List<Map<String, Object>> emptyRows = new List<Map<String, Object>>();
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withRows(emptyRows));

        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord('CsvTest', 1, 'CursorJob');
        CursorBatchContext ctx = CursorBatchTestUtils.createCsvTestContext(job.Id, 'cq_test123');

        CursorBatchTestUtils.TestCsvWorker worker = new CursorBatchTestUtils.TestCsvWorker();
        worker.initialize(ctx);

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        System.assertEquals(0, CursorBatchTestUtils.testCsvWorker_processCallCount, 'process() should not be called for empty rows');
        System.assert(ctx.isFinal, 'Should be marked as final');
    }

    @IsTest
    static void soqlProcess_throwsForCsvWorker() {
        CursorBatchTestUtils.TestCsvWorker worker = new CursorBatchTestUtils.TestCsvWorker();

        Boolean caught = false;
        try {
            worker.process(new List<SObject>());
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            caught = true;
            System.assert(e.getMessage().contains('CSV workers'), 'Expected CSV workers message');
        }
        System.assert(caught, 'Expected exception when calling SObject process on CSV worker');
    }

    @IsTest
    static void csvContext_isCsvJob_true() {
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord('CsvTest', 1, 'CursorJob');
        CursorBatchContext ctx = CursorBatchTestUtils.createCsvTestContext(job.Id, 'cq_test');

        System.assert(ctx.isCsvJob, 'isCsvJob should be true for CSV context');
        System.assertEquals('CSV', ctx.processingType);
    }

    @IsTest
    static void csvContext_copy_preservesProcessingType() {
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord('CsvTest', 1, 'CursorJob');
        CursorBatchContext ctx = CursorBatchTestUtils.createCsvTestContext(job.Id, 'cq_test');

        CursorBatchContext next = ctx.withNextPosition(5);
        System.assertEquals('CSV', next.processingType, 'processingType should be preserved across copy');
        System.assert(next.isCsvJob);
    }

    // ── toDecimal ───────────────────────────────────────────────────────

    @IsTest
    static void toDecimal_fromString() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(150.75, w.testToDecimal('150.75'));
    }

    @IsTest
    static void toDecimal_fromDecimal() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(42.0, w.testToDecimal(42.0));
    }

    @IsTest
    static void toDecimal_null_returnsZero() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(0, w.testToDecimal(null));
    }

    @IsTest
    static void toDecimal_blank_returnsZero() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(0, w.testToDecimal(''));
        System.assertEquals(0, w.testToDecimal('  '));
    }

    // ── toInteger ───────────────────────────────────────────────────────

    @IsTest
    static void toInteger_fromString() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(7, w.testToInteger('7'));
    }

    @IsTest
    static void toInteger_fromDecimal() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(9, w.testToInteger(9.8));
    }

    @IsTest
    static void toInteger_fromInteger() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(3, w.testToInteger(3));
    }

    @IsTest
    static void toInteger_null_returnsZero() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(0, w.testToInteger(null));
    }

    @IsTest
    static void toInteger_blank_returnsZero() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(0, w.testToInteger(''));
    }

    // ── toDate ──────────────────────────────────────────────────────────

    @IsTest
    static void toDate_fromString() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(Date.newInstance(2025, 3, 15), w.testToDate('2025-03-15'));
    }

    @IsTest
    static void toDate_null_returnsNull() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(null, w.testToDate(null));
    }

    @IsTest
    static void toDate_blank_returnsNull() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(null, w.testToDate(''));
    }

    // ── toDatetime ──────────────────────────────────────────────────────

    @IsTest
    static void toDatetime_fromString() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        Datetime expected = Datetime.newInstance(2025, 6, 1, 14, 30, 0);
        System.assertEquals(expected, w.testToDatetime('2025-06-01 14:30:00'));
    }

    @IsTest
    static void toDatetime_null_returnsNull() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(null, w.testToDatetime(null));
    }

    @IsTest
    static void toDatetime_blank_returnsNull() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(null, w.testToDatetime(''));
    }

    // ── toBoolean ───────────────────────────────────────────────────────

    @IsTest
    static void toBoolean_trueStrings() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(true, w.testToBoolean('true'));
        System.assertEquals(true, w.testToBoolean('TRUE'));
        System.assertEquals(true, w.testToBoolean('1'));
        System.assertEquals(true, w.testToBoolean('yes'));
        System.assertEquals(true, w.testToBoolean('YES'));
    }

    @IsTest
    static void toBoolean_falseStrings() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(false, w.testToBoolean('false'));
        System.assertEquals(false, w.testToBoolean('0'));
        System.assertEquals(false, w.testToBoolean('no'));
    }

    @IsTest
    static void toBoolean_fromBoolean() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(true, w.testToBoolean(true));
        System.assertEquals(false, w.testToBoolean(false));
    }

    @IsTest
    static void toBoolean_null_returnsFalse() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(false, w.testToBoolean(null));
    }

    @IsTest
    static void toBoolean_blank_returnsFalse() {
        CursorBatchTestUtils.TestCsvWorker w = new CursorBatchTestUtils.TestCsvWorker();
        System.assertEquals(false, w.testToBoolean(''));
    }
}
