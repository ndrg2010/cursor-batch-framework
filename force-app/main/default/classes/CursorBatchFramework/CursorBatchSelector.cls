/**
 * @description Centralized selector class for all SOQL queries in the CursorBatch framework.
 *              Provides reusable query methods following Salesforce best practices.
 * @group CursorBatchFramework
 */
public without sharing class CursorBatchSelector {
    
    /**
     * @description Queries CursorBatch_Job__c record by Id with all standard fields.
     * @param jobId The Id of the job record
     * @return CursorBatch_Job__c record or null if not found
     */
    public static CursorBatch_Job__c getJobById(Id jobId) {
        if (jobId == null) {
            return null;
        }
        
        List<CursorBatch_Job__c> jobs = getJobsWithAllFields(
            'Id = :jobId', 
            new Map<String, Object>{ 'jobId' => jobId },
            1
        );
        return jobs.isEmpty() ? null : jobs[0];
    }
    
    /**
     * @description Queries CursorBatch_Job__c records by Ids.
     *              Used for completion handler to update worker counts.
     * @param jobIds Set of job record Ids
     * @return Map of Id to CursorBatch_Job__c records
     */
    public static Map<Id, CursorBatch_Job__c> getJobsByIds(Set<Id> jobIds) {
        if (jobIds == null || jobIds.isEmpty()) {
            return new Map<Id, CursorBatch_Job__c>();
        }
        
        List<CursorBatch_Job__c> jobs = [
            SELECT Id, Job_Name__c, Total_Workers__c, Completed_Workers__c, Failed_Workers__c,
                   Status__c, Coordinator_Class__c, Error_Message__c
            FROM CursorBatch_Job__c
            WHERE Id IN :jobIds
        ];
        return new Map<Id, CursorBatch_Job__c>(jobs);
    }
    
    /**
     * @description Queries CursorBatch_Job__c records that are currently running (Preparing or Processing).
     *              Used to check if a job is already running before starting a new one.
     * @param jobName The job name to search for
     * @return List of running CursorBatch_Job__c records
     */
    public static List<CursorBatch_Job__c> getRunningJobsByName(String jobName) {
        if (String.isBlank(jobName)) {
            return new List<CursorBatch_Job__c>();
        }
        
        return getJobsWithAllFields(
            'Job_Name__c = :jobName AND Status__c IN :statuses',
            new Map<String, Object>{ 'jobName' => jobName, 'statuses' => new List<String>{ 'Preparing', 'Processing' } },
            null
        );
    }
    
    /**
     * @description Queries CursorBatch_Config__mdt by MasterLabel (job name).
     *              Returns only active configurations.
     * @param jobName The job name (MasterLabel) to search for
     * @return CursorBatch_Config__mdt record or null if not found
     */
    public static CursorBatch_Config__mdt getConfigByJobName(String jobName) {
        if (String.isBlank(jobName)) {
            return null;
        }
        
        List<CursorBatch_Config__mdt> configs = [
            SELECT MasterLabel, Parallel_Count__c, Page_Size__c, Coordinator_Max_Retries__c, 
                   Worker_Max_Retries__c, Worker_Retry_Delay__c, Active__c
            FROM CursorBatch_Config__mdt
            WHERE MasterLabel = :jobName
            AND Active__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }
    
    /**
     * @description Queries AsyncApexJob records that are currently running for a given class.
     *              Used to check if a coordinator job is already running.
     * @param className The fully qualified ApexClass name
     * @return List of running AsyncApexJob records
     */
    public static List<AsyncApexJob> getRunningAsyncJobsByClass(String className) {
        if (String.isBlank(className)) {
            return new List<AsyncApexJob>();
        }
        
        return [
            SELECT Id 
            FROM AsyncApexJob 
            WHERE ApexClass.Name = :className 
            AND Status IN ('Queued', 'Holding', 'Preparing', 'Processing')
            LIMIT 1
        ];
    }
    
    // ============== Private Helpers ==============
    
    /**
     * @description Builds and executes a dynamic query for CursorBatch_Job__c with all standard fields.
     * @param whereClause WHERE clause condition (without WHERE keyword)
     * @param bindVars Map of bind variable names to values
     * @param queryLimit Optional LIMIT value (null for no limit)
     * @return List of CursorBatch_Job__c records
     */
    private static List<CursorBatch_Job__c> getJobsWithAllFields(String whereClause, Map<String, Object> bindVars, Integer queryLimit) {
        String query = 'SELECT Id, Job_Name__c, Retry_Count__c, Status__c, Query__c, ' +
                       'Total_Workers__c, Total_Records__c, Completed_Workers__c, ' +
                       'Failed_Workers__c, Started_At__c, Coordinator_Class__c, ' +
                       'Cursor_Query_Id__c, Query_Duration_Ms__c, Completed_At__c, Error_Message__c ' +
                       'FROM CursorBatch_Job__c ' +
                       'WHERE ' + whereClause;
        
        if (queryLimit != null) {
            query += ' LIMIT ' + queryLimit;
        }
        
        return Database.queryWithBinds(query, bindVars, AccessLevel.SYSTEM_MODE);
    }
}