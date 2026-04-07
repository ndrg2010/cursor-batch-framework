/**
 * @description Abstract base class for CSV-based batch workers. Extends CursorBatchWorker to
 *              provide CSV-specific data fetching via CsvCursorClient while inheriting all
 *              framework features: retry, kill switch, shared state via reducers, per-worker
 *              state, finish() callbacks, and job chaining.
 *
 *              CSV workers override process(List<Map<String, Object>>) instead of
 *              process(List<SObject>). All other overridable methods are identical to SOQL workers.
 *
 * Usage:
 *      public class MyCsvWorker extends CursorBatchCsvWorker {
 *          public override void process(List<Map<String, Object>> rows) {
 *              for (Map<String, Object> row : rows) {
 *                  String email = (String) row.get('Email');
 *                  // ...
 *              }
 *          }
 *      }
 *
 * @group CursorBatchFramework
 * @see CursorBatchWorker
 * @see CsvCursorClient
 */
public abstract without sharing class CursorBatchCsvWorker extends CursorBatchWorker {

    /**
     * @description Satisfies the parent's abstract contract. Never called for CSV workers;
     *              the CSV path uses fetchAndProcess() which routes to the Map-based overload.
     * @param records Not used
     */
    public override void process(List<SObject> records) {
        throw new CursorBatchCoordinator.CursorBatchException(
            'CSV workers must override process(List<Map<String, Object>>)'
        );
    }

    /**
     * @description Processes a page of CSV rows. Override to implement business logic.
     *              Each map is keyed by CSV column header. Throw CursorBatchRetryException
     *              to request retry of the current page.
     * @param rows List of row maps from the CSV file
     * @throws CursorBatchRetryException When the caller wants to retry this page
     */
    public abstract void process(List<Map<String, Object>> rows);

    /**
     * @description Fetches a page of CSV rows from the middleware and delegates to the
     *              Map-based process() method.
     * @return FetchResult indicating how many rows were processed
     */
    protected override FetchResult fetchAndProcess() {
        Integer remainingInRange = ctx.endPosition - ctx.startPosition;
        Integer fetchSize = Math.min(ctx.pageSize, remainingInRange);
        if (fetchSize <= 0) {
            return new FetchResult(0, true);
        }

        List<Map<String, Object>> rows = CsvCursorClient.getRows(
            ctx.cursorQueryId, ctx.startPosition, fetchSize
        );

        if (rows == null || rows.isEmpty()) {
            return new FetchResult(0, true);
        }

        String retryInfo = ctx.retryCount > 0 ? ' (retry ' + ctx.retryCount + ')' : '';
        logger.logInfo('CursorBatchCsvWorker (' + ctx.jobName + ' #' + ctx.workerNum + ') processing ' +
            rows.size() + ' rows at position ' + ctx.startPosition + retryInfo);

        process(rows);
        return new FetchResult(rows.size(), false);
    }

    // ── CSV type converters ─────────────────────────────────────────────
    // The cursor-csv middleware returns all values as JSON strings
    // (DuckDB all_varchar=true). These helpers give subclasses null-safe,
    // blank-safe parsing for the common column types. Defensive instanceof
    // guards handle the case where a future middleware returns typed values.

    /**
     * @description Converts a CSV row value to Decimal. Returns 0 for null or blank.
     * @param value Raw value from the row map
     * @return Parsed Decimal, or 0
     */
    protected Decimal toDecimal(Object value) {
        if (value == null) return 0;
        if (value instanceof Decimal) return (Decimal) value;
        String s = String.valueOf(value);
        return String.isBlank(s) ? 0 : Decimal.valueOf(s.trim());
    }

    /**
     * @description Converts a CSV row value to Integer. Returns 0 for null or blank.
     * @param value Raw value from the row map
     * @return Parsed Integer, or 0
     */
    protected Integer toInteger(Object value) {
        if (value == null) return 0;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Decimal) return ((Decimal) value).intValue();
        String s = String.valueOf(value);
        return String.isBlank(s) ? 0 : Integer.valueOf(s.trim());
    }

    /**
     * @description Converts a CSV row value to Date. Returns null for null or blank.
     *              Expects YYYY-MM-DD format (ISO 8601).
     * @param value Raw value from the row map
     * @return Parsed Date, or null
     */
    protected Date toDate(Object value) {
        if (value == null) return null;
        if (value instanceof Date) return (Date) value;
        String s = String.valueOf(value);
        return String.isBlank(s) ? null : Date.valueOf(s.trim());
    }

    /**
     * @description Converts a CSV row value to Datetime. Returns null for null or blank.
     *              Expects YYYY-MM-DD HH:MM:SS format.
     * @param value Raw value from the row map
     * @return Parsed Datetime, or null
     */
    protected Datetime toDatetime(Object value) {
        if (value == null) return null;
        if (value instanceof Datetime) return (Datetime) value;
        String s = String.valueOf(value);
        return String.isBlank(s) ? null : Datetime.valueOf(s.trim());
    }

    /**
     * @description Converts a CSV row value to Boolean. Returns false for null or blank.
     *              Recognises 'true', '1', and 'yes' (case-insensitive) as true.
     * @param value Raw value from the row map
     * @return Parsed Boolean, or false
     */
    protected Boolean toBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        String s = String.valueOf(value).trim().toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
    }
}
