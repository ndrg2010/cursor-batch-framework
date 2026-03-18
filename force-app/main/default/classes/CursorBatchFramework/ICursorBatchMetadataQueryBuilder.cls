/**
 * @description Interface for metadata-aware query building in the CursorBatchFramework.
 *              Implement this interface instead of ICursorBatchQueryBuilder when the query
 *              needs runtime parameters (e.g., a record ID to filter on) passed at job
 *              invocation via CursorJob.run(jobName, metadataJson).
 * 
 * Example implementation:
 *      public class ContactsByAccountSelector implements ICursorBatchMetadataQueryBuilder {
 *          public String buildQuery(String methodName, String metadataJson) {
 *              if (String.isBlank(metadataJson)) {
 *                  return null; // or a default query
 *              }
 *              Map<String, Object> meta = (Map<String, Object>) JSON.deserializeUntyped(metadataJson);
 *              String accountId = (String) meta.get('accountId');
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
     * @param metadataJson JSON string of runtime parameters passed at invocation, or null
     * @return SOQL query string with inlined values (no bind variables) for Database.Cursor,
     *         or null if the method name is not recognized
     */
    String buildQuery(String methodName, String metadataJson);
}
