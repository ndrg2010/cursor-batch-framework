@IsTest
private class CursorBatchCsvCallbackCoordinatorTest {

    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(1);
    }

    @IsTest
    static void execute_fansOutWorkersOnCallback() {
        CursorBatchTestUtils.CsvMiddlewareMock mock = new CursorBatchTestUtils.CsvMiddlewareMock()
            .withRowCount(25);
        Test.setMock(HttpCalloutMock.class, mock);

        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestCsvJob', 5, 10);
        config.Processing_Type__c = CursorBatchContext.PROCESSING_TYPE_CSV;
        config.Worker_Class__c = 'CursorBatchTestUtils.TestCsvWorker';
        CursorBatchCoordinator.testConfig = config;

        CursorBatch_Job__c job = CursorBatchTestUtils.createPreparingJobRecord(
            'TestCsvJob', 'CursorJob', 0
        );

        Long durationMs = 5000;
        CursorBatchCsvCallbackCoordinator coordinator = new CursorBatchCsvCallbackCoordinator('cq_session_abc', durationMs);
        coordinator.setJobRecordId(job.Id);

        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();

        CursorBatch_Job__c updated = [SELECT Status__c, Total_Records__c, Cursor_Query_Id__c, Query_Duration_Ms__c FROM CursorBatch_Job__c WHERE Id = :job.Id];
        System.assertEquals('Processing', updated.Status__c);
        System.assertEquals(25, updated.Total_Records__c);
        System.assertEquals('cq_session_abc', updated.Cursor_Query_Id__c);
        System.assertEquals(durationMs, updated.Query_Duration_Ms__c,
            'Query duration should be set from the CSV callback');
    }

    @IsTest
    static void execute_zeroRows_completesJob() {
        CursorBatchTestUtils.CsvMiddlewareMock mock = new CursorBatchTestUtils.CsvMiddlewareMock()
            .withRowCount(0);
        Test.setMock(HttpCalloutMock.class, mock);

        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestCsvJob', 5, 10);
        config.Processing_Type__c = CursorBatchContext.PROCESSING_TYPE_CSV;
        config.Worker_Class__c = 'CursorBatchTestUtils.TestCsvWorker';
        CursorBatchCoordinator.testConfig = config;

        CursorBatch_Job__c job = CursorBatchTestUtils.createPreparingJobRecord(
            'TestCsvJob', 'CursorJob', 0
        );

        CursorBatchCsvCallbackCoordinator coordinator = new CursorBatchCsvCallbackCoordinator('cq_empty', 1000);
        coordinator.setJobRecordId(job.Id);

        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();

        CursorBatch_Job__c updated = [SELECT Status__c, Total_Records__c FROM CursorBatch_Job__c WHERE Id = :job.Id];
        System.assertEquals('Completed', updated.Status__c);
        System.assertEquals(0, updated.Total_Records__c);
    }

    @IsTest
    static void buildQuery_returnsNull() {
        CursorBatchCsvCallbackCoordinator coordinator = new CursorBatchCsvCallbackCoordinator('cq_x', 0);
        System.assertEquals(null, coordinator.buildQuery());
    }

    @IsTest
    static void triggerHandler_routesCsvReady() {
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig('TestCsvJob', 5, 10);
        config.Processing_Type__c = CursorBatchContext.PROCESSING_TYPE_CSV;
        config.Worker_Class__c = 'CursorBatchTestUtils.TestCsvWorker';
        CursorBatchCoordinator.testConfig = config;

        CursorBatch_Job__c job = CursorBatchTestUtils.createPreparingJobRecord(
            'TestCsvJob', 'CursorJob', 0
        );
        job.Status__c = 'Extracting File';
        job.Cursor_Query_Id__c = 'cq_session_xyz';
        update job;

        CursorBatch_Coordinator__e evt = new CursorBatch_Coordinator__e(
            Coordinator_Class__c = 'CSV_Ready',
            Job_Name__c = 'cq_session_xyz',
            Job_Record_Id__c = String.valueOf(job.Id)
        );

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        Test.startTest();
        handler.handle(new List<CursorBatch_Coordinator__e>{ evt });
        Test.stopTest();
    }

    @IsTest
    static void triggerHandler_routesCsvError() {
        CursorBatch_Job__c job = CursorBatchTestUtils.createPreparingJobRecord(
            'TestCsvJob', 'CursorJob', 0
        );

        CursorBatch_Coordinator__e evt = new CursorBatch_Coordinator__e(
            Coordinator_Class__c = 'CSV_Error',
            Job_Name__c = 'File parsing failed',
            Job_Record_Id__c = String.valueOf(job.Id)
        );

        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();

        Test.startTest();
        handler.handle(new List<CursorBatch_Coordinator__e>{ evt });
        Test.stopTest();

        CursorBatch_Job__c updated = [SELECT Status__c, Error_Message__c FROM CursorBatch_Job__c WHERE Id = :job.Id];
        System.assertEquals('Failed', updated.Status__c);
        System.assert(updated.Error_Message__c.contains('File parsing failed'));
    }
}
