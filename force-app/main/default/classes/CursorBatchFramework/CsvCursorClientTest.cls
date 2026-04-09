@IsTest
private class CsvCursorClientTest {

    @IsTest
    static void initSession_returnsCsvQueryId() {
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withInitSuccess());

        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord('CsvTest', 1, 'CursorJob');

        Test.startTest();
        String csvQueryId = CsvCursorClient.initSession('068000000000001', job.Id);
        Test.stopTest();

        System.assertEquals('cq-test-session', csvQueryId, 'Expected csvQueryId from 202 response');
    }

    @IsTest
    static void initSession_throwsOnHttpError() {
        Test.setMock(HttpCalloutMock.class,
            new CursorBatchTestUtils.CsvMiddlewareMock().withError('POST:/init', 500, 'Internal error'));

        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord('CsvTest', 1, 'CursorJob');

        Boolean caught = false;
        Test.startTest();
        try {
            CsvCursorClient.initSession('068000000000001', job.Id);
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            caught = true;
            System.assert(e.getMessage().contains('500'), 'Expected status code in error message');
        }
        Test.stopTest();
        System.assert(caught, 'Expected exception on HTTP error');
    }

    @IsTest
    static void getRowCount_returnsTotal() {
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withRowCount(42));

        Test.startTest();
        Integer count = CsvCursorClient.getRowCount('cq_test123');
        Test.stopTest();

        System.assertEquals(42, count);
    }

    @IsTest
    static void getRows_returnsParsedRows() {
        List<Map<String, Object>> mockRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => 'Alice', 'Email' => 'alice@test.com' },
            new Map<String, Object>{ 'Name' => 'Bob', 'Email' => 'bob@test.com' }
        };
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withRows(mockRows));

        Test.startTest();
        List<Map<String, Object>> rows = CsvCursorClient.getRows('cq_test123', 0, 10);
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Alice', rows[0].get('Name'));
        System.assertEquals('bob@test.com', rows[1].get('Email'));
    }

    @IsTest
    static void getRows_returnsEmptyOnNoRows() {
        List<Map<String, Object>> mockRows = new List<Map<String, Object>>();
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withRows(mockRows));

        Test.startTest();
        List<Map<String, Object>> rows = CsvCursorClient.getRows('cq_test123', 0, 10);
        Test.stopTest();

        System.assert(rows.isEmpty());
    }

    @IsTest
    static void deleteSession_succeeds() {
        Test.setMock(HttpCalloutMock.class, new CursorBatchTestUtils.CsvMiddlewareMock().withDeleteSuccess());

        Test.startTest();
        CsvCursorClient.deleteSession('cq_test123');
        Test.stopTest();
    }

    @IsTest
    static void deleteSession_throwsOnHttpError() {
        Test.setMock(HttpCalloutMock.class,
            new CursorBatchTestUtils.CsvMiddlewareMock().withError('DELETE:/session', 404, 'Session not found'));

        Boolean caught = false;
        Test.startTest();
        try {
            CsvCursorClient.deleteSession('cq_missing');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            caught = true;
            System.assert(e.getMessage().contains('404'), 'Expected status code in error message');
        }
        Test.stopTest();
        System.assert(caught, 'Expected exception on HTTP error');
    }
}
