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
     * @description Constructs a CursorJob with runtime metadata. The metadata is serialized
     *              internally, persisted on the job record, and made available to query builders
     *              and workers.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param metadata Runtime parameters (e.g., record IDs) — serialized to JSON internally
     */
    public CursorJob(String jobName, Map<String, Object> metadata) {
        this(jobName);
        setMetadata(metadata != null ? JSON.serialize(metadata) : null);
    }
    
    /**
     * @description Runs the specified job immediately.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @return The CursorBatch_Job__c record Id, or null if the job was already running
     */
    public static Id run(String jobName) {
        return new CursorJob(jobName).submit();
    }
    
    /**
     * @description Runs the specified job immediately with runtime metadata.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param metadata Runtime parameters (e.g., record IDs) — serialized to JSON internally
     * @return The CursorBatch_Job__c record Id, or null if the job was already running
     */
    public static Id run(String jobName, Map<String, Object> metadata) {
        return new CursorJob(jobName, metadata).submit();
    }
    
    /**
     * @description Runs the specified job with a delay.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param delayMinutes Number of minutes to delay before execution (1-10)
     * @return The CursorBatch_Job__c record Id, or null if the job was already running
     */
    public static Id runWithDelay(String jobName, Integer delayMinutes) {
        return new CursorJob(jobName).submitWithDelay(delayMinutes);
    }
    
    /**
     * @description Runs the specified job with a delay and runtime metadata.
     * @param jobName Job identifier matching CursorBatch_Config__mdt.MasterLabel
     * @param delayMinutes Number of minutes to delay before execution (1-10)
     * @param metadata Runtime parameters (e.g., record IDs) — serialized to JSON internally
     * @return The CursorBatch_Job__c record Id, or null if the job was already running
     */
    public static Id runWithDelay(String jobName, Integer delayMinutes, Map<String, Object> metadata) {
        return new CursorJob(jobName, metadata).submitWithDelay(delayMinutes);
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
     * @description Executes the coordinator. For SOQL jobs, delegates to the standard cursor-based
     *              path. For CSV jobs, initiates a middleware session and returns — the middleware
     *              calls back via CursorBatch_Coordinator__e when the file is indexed.
     * @param ctx Queueable context
     */
    public override void execute(QueueableContext ctx) {
        if (config == null) {
            loadConfig(jobName);
        }
        String pType = config != null ? config.Processing_Type__c : null;
        if (pType == CursorBatchContext.PROCESSING_TYPE_CSV) {
            executeCsvInit(ctx);
        } else {
            super.execute(ctx);
        }
    }
    
    /**
     * @description Initiates a CSV middleware session. Extracts the contentVersionId from
     *              metadataJson and sends it to the middleware for indexing. The job stays
     *              in Preparing status until the middleware calls back.
     * @param ctx Queueable context
     */
    private void executeCsvInit(QueueableContext ctx) {
        try {
            CursorBatch_Job__c jobRecord = CursorBatchSelector.getJobById(jobRecordId);
            if (jobRecord == null) {
                throw new CursorBatchException('Job record not found: ' + jobRecordId);
            }
            
            if (String.isBlank(this.metadataJson) && String.isNotBlank(jobRecord.Metadata_JSON__c)) {
                this.metadataJson = jobRecord.Metadata_JSON__c;
            }
            
            if (String.isBlank(this.metadataJson)) {
                throw new CursorBatchException(
                    'CSV jobs require metadataJson with contentVersionId for job: ' + jobName
                );
            }
            
            Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(this.metadataJson);
            String contentVersionId = (String) metadata.get('contentVersionId');
            if (String.isBlank(contentVersionId)) {
                throw new CursorBatchException(
                    'metadataJson must include contentVersionId for CSV job: ' + jobName
                );
            }
            
            logger.logInfo('CursorJob CSV init for ' + jobName + ': contentVersionId=' + contentVersionId);
            
            attachFinalizer(jobRecord.Id, null);
            
            CsvCursorClient.initSession(contentVersionId, jobRecord.Id);
            
            logger.logInfo('CursorJob CSV middleware session initiated for ' + jobName +
                ', awaiting callback');
                
        } catch (Exception e) {
            logger.logException('CursorJob CSV init error for ' + jobName, e);
            throw e;
        }
    }
    
    /**
     * @description Builds the SOQL query by delegating to the configured query builder class.
     *              Returns null for CSV jobs (no SOQL needed).
     * @return Complete SOQL query string, or null for CSV jobs
     * @throws CursorBatchException When query builder class is not configured for SOQL jobs
     */
    public override String buildQuery() {
        if (String.isBlank(queryBuilderClass) || String.isBlank(queryBuilderMethod)) {
            if (config != null && config.Processing_Type__c == CursorBatchContext.PROCESSING_TYPE_CSV) {
                return null;
            }
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
                Map<String, Object> metadata = String.isBlank(metadataJson)
                    ? new Map<String, Object>()
                    : (Map<String, Object>) JSON.deserializeUntyped(metadataJson);
                query = ((ICursorBatchMetadataQueryBuilder) instance).buildQuery(queryBuilderMethod, metadata);
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
