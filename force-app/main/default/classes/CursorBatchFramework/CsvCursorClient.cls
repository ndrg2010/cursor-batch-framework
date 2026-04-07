/**
 * @description HTTP client for the CursorBatch CSV middleware. Encapsulates the fire-and-callback
 *              protocol: initSession sends the file reference and job ID; the middleware calls back
 *              via CursorBatch_Coordinator__e when indexing is complete. getRowCount and getRows
 *              are used by the callback coordinator and workers respectively.
 *
 *              Requires a Named Credential called "CursorBatch_CSV" pointing at the middleware base URL.
 * @group CursorBatchFramework
 * @see CursorBatchCsvCallbackCoordinator
 * @see CursorBatchCsvWorker
 */
public without sharing class CsvCursorClient {

    private static final String NAMED_CREDENTIAL = 'callout:CursorBatch_CSV';

    /**
     * @description Sends the CSV file reference to the middleware for indexing. The middleware
     *              will publish a CursorBatch_Coordinator__e callback when ready.
     * @param contentVersionId Salesforce ContentVersion ID for the uploaded CSV file
     * @param jobRecordId CursorBatch_Job__c record ID for the callback
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or non-success responses
     */
    public static void initSession(String contentVersionId, Id jobRecordId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/init');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, String>{
            'contentVersionId' => contentVersionId,
            'cursorBatchJobId' => String.valueOf(jobRecordId)
        }));
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        validateResponse(res, 'initSession');
    }

    /**
     * @description Retrieves the total row count for an indexed CSV file.
     * @param csvCursorQuery Session identifier returned by the middleware callback
     * @return Total number of data rows (excluding header)
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or non-success responses
     */
    public static Integer getRowCount(String csvCursorQuery) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/count?cursor=' + EncodingUtil.urlEncode(csvCursorQuery, 'UTF-8'));
        req.setMethod('GET');
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        validateResponse(res, 'getRowCount');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object rawCount = body.get('totalRows');
        if (rawCount == null) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'CSV middleware getRowCount response missing totalRows field'
            );
        }
        return Integer.valueOf(rawCount);
    }

    /**
     * @description Fetches a page of CSV rows from the middleware.
     * @param csvCursorQuery Session identifier returned by the middleware callback
     * @param offset Zero-based row offset
     * @param pageSize Maximum rows to return
     * @return List of row maps keyed by CSV column header
     * @throws CursorBatchCoordinator.CursorBatchException On HTTP errors or non-success responses
     */
    public static List<Map<String, Object>> getRows(String csvCursorQuery, Integer offset, Integer pageSize) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            NAMED_CREDENTIAL + '/rows?cursor=' + EncodingUtil.urlEncode(csvCursorQuery, 'UTF-8') +
            '&offset=' + offset + '&limit=' + pageSize
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

    private static void validateResponse(HttpResponse res, String methodName) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CursorBatchCoordinator.CursorBatchException(
                'CSV middleware ' + methodName + ' failed: HTTP ' + res.getStatusCode() + ' \u2014 ' + res.getBody()
            );
        }
    }
}
