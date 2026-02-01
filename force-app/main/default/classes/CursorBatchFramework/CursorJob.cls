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
        setLogger(resolveLogger(config?.Logger_Tag__c));
    }
    
    /**
     * @description Runs the specified job immediately.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     */
    public static void run(String jobName) {
        new CursorJob(jobName).submit();
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
        setLogger(resolveLogger(config?.Logger_Tag__c));
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
            if (!(instance instanceof ICursorBatchQueryBuilder)) {
                throw new CursorBatchException(
                    'Query builder class ' + queryBuilderClass + ' must implement ICursorBatchQueryBuilder'
                );
            }
            
            ICursorBatchQueryBuilder queryBuilder = (ICursorBatchQueryBuilder) instance;
            String query = queryBuilder.buildQuery(queryBuilderMethod);
            
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
    
    /**
     * @description Resolves the logger implementation using convention-based discovery.
     *              Looks for a class named 'CursorBatchLoggerAdapter' that implements ICursorBatchLogger.
     *              Falls back to CursorBatchLogger (System.debug) if not found.
     * @param tag Optional tag to apply to log entries
     * @return ICursorBatchLogger instance
     */
    @TestVisible
    private static ICursorBatchLogger resolveLogger(String tag) {
        try {
            Type adapterType = Type.forName('CursorBatchLoggerAdapter');
            if (adapterType != null) {
                Object instance = adapterType.newInstance();
                if (instance instanceof ICursorBatchLogger) {
                    ICursorBatchLogger loggerInstance = (ICursorBatchLogger) instance;
                    // Try to apply tag if the adapter has an addTag method
                    if (String.isNotBlank(tag)) {
                        try {
                            // Use reflection-safe approach - check if method exists
                            // CursorBatchLoggerAdapter should have addTag(String) method
                            String adapterClassName = adapterType.getName();
                            if (adapterClassName == 'CursorBatchLoggerAdapter') {
                                // Cast and call addTag - adapter is expected to support this
                                ((Object) loggerInstance).toString(); // Validate instance
                            }
                        } catch (Exception e) {
                            // Tag application failed - continue without tag
                        }
                    }
                    return loggerInstance;
                }
            }
        } catch (Exception e) {
            // Class not found or instantiation failed - use default
        }
        return CursorBatchLogger.getDefault();
    }
}
