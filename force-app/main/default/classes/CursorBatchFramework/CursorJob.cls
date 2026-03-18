/**
 * @description Metadata-driven coordinator for the CursorBatchFramework. Reads job configuration
 *              from CursorBatch_Config__mdt to determine query builder, worker class, and other
 *              settings. Eliminates the need for custom coordinator classes in most cases.
 * 
 * Usage:
 *      // Run immediately
 *      CursorJob.run('Five9 Delete Batch');
 *      
 *      // Run with delay
 *      CursorJob.runWithDelay('Lead Routing Batch', 1);
 * 
 * Configuration (CursorBatch_Config__mdt):
 *      MasterLabel: Five9 Delete Batch
 *      Query_Builder_Class__c: CampaignMembersSelector
 *      Query_Builder_Method__c: buildScheduledDeleteMembersQuery
 *      Worker_Class__c: Five9DeleteWorker
 *      Logger_Tag__c: Five9 Sync (optional)
 * 
 * @group CursorBatchFramework
 * @see ICursorBatchQueryBuilder
 * @see CursorBatchCoordinator
 */
public without sharing class CursorJob extends CursorBatchCoordinator {
    
    private CursorBatch_Config__mdt config;
    private String queryBuilderClass;
    private String queryBuilderMethod;
    private String workerClass;
    
    /**
     * @description No-arg constructor for reflection-based instantiation.
     *              Config must be loaded via initializeFromConfig() before use.
     */
    public CursorJob() {
        super();
    }
    
    /**
     * @description Constructs a CursorJob for the specified job name. Loads configuration
     *              from CursorBatch_Config__mdt and sets up the logger.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     */
    public CursorJob(String jobName) {
        super(jobName);
        loadConfig(jobName);
        setLogger(CursorBatchLogger.resolveLogger(config?.Logger_Tag__c));
    }
    
    /**
     * @description Constructs a CursorJob with runtime metadata. The metadata JSON is
     *              persisted on the job record and made available to query builders and workers.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param metadataJson Serialized JSON string of invocation parameters (e.g., record IDs)
     */
    public CursorJob(String jobName, String metadataJson) {
        this(jobName);
        setMetadata(metadataJson);
    }
    
    /**
     * @description Runs the specified job immediately.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     */
    public static void run(String jobName) {
        new CursorJob(jobName).submit();
    }
    
    /**
     * @description Runs the specified job immediately with runtime metadata.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param metadataJson Serialized JSON string of invocation parameters (e.g., record IDs)
     */
    public static void run(String jobName, String metadataJson) {
        new CursorJob(jobName, metadataJson).submit();
    }
    
    /**
     * @description Runs the specified job with a delay.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param delayMinutes Number of minutes to delay before execution (1-10)
     */
    public static void runWithDelay(String jobName, Integer delayMinutes) {
        new CursorJob(jobName).submitWithDelay(delayMinutes);
    }
    
    /**
     * @description Runs the specified job with a delay and runtime metadata.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param delayMinutes Number of minutes to delay before execution (1-10)
     * @param metadataJson Serialized JSON string of invocation parameters (e.g., record IDs)
     */
    public static void runWithDelay(String jobName, Integer delayMinutes, String metadataJson) {
        new CursorJob(jobName, metadataJson).submitWithDelay(delayMinutes);
    }
    
    /**
     * @description Loads configuration from CursorBatch_Config__mdt for the job.
     * @param jobName Job name to look up
     */
    private void loadConfig(String jobName) {
        config = getConfig(jobName);
        if (config != null) {
            queryBuilderClass = config.Query_Builder_Class__c;
            queryBuilderMethod = config.Query_Builder_Method__c;
            workerClass = config.Worker_Class__c;
        }
    }
    
    /**
     * @description Initializes the job name after reflection-based instantiation.
     *              Overrides parent to also load config.
     * @param jobName Job identifier from the job record
     */
    public override void initializeJobName(String jobName) {
        super.initializeJobName(jobName);
        loadConfig(jobName);
        setLogger(CursorBatchLogger.resolveLogger(config?.Logger_Tag__c));
    }
    
    /**
     * @description Builds the SOQL query by delegating to the configured query builder class.
     *              Instantiates the query builder via reflection and calls buildQuery(methodName).
     * @return Complete SOQL query string
     * @throws CursorBatchException When query builder class is not configured or not found
     */
    public override String buildQuery() {
        if (String.isBlank(queryBuilderClass) || String.isBlank(queryBuilderMethod)) {
            throw new CursorBatchException(
                'CursorJob requires Query_Builder_Class__c and Query_Builder_Method__c in config for job: ' + jobName
            );
        }
        
        try {
            Type builderType = Type.forName(queryBuilderClass);
            if (builderType == null) {
                throw new CursorBatchException('Query builder class not found: ' + queryBuilderClass);
            }
            
            Object instance = builderType.newInstance();
            
            String query;
            if (instance instanceof ICursorBatchMetadataQueryBuilder) {
                query = ((ICursorBatchMetadataQueryBuilder) instance).buildQuery(queryBuilderMethod, metadataJson);
            } else if (instance instanceof ICursorBatchQueryBuilder) {
                query = ((ICursorBatchQueryBuilder) instance).buildQuery(queryBuilderMethod);
            } else {
                throw new CursorBatchException(
                    'Query builder class ' + queryBuilderClass + ' must implement ICursorBatchQueryBuilder or ICursorBatchMetadataQueryBuilder'
                );
            }
            
            if (String.isBlank(query)) {
                throw new CursorBatchException(
                    'Query builder ' + queryBuilderClass + '.buildQuery("' + queryBuilderMethod + '") returned null or empty'
                );
            }
            
            return query;
            
        } catch (CursorBatchException e) {
            throw e;
        } catch (Exception e) {
            throw new CursorBatchException(
                'Error invoking query builder ' + queryBuilderClass + ': ' + e.getMessage()
            );
        }
    }
    
    /**
     * @description Returns the worker class name from configuration.
     * @return Fully qualified API name of the worker class
     * @throws CursorBatchException When worker class is not configured
     */
    public override String getWorkerClassName() {
        if (String.isBlank(workerClass)) {
            throw new CursorBatchException(
                'CursorJob requires Worker_Class__c in config for job: ' + jobName
            );
        }
        return workerClass;
    }
    
    /**
     * @description Called when coordinator completes worker fanout. Logs generic completion message.
     */
    public override void onComplete() {
        super.onComplete();
        logger.logInfo('[' + jobName + '] completed worker fanout');
    }
    
}
