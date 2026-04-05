@IsTest
private class CsvCursorClientTest {

    private class InitMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('/init') && req.getMethod() == 'POST') {
                res.setStatusCode(202);
                res.setBody('{"csvQueryId":"cq_abc123","status":"preparing","ttlSeconds":900,"expiresAt":"2026-03-18T15:15:00Z"}');
            } else if (req.getEndpoint().contains('/status') && req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"csvQueryId":"cq_abc123","status":"ready","rowCount":100,"headers":["Id","Name"],"columnTypes":["VARCHAR","VARCHAR"],"ttlSeconds":900,"expiresAt":"2026-03-18T15:15:00Z"}');
            } else if (req.getEndpoint().contains('/rows') && req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"csvQueryId":"cq_abc123","start":0,"count":2,"rows":[{"Id":"001a","Name":"Acme"},{"Id":"001b","Name":"Beta"}],"hasMore":true,"totalRows":100}');
            } else if (req.getEndpoint().contains('/meta') && req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"csvQueryId":"cq_abc123","status":"ready","rowCount":100,"headers":["Id","Name"],"columnTypes":["VARCHAR","VARCHAR"],"ttlSeconds":900}');
            } else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(204);
                res.setBody('');
            } else {
                res.setStatusCode(404);
                res.setBody('{"code":"NOT_FOUND","message":"Not found"}');
            }
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"code":"INTERNAL_ERROR","message":"Something went wrong"}');
            return res;
        }
    }

    @IsTest
    static void testInitSession() {
        Test.setMock(HttpCalloutMock.class, new InitMock());

        Test.startTest();
        CsvCursorClient.InitResult result = CsvCursorClient.initSession('068XXXXXXXXXXXX');
        Test.stopTest();

        Assert.areEqual('cq_abc123', result.csvQueryId);
        Assert.areEqual('preparing', result.status);
        Assert.areEqual(900, result.ttlSeconds);
    }

    @IsTest
    static void testGetStatusReady() {
        Test.setMock(HttpCalloutMock.class, new InitMock());

        Test.startTest();
        CsvCursorClient.StatusResult result = CsvCursorClient.getStatus('cq_abc123');
        Test.stopTest();

        Assert.areEqual('cq_abc123', result.csvQueryId);
        Assert.areEqual('ready', result.status);
        Assert.areEqual(100, result.rowCount);
        Assert.areEqual(2, result.headers.size());
        Assert.areEqual('Id', result.headers[0]);
    }

    @IsTest
    static void testGetRows() {
        Test.setMock(HttpCalloutMock.class, new InitMock());

        Test.startTest();
        CsvCursorClient.RowResult result = CsvCursorClient.getRows('cq_abc123', 0, 2);
        Test.stopTest();

        Assert.areEqual('cq_abc123', result.csvQueryId);
        Assert.areEqual(0, result.start);
        Assert.areEqual(2, result.count);
        Assert.areEqual(true, result.hasMore);
        Assert.areEqual(100, result.totalRows);
        Assert.areEqual(2, result.rows.size());
        Assert.areEqual('Acme', result.rows[0].get('Name'));
        Assert.areEqual('Beta', result.rows[1].get('Name'));
    }

    @IsTest
    static void testGetMeta() {
        Test.setMock(HttpCalloutMock.class, new InitMock());

        Test.startTest();
        CsvCursorClient.StatusResult result = CsvCursorClient.getMeta('cq_abc123');
        Test.stopTest();

        Assert.areEqual('ready', result.status);
        Assert.areEqual(100, result.rowCount);
    }

    @IsTest
    static void testDeleteSession() {
        Test.setMock(HttpCalloutMock.class, new InitMock());

        Test.startTest();
        CsvCursorClient.deleteSession('cq_abc123');
        Test.stopTest();
        // No exception = success
    }

    @IsTest
    static void testInitSessionError() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        try {
            CsvCursorClient.initSession('068XXXXXXXXXXXX');
            Assert.fail('Should have thrown');
        } catch (CsvCursorClient.CsvCursorException e) {
            Assert.isTrue(e.getMessage().contains('initSession failed'));
            Assert.isTrue(e.getMessage().contains('Something went wrong'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetRowsError() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        try {
            CsvCursorClient.getRows('cq_abc123', 0, 10);
            Assert.fail('Should have thrown');
        } catch (CsvCursorClient.CsvCursorException e) {
            Assert.isTrue(e.getMessage().contains('getRows failed'));
        }
        Test.stopTest();
    }
}
