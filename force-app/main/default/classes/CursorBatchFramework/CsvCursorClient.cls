/**
 * @description HTTP client for the CSV Cursor Middleware. Provides methods to initialize
 *              CSV cursor sessions, poll for readiness, fetch paginated rows, retrieve
 *              metadata, and delete sessions.
 *
 *              All callouts use the Named Credential 'CSV_Middleware' which must be
 *              configured with an External Credential providing the X-API-Key header.
 *
 *              Usage in a coordinator's execute():
 *                  CsvCursorClient.InitResult init = CsvCursorClient.initSession(contentVersionId);
 *                  CsvCursorClient.StatusResult status = CsvCursorClient.getStatus(init.csvQueryId);
 *                  if (status.status == 'preparing') {
 *                      throw CursorBatchRetryException.create('CSV still preparing', 1);
 *                  }
 *                  // status.status == 'ready' -- fan out workers using status.rowCount
 *
 *              Usage in a worker's process():
 *                  CsvCursorClient.RowResult page = CsvCursorClient.getRows(csvQueryId, start, count);
 *                  for (Map<String, Object> row : page.rows) { ... }
 *
 *              Usage in a coordinator's finish():
 *                  CsvCursorClient.deleteSession(csvQueryId);
 *
 * @group CursorBatchFramework
 */
public without sharing class CsvCursorClient {

    private static final String NAMED_CREDENTIAL = 'callout:CSV_Middleware';
    private static final String API_PREFIX = '/v1/csv';
    private static final Integer DEFAULT_TIMEOUT_MS = 30000;

    // -- Response wrappers --

    public class InitResult {
        public String csvQueryId;
        public String status;
        public Integer ttlSeconds;
        public String expiresAt;
    }

    public class StatusResult {
        public String csvQueryId;
        public String status;
        public Integer rowCount;
        public List<String> headers;
        public List<String> columnTypes;
        public Integer ttlSeconds;
        public String expiresAt;
        public ErrorDetail error;
    }

    public class RowResult {
        public String csvQueryId;
        public Integer start;
        public Integer count;
        public List<Map<String, Object>> rows;
        public Boolean hasMore;
        public Integer totalRows;
    }

    public class ErrorDetail {
        public String code;
        public String message;
    }

    public class CsvCursorException extends Exception {}

    // -- API methods --

    /**
     * @description Initiates a CSV cursor session. Returns immediately; the middleware
     *              downloads and parses the file in the background.
     * @param contentVersionId The 15/18-char Salesforce ContentVersion ID
     * @return InitResult with csvQueryId and status "preparing"
     */
    public static InitResult initSession(String contentVersionId) {
        HttpRequest req = buildRequest('POST', API_PREFIX + '/init');
        req.setBody(JSON.serialize(new Map<String, String>{
            'contentVersionId' => contentVersionId
        }));
        HttpResponse res = send(req);
        assertStatus(res, 202, 'initSession');
        return (InitResult) JSON.deserialize(res.getBody(), InitResult.class);
    }

    /**
     * @description Polls the status of a CSV cursor session.
     *              Returns "preparing", "ready", or "error".
     * @param csvQueryId The session identifier from initSession()
     * @return StatusResult with current status and metadata when ready
     */
    public static StatusResult getStatus(String csvQueryId) {
        HttpRequest req = buildRequest('GET', API_PREFIX + '/' + csvQueryId + '/status');
        HttpResponse res = send(req);
        assertStatus(res, 200, 'getStatus');
        return (StatusResult) JSON.deserialize(res.getBody(), StatusResult.class);
    }

    /**
     * @description Fetches a page of rows from a ready session.
     * @param csvQueryId The session identifier
     * @param start Zero-based row offset
     * @param count Number of rows to fetch (max 2000)
     * @return RowResult with rows as List<Map<String, Object>>
     */
    public static RowResult getRows(String csvQueryId, Integer start, Integer count) {
        String path = API_PREFIX + '/' + csvQueryId + '/rows?start=' + start + '&count=' + count;
        HttpRequest req = buildRequest('GET', path);
        HttpResponse res = send(req);
        assertStatus(res, 200, 'getRows');

        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        RowResult result = new RowResult();
        result.csvQueryId = (String) raw.get('csvQueryId');
        result.start = Integer.valueOf(raw.get('start'));
        result.count = Integer.valueOf(raw.get('count'));
        result.hasMore = (Boolean) raw.get('hasMore');
        result.totalRows = Integer.valueOf(raw.get('totalRows'));

        result.rows = new List<Map<String, Object>>();
        List<Object> rawRows = (List<Object>) raw.get('rows');
        if (rawRows != null) {
            for (Object rowObj : rawRows) {
                result.rows.add((Map<String, Object>) rowObj);
            }
        }

        return result;
    }

    /**
     * @description Retrieves session metadata (headers, types, row count).
     *              Only valid when session status is "ready".
     * @param csvQueryId The session identifier
     * @return StatusResult with metadata fields
     */
    public static StatusResult getMeta(String csvQueryId) {
        HttpRequest req = buildRequest('GET', API_PREFIX + '/' + csvQueryId + '/meta');
        HttpResponse res = send(req);
        assertStatus(res, 200, 'getMeta');
        return (StatusResult) JSON.deserialize(res.getBody(), StatusResult.class);
    }

    /**
     * @description Deletes a CSV cursor session, releasing middleware resources immediately.
     *              Call from the coordinator's finish() callback.
     * @param csvQueryId The session identifier to delete
     */
    public static void deleteSession(String csvQueryId) {
        HttpRequest req = buildRequest('DELETE', API_PREFIX + '/' + csvQueryId);
        HttpResponse res = send(req);
        if (res.getStatusCode() != 204 && res.getStatusCode() != 404) {
            throw new CsvCursorException(
                'deleteSession failed: HTTP ' + res.getStatusCode() + ' ' + res.getBody()
            );
        }
    }

    // -- Internal helpers --

    private static HttpRequest buildRequest(String method, String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + path);
        req.setMethod(method);
        req.setTimeout(DEFAULT_TIMEOUT_MS);
        if (method == 'POST') {
            req.setHeader('Content-Type', 'application/json');
        }
        return req;
    }

    private static HttpResponse send(HttpRequest req) {
        return new Http().send(req);
    }

    private static void assertStatus(HttpResponse res, Integer expected, String operation) {
        if (res.getStatusCode() != expected) {
            String body = res.getBody();
            String errorMsg = operation + ' failed: HTTP ' + res.getStatusCode();
            if (String.isNotBlank(body)) {
                try {
                    Map<String, Object> err = (Map<String, Object>) JSON.deserializeUntyped(body);
                    errorMsg += ' - ' + err.get('message');
                } catch (Exception e) {
                    errorMsg += ' - ' + body;
                }
            }
            throw new CsvCursorException(errorMsg);
        }
    }
}
