/**
 * @description Interface for metadata-driven query building in the CursorBatchFramework.
 *              Implement this interface on selector classes to enable CursorJob configuration.
 *              The buildQuery method receives a method name from CursorBatch_Config__mdt and
 *              routes to the appropriate query builder method via a switch statement.
 * 
 * Example implementation:
 *      public class DealsSelector implements ICursorBatchQueryBuilder {
 *          public String buildQuery(String methodName) {
 *              switch on methodName {
 *                  when 'buildQueryForBillingFullDatabase' {
 *                      return buildQueryForBillingFullDatabase();
 *                  }
 *                  when else {
 *                      return null;
 *                  }
 *              }
 *          }
 *      }
 * 
 * @group CursorBatchFramework
 * @see CursorJob
 */
public interface ICursorBatchQueryBuilder {
    
    /**
     * @description Routes a method name to the appropriate query builder method.
     *              Called by CursorJob with the Query_Builder_Method__c value from config.
     * @param methodName The name of the query builder method to invoke
     * @return SOQL query string with inlined values (no bind variables) for Database.Cursor,
     *         or null if the method name is not recognized
     */
    String buildQuery(String methodName);
}
