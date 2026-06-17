/**
 * @description HTTP client for the CursorBatch CSV middleware (Content Session API v1).
 *              Endpoints follow the /v1/csv/{csvQueryId}/… path convention with per-org
 *              API key authentication via Named Credential "CursorBatch_CSV".
 *
 *              Lifecycle: initSession (POST /init, 202) -> poll or wait for platform event
 *              -> getRowCount (GET /{id}/status) -> getRows (GET /{id}/rows) in pages
 *              -> deleteSession (DELETE /{id}) when done.
 * @group CursorBatchFramework
 * @see CursorBatchCsvCallbackCoordinator
 * @see CursorBatchCsvWorker
 */
public without sharing class CsvCursorClient {

    private static final String NAMED_CREDENTIAL = 'callout:CursorBatch_CSV';

    /**
     * @description Sends the file reference to the middleware for async indexing.
     *              Returns the csvQueryId session handle from the 202 response.
     * @param contentVersionId Salesforce ContentVersion ID for the uploaded CSV/Excel file
     * @param jobRecordId CursorBatch_Job__c record ID for the callback
     * @return csvQueryId session identifier assigned by the middleware
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or non-success responses
     */
    public static String initSession(String contentVersionId, Id jobRecordId) {
        return initSession(contentVersionId, jobRecordId, null, null);
    }

    /**
     * @description Sends the file reference to the middleware for async indexing, with optional
     *              worksheet selection for xls/xlsx files. Returns the csvQueryId session handle
     *              from the 202 response. The worksheet fields are only added to the payload when
     *              provided (CSV files omit them).
     * @param contentVersionId Salesforce ContentVersion ID for the uploaded CSV/Excel file
     * @param jobRecordId CursorBatch_Job__c record ID for the callback
     * @param worksheetLabel Optional worksheet/sheet name to read (xls/xlsx only)
     * @param worksheetPassword Optional password for protected workbooks (xls/xlsx only)
     * @return csvQueryId session identifier assigned by the middleware
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or non-success responses
     */
    public static String initSession(String contentVersionId, Id jobRecordId,
                                     String worksheetLabel, String worksheetPassword) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/init');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        Map<String, String> payload = new Map<String, String>{
            'contentVersionId' => contentVersionId,
            'cursorBatchJobId' => String.valueOf(jobRecordId)
        };
        if (String.isNotBlank(worksheetLabel)) {
            payload.put('worksheetLabel', worksheetLabel);
        }
        if (String.isNotBlank(worksheetPassword)) {
            payload.put('worksheetPassword', worksheetPassword);
        }
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        validateResponse(res, 'initSession');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('csvQueryId');
    }

    /**
     * @description Retrieves the total row count for an indexed CSV session via the status endpoint.
     * @param csvQueryId Session identifier returned by initSession or the middleware callback
     * @return Total number of data rows (excluding header)
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or missing rowCount
     */
    public static Integer getRowCount(String csvQueryId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/' + EncodingUtil.urlEncode(csvQueryId, 'UTF-8') + '/status');
        req.setMethod('GET');
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        validateResponse(res, 'getRowCount');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object rawCount = body.get('rowCount');
        if (rawCount == null) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'CSV middleware getRowCount response missing rowCount field'
            );
        }
        return Integer.valueOf(rawCount);
    }

    /**
     * @description Fetches a page of CSV rows from the middleware. Internally converts the
     *              framework's 0-based offset to the API's 1-based start parameter.
     * @param csvQueryId Session identifier returned by initSession or the middleware callback
     * @param offset Zero-based row offset (converted to 1-based start for the API)
     * @param pageSize Maximum rows to return (max 2000)
     * @return List of row maps keyed by CSV column header
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or non-success responses
     */
    public static List<Map<String, Object>> getRows(String csvQueryId, Integer offset, Integer pageSize) {
        Integer start = offset + 1;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            NAMED_CREDENTIAL + '/' + EncodingUtil.urlEncode(csvQueryId, 'UTF-8') +
            '/rows?start=' + start + '&count=' + pageSize
        );
        req.setMethod('GET');
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);
        validateResponse(res, 'getRows');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> rawRows = (List<Object>) body.get('rows');
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (rawRows != null) {
            for (Object row : rawRows) {
                rows.add((Map<String, Object>) row);
            }
        }
        return rows;
    }

    /**
     * @description Deletes a content session and releases parsed row data on the middleware.
     * @param csvQueryId Session identifier to delete
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors (404 for missing session is still thrown)
     */
    public static void deleteSession(String csvQueryId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/' + EncodingUtil.urlEncode(csvQueryId, 'UTF-8'));
        req.setMethod('DELETE');
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        validateResponse(res, 'deleteSession');
    }

    private static void validateResponse(HttpResponse res, String methodName) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'CSV middleware ' + methodName + ' failed: HTTP ' + res.getStatusCode() + ' \u2014 ' + res.getBody()
            );
        }
    }
}
