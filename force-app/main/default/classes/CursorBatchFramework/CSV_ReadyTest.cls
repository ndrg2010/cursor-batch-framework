@IsTest
private class CSV_ReadyTest {

    private static final String MOCK_CSV_QUERY_ID = 'cq_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4';
    private static final String MOCK_CONTENT_VERSION_ID = '068XXXXXXXXXXXX';

    private class ReadyStatusMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"csvQueryId":"' + MOCK_CSV_QUERY_ID + '",' +
                '"status":"ready",' +
                '"rowCount":500,' +
                '"headers":["Id","Name","Amount"],' +
                '"columnTypes":["VARCHAR","VARCHAR","VARCHAR"],' +
                '"ttlSeconds":900,' +
                '"expiresAt":"2026-04-05T12:00:00Z"}'
            );
            return res;
        }
    }

    private class ErrorStatusMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"csvQueryId":"' + MOCK_CSV_QUERY_ID + '",' +
                '"status":"error",' +
                '"error":{"code":"DOWNLOAD_FAILED","message":"ContentVersion not found"}}'
            );
            return res;
        }
    }

    private class PreparingStatusMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"csvQueryId":"' + MOCK_CSV_QUERY_ID + '",' +
                '"status":"preparing"}'
            );
            return res;
        }
    }

    private class HttpErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"code":"INTERNAL_ERROR","message":"Server error"}');
            return res;
        }
    }

    @IsTest
    static void testCallableSetsPeFields() {
        CSV_Ready handler = new CSV_Ready();
        handler.call('handlePlatformEvent', new Map<String, Object>{
            'Job_Record_Id__c' => MOCK_CSV_QUERY_ID,
            'Job_Name__c' => MOCK_CONTENT_VERSION_ID,
            'Coordinator_Class__c' => 'CSV_Ready'
        });

        Assert.areEqual(MOCK_CSV_QUERY_ID, handler.getCsvQueryId());
        Assert.areEqual(MOCK_CONTENT_VERSION_ID, handler.getContentVersionId());
    }

    @IsTest
    static void testCallableIgnoresUnknownAction() {
        CSV_Ready handler = new CSV_Ready();
        handler.call('unknownAction', new Map<String, Object>{
            'Job_Record_Id__c' => MOCK_CSV_QUERY_ID
        });

        Assert.isNull(handler.getCsvQueryId());
    }

    @IsTest
    static void testExecuteWithReadySession() {
        Test.setMock(HttpCalloutMock.class, new ReadyStatusMock());

        CSV_Ready handler = new CSV_Ready();
        handler.csvQueryId = MOCK_CSV_QUERY_ID;
        handler.contentVersionId = MOCK_CONTENT_VERSION_ID;

        Test.startTest();
        handler.execute(null);
        Test.stopTest();
    }

    @IsTest
    static void testExecuteWithErrorSession() {
        Test.setMock(HttpCalloutMock.class, new ErrorStatusMock());

        CSV_Ready handler = new CSV_Ready();
        handler.csvQueryId = MOCK_CSV_QUERY_ID;
        handler.contentVersionId = MOCK_CONTENT_VERSION_ID;

        Test.startTest();
        handler.execute(null);
        Test.stopTest();
    }

    @IsTest
    static void testExecuteWithPreparingSession() {
        Test.setMock(HttpCalloutMock.class, new PreparingStatusMock());

        CSV_Ready handler = new CSV_Ready();
        handler.csvQueryId = MOCK_CSV_QUERY_ID;
        handler.contentVersionId = MOCK_CONTENT_VERSION_ID;

        Test.startTest();
        handler.execute(null);
        Test.stopTest();
    }

    @IsTest
    static void testExecuteWithMissingCsvQueryId() {
        CSV_Ready handler = new CSV_Ready();

        Test.startTest();
        handler.execute(null);
        Test.stopTest();
    }

    @IsTest
    static void testExecuteWithHttpError() {
        Test.setMock(HttpCalloutMock.class, new HttpErrorMock());

        CSV_Ready handler = new CSV_Ready();
        handler.csvQueryId = MOCK_CSV_QUERY_ID;
        handler.contentVersionId = MOCK_CONTENT_VERSION_ID;

        Test.startTest();
        handler.execute(null);
        Test.stopTest();
    }
}
