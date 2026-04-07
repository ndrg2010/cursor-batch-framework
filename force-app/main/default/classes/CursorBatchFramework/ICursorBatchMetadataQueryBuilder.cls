/**
 * @description Interface for metadata-aware query building in the CursorBatchFramework.
 *              Implement this interface instead of ICursorBatchQueryBuilder when the query
 *              needs runtime parameters (e.g., a record ID to filter on) passed at job
 *              invocation via CursorJob.run(jobName, metadata).
 *
 *              The metadata parameter is a Map<String, Object> parsed from the JSON
 *              provided at invocation — guaranteed non-null (empty map when no
 *              metadata is provided).
 * 
 * Example implementation:
 *      public class ContactsByAccountSelector implements ICursorBatchMetadataQueryBuilder {
 *          public String buildQuery(String methodName, Map<String, Object> metadata) {
 *              String accountId = (String) metadata.get('accountId');
 *              if (String.isBlank(accountId)) {
 *                  return null;
 *              }
 *              return 'SELECT Id, Name FROM Contact WHERE AccountId = \'' +
 *                     String.escapeSingleQuotes(accountId) + '\'';
 *          }
 *      }
 * 
 * @group CursorBatchFramework
 * @see ICursorBatchQueryBuilder
 * @see CursorJob
 */
public interface ICursorBatchMetadataQueryBuilder {
    
    /**
     * @description Routes a method name to the appropriate query builder method, with
     *              access to runtime metadata from the job invocation.
     * @param methodName The name of the query builder method to invoke
     * @param metadata Runtime parameters from the job invocation (empty map when no
     *                 metadata was provided, never null)
     * @return SOQL query string with inlined values (no bind variables) for Database.Cursor,
     *         or null if the method name is not recognized
     */
    String buildQuery(String methodName, Map<String, Object> metadata);
}
