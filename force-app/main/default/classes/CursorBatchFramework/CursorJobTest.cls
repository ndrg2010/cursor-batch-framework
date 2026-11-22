/**
 * @description Unit tests for CursorJob metadata-driven coordinator class.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorJobTest {
    
    // Static tracking variables for inner class test helpers (inner classes cannot have static members)
    @TestVisible private static Boolean workerFinishCalled = false;
    @TestVisible private static CursorBatch_Job__c workerFinishJobRecord = null;
    @TestVisible private static Boolean chainableCallInvoked = false;
    @TestVisible private static String chainableCalledMethod = null;
    @TestVisible private static Map<String, Object> chainableCalledArgs = null;
    @TestVisible private static String coordinatorFinishMetadata = null;
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(100);
    }
    
    /**
     * @description Resets all test tracking variables.
     */
    private static void resetTestState() {
        workerFinishCalled = false;
        workerFinishJobRecord = null;
        chainableCallInvoked = false;
        chainableCalledMethod = null;
        chainableCalledArgs = null;
        coordinatorFinishMetadata = null;
    }
    
    // ============================================
    // Test Query Builder for CursorJob tests
    // ============================================
    
    /**
     * @description Test implementation of ICursorBatchQueryBuilder for testing.
     */
    public class TestQueryBuilder implements ICursorBatchQueryBuilder {
        public String buildQuery(String methodName) {
            switch on methodName {
                when 'getAccountsQuery' {
                    return CursorBatchTestUtils.DEFAULT_TEST_QUERY;
                }
                when 'getEmptyQuery' {
                    return 'SELECT Id FROM Account WHERE Name = \'NonExistentAccount12345\'';
                }
                when 'getInvalidQuery' {
                    return 'SELECT InvalidField FROM Account';
                }
                when else {
                    return null;
                }
            }
        }
    }
    
    /**
     * @description Test worker that tracks finish() calls.
     */
    public class TestCursorJobWorker extends CursorBatchWorker {
        
        public override void process(List<SObject> records) {
            // No-op for testing
        }
        
        public override void finish(CursorBatch_Job__c jobRecord) {
            CursorJobTest.workerFinishCalled = true;
            CursorJobTest.workerFinishJobRecord = jobRecord;
        }
    }
    
    /**
     * @description Test class implementing Callable for chaining tests.
     */
    public class TestChainableJob implements Callable {
        
        public Object call(String action, Map<String, Object> args) {
            CursorJobTest.chainableCallInvoked = true;
            CursorJobTest.chainableCalledMethod = action;
            CursorJobTest.chainableCalledArgs = args;
            return null;
        }
    }
    
    /**
     * @description Test coordinator that captures this.metadataJson in finish()
     *              to verify invokeFinishCallback() restores metadata on the instance.
     */
    public class TestMetadataAwareCoordinator extends CursorBatchCoordinator {
        
        public TestMetadataAwareCoordinator() {
            super();
        }
        
        public override String buildQuery() {
            return CursorBatchTestUtils.DEFAULT_TEST_QUERY;
        }
        
        public override String getWorkerClassName() {
            return 'CursorJobTest.TestCursorJobWorker';
        }
        
        public override void finish(CursorBatch_Job__c jobRecord) {
            CursorJobTest.coordinatorFinishMetadata = this.metadataJson;
        }
    }
    
    /**
     * @description Test implementation of ICursorBatchMetadataQueryBuilder for metadata-aware query building.
     */
    public class TestMetadataQueryBuilder implements ICursorBatchMetadataQueryBuilder {
        public String buildQuery(String methodName, Map<String, Object> metadata) {
            switch on methodName {
                when 'getAccountsByIdQuery' {
                    String accountId = (String) metadata.get('accountId');
                    if (String.isBlank(accountId)) {
                        return CursorBatchTestUtils.DEFAULT_TEST_QUERY;
                    }
                    return 'SELECT Id, Name FROM Account WHERE Id = \'' +
                           String.escapeSingleQuotes(accountId) + '\'';
                }
                when 'getAccountsOrNullWhenFailQuery' {
                    return metadata.get('fail') == true ? null : CursorBatchTestUtils.DEFAULT_TEST_QUERY;
                }
                when else {
                    return null;
                }
            }
        }
    }
    
    // ============================================
    // Helper Methods
    // ============================================
    
    private static CursorBatch_Config__mdt createCursorJobConfig(
        String jobName,
        String queryBuilderClass,
        String queryBuilderMethod,
        String workerClass
    ) {
        return createCursorJobConfig(jobName, queryBuilderClass, queryBuilderMethod, workerClass, null, null, null, null);
    }
    
    private static CursorBatch_Config__mdt createCursorJobConfig(
        String jobName,
        String queryBuilderClass,
        String queryBuilderMethod,
        String workerClass,
        String chainToClass,
        String chainToMethod,
        String loggerTag
    ) {
        return createCursorJobConfig(
            jobName,
            queryBuilderClass,
            queryBuilderMethod,
            workerClass,
            chainToClass,
            chainToMethod,
            loggerTag,
            null
        );
    }
    
    private static CursorBatch_Config__mdt createCursorJobConfig(
        String jobName,
        String queryBuilderClass,
        String queryBuilderMethod,
        String workerClass,
        String chainToClass,
        String chainToMethod,
        String loggerTag,
        String stateReducerClass
    ) {
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = jobName,
            DeveloperName = CursorBatchTestUtils.toDeveloperName(jobName),
            Query_Builder_Class__c = queryBuilderClass,
            Query_Builder_Method__c = queryBuilderMethod,
            Worker_Class__c = workerClass,
            Chain_To_Class__c = chainToClass,
            Chain_To_Method__c = chainToMethod,
            Logger_Tag__c = loggerTag,
            State_Reducer_Class__c = stateReducerClass,
            Parallel_Count__c = 5,
            Page_Size__c = 20,
            Active__c = true
        );
        return config;
    }
    
    // ============================================
    // CursorJob Constructor Tests
    // ============================================
    
    @IsTest
    static void testConstructorLoadsConfig() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestCursorJob',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        // Act
        Test.startTest();
        CursorJob cursorJob = new CursorJob('TestCursorJob');
        Test.stopTest();
        
        // Assert - verify buildQuery() works (config was loaded)
        String query = cursorJob.buildQuery();
        Assert.areEqual(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 
            'Should load config and build query');
    }
    
    @IsTest
    static void testConstructorWithLoggerTag() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestCursorJobWithTag',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker',
            null,
            null,
            'TestTag'
        );
        
        // Act
        Test.startTest();
        CursorJob cursorJob = new CursorJob('TestCursorJobWithTag');
        Test.stopTest();
        
        // Assert - constructor should complete without error
        Assert.areNotEqual(null, cursorJob, 'CursorJob should be created');
    }
    
    // ============================================
    // buildQuery() Tests
    // ============================================
    
    @IsTest
    static void testBuildQuerySuccess() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestBuildQuery',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestBuildQuery');
        
        // Act
        Test.startTest();
        String query = cursorJob.buildQuery();
        Test.stopTest();
        
        // Assert
        Assert.areEqual(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 
            'Should return query from query builder');
    }
    
    @IsTest
    static void testBuildQueryMissingConfig() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('NoQueryBuilder', 5, 20);
        
        CursorJob cursorJob = new CursorJob('NoQueryBuilder');
        
        // Act & Assert
        Test.startTest();
        try {
            cursorJob.buildQuery();
            Assert.isTrue(false, 'Should throw exception for missing query builder config');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('Query_Builder_Class__c'), 
                'Exception should mention missing Query_Builder_Class__c');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testBuildQueryClassNotFound() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestMissingClass',
            'NonExistentQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestMissingClass');
        
        // Act & Assert
        Test.startTest();
        try {
            cursorJob.buildQuery();
            Assert.isTrue(false, 'Should throw exception for missing class');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('not found'), 
                'Exception should mention class not found');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testBuildQueryMethodReturnsNull() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestNullMethod',
            'CursorJobTest.TestQueryBuilder',
            'nonExistentMethod',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestNullMethod');
        
        // Act & Assert
        Test.startTest();
        try {
            cursorJob.buildQuery();
            Assert.isTrue(false, 'Should throw exception when query builder returns null');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('returned null'), 
                'Exception should mention null return');
        }
        Test.stopTest();
    }
    
    // ============================================
    // getWorkerClassName() Tests
    // ============================================
    
    @IsTest
    static void testGetWorkerClassName() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestWorkerClass',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestWorkerClass');
        
        // Act
        Test.startTest();
        String workerClass = cursorJob.getWorkerClassName();
        Test.stopTest();
        
        // Assert
        Assert.areEqual('CursorJobTest.TestCursorJobWorker', workerClass, 
            'Should return worker class from config');
    }
    
    @IsTest
    static void testGetWorkerClassNameMissing() {
        // Arrange
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = 'TestNoWorker',
            Query_Builder_Class__c = 'CursorJobTest.TestQueryBuilder',
            Query_Builder_Method__c = 'getAccountsQuery',
            Worker_Class__c = null,
            Parallel_Count__c = 5,
            Page_Size__c = 20,
            Active__c = true
        );
        CursorBatchCoordinator.testConfig = config;
        
        CursorJob cursorJob = new CursorJob('TestNoWorker');
        
        // Act & Assert
        Test.startTest();
        try {
            cursorJob.getWorkerClassName();
            Assert.isTrue(false, 'Should throw exception for missing worker class');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('Worker_Class__c'), 
                'Exception should mention missing Worker_Class__c');
        }
        Test.stopTest();
    }
    
    // ============================================
    // onComplete() Tests
    // ============================================
    
    @IsTest
    static void testOnCompleteLogsMessage() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestOnComplete',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorJob cursorJob = new CursorJob('TestOnComplete');
        cursorJob.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        cursorJob.onComplete();
        Test.stopTest();
        
        // Assert
        Assert.isTrue(mockLogger.hasInfoContaining('TestOnComplete'), 
            'Should log job name');
        Assert.isTrue(mockLogger.hasInfoContaining('completed worker fanout'), 
            'Should log fanout completion');
    }
    
    // ============================================
    // Static run() Method Tests
    // ============================================
    
    @IsTest
    static void testStaticRunMethod() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestStaticRun',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        // Act
        Test.startTest();
        CursorJob.run('TestStaticRun');
        Test.stopTest();
        
        // Assert - Job should be created
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestStaticRun');
        Assert.areEqual(1, jobs.size(), 'Should create job record');
    }
    
    @IsTest
    static void testStaticRunLinksJobParent() {
        // Arrange - end-to-end CursorJob.run() should also auto-upsert and link Job_Parent__c
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestStaticRunParent',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        // Act
        Test.startTest();
        Id jobId = CursorJob.run('TestStaticRunParent');
        Test.stopTest();
        
        // Assert
        Assert.areNotEqual(null, jobId, 'CursorJob.run should return the new job Id');
        CursorBatch_Job__c job = CursorBatchSelector.getJobById(jobId);
        Assert.areNotEqual(null, job.Job_Parent__c, 'Job_Parent__c should be auto-linked for CursorJob runs');
        
        String devName = CursorBatchTestUtils.toDeveloperName('TestStaticRunParent');
        List<CursorBatch_Job_Parent__c> parents = [
            SELECT Id, Config_Developer_Name__c, Config_Label__c
            FROM CursorBatch_Job_Parent__c
            WHERE Id = :job.Job_Parent__c
        ];
        Assert.areEqual(1, parents.size(), 'Linked parent should exist');
        Assert.areEqual(devName, parents[0].Config_Developer_Name__c,
            'Parent should be keyed by config DeveloperName');
        Assert.areEqual('TestStaticRunParent', parents[0].Config_Label__c,
            'Parent should denormalize MasterLabel');
    }
    
    @IsTest
    static void testStaticRunMethodInitializesReducerState() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestStaticRunStateful',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorBatchTestUtils.TestStatefulCursorJobWorker',
            null,
            null,
            null,
            'CursorBatchTestUtils.TestStateReducer'
        );
        
        // Act
        Test.startTest();
        CursorJob.run('TestStaticRunStateful');
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestStaticRunStateful');
        Assert.areEqual(1, jobs.size(), 'Should create a job record');
        Assert.isTrue(String.isNotBlank(jobs[0].State_JSON__c), 'Should initialize reducer state on submit');
    }
    
    // ============================================
    // Worker finish() Callback Tests
    // ============================================
    
    @IsTest
    static void testWorkerFinishCallbackInvoked() {
        // Arrange
        resetTestState();
        
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestWorkerFinish', 5, 'CursorJob'
        );
        job.Status__c = 'Completed';
        update job;
        
        // Act
        Test.startTest();
        CursorBatchWorker.invokeFinishCallback(
            'CursorJobTest.TestCursorJobWorker',
            job,
            CursorBatchLogger.getDefault()
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual(true, workerFinishCalled, 
            'Worker finish() should be called');
        Assert.areEqual(job.Id, workerFinishJobRecord.Id, 
            'Should receive job record');
    }
    
    @IsTest
    static void testWorkerFinishCallbackWithInvalidClass() {
        // Arrange
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestInvalidWorker', 5, 'CursorJob'
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        // Act
        Test.startTest();
        CursorBatchWorker.invokeFinishCallback(
            'NonExistentWorkerClass',
            job,
            mockLogger
        );
        Test.stopTest();
        
        // Assert
        Assert.isTrue(mockLogger.hasErrorContaining('not found'), 
            'Should log error for missing class');
    }
    
    // ============================================
    // Completion Handler 3-Path Logic Tests
    // ============================================
    
    @IsTest
    static void testCompletionHandler_ChainToPath() {
        // Arrange
        resetTestState();
        
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestChainPath',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker',
            'CursorJobTest.TestChainableJob',
            'submitJob',
            null
        );
        
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestChainPath', 1, 'CursorJob'
        );
        
        // Simulate job completion
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = job.Id,
                Success__c = true,
                Is_Final__c = true
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(true, chainableCallInvoked, 
            'Chain class should be invoked');
        Assert.areEqual('submitJob', chainableCalledMethod, 
            'Should call specified method');
    }
    
    @IsTest
    static void testCompletionHandler_WorkerFinishPath() {
        // Arrange
        resetTestState();
        
        // Config with Query_Builder but NO Chain_To
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestWorkerPath',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker',
            null,  // No chain
            null,
            null
        );
        
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestWorkerPath', 1, 'CursorJob'
        );
        
        // Simulate job completion
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = job.Id,
                Success__c = true,
                Is_Final__c = true
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(true, workerFinishCalled, 
            'Worker finish() should be called for CursorJob path');
    }
    
    @IsTest
    static void testCompletionHandler_WorkerFinishPathIncludesFinalState() {
        // Arrange
        CursorBatchTestUtils.resetStatefulWorker();
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestStatefulWorkerPath',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorBatchTestUtils.TestStatefulCursorJobWorker',
            null,
            null,
            null,
            'CursorBatchTestUtils.TestStateReducer'
        );
        
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestStatefulWorkerPath', 1, 'CursorJob'
        );
        job.State_JSON__c = '{"processedCount":0,"pagesProcessed":0}';
        update job;
        
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = job.Id,
                Success__c = true,
                Is_Final__c = true,
                State_Delta__c = '{"processedCount":7,"pagesProcessed":1}'
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(true, CursorBatchTestUtils.testStatefulWorker_finishCalled,
            'Stateful worker finish() should be called');
        Assert.areEqual(
            7,
            ((Decimal) CursorBatchTestUtils.testStatefulWorker_lastFinishedState.get('processedCount')).intValue(),
            'finish() should see the reduced final state'
        );
    }
    
    @IsTest
    static void testCompletionHandler_CoordinatorFinishPath() {
        // Arrange
        // Config without Query_Builder (custom coordinator path)
        CursorBatch_Config__mdt config = CursorBatchTestUtils.createTestConfig(
            'TestCoordPath', 5, 20
        );
        CursorBatchCoordinator.testConfig = config;
        
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestCoordPath', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Simulate job completion
        List<CursorBatch_WorkerComplete__e> events = new List<CursorBatch_WorkerComplete__e>{
            new CursorBatch_WorkerComplete__e(
                Job_Id__c = job.Id,
                Success__c = true,
                Is_Final__c = true
            )
        };
        
        // Act
        Test.startTest();
        new CursorBatchCompletionHandler().handle(events);
        Test.stopTest();
        
        // Assert - Job should be completed (coordinator finish path)
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(job.Id);
        Assert.areEqual('Completed', updatedJob.Status__c, 
            'Job should be completed via coordinator path');
    }
    
    // ============================================
    // resolveLogger() Tests
    // ============================================
    
    @IsTest
    static void testResolveLoggerFallsBackToDefault() {
        // Arrange
        Boolean adapterExists = Type.forName('CursorBatchLoggerAdapter') != null;
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorBatchLogger.resolveLogger(null);
        Test.stopTest();
        
        // Assert
        Assert.areNotEqual(null, logger, 'Should return a logger');
        if (adapterExists) {
            Assert.isInstanceOfType(logger, ICursorBatchLogger.class, 
                'Should return the adapter when CursorBatchLoggerAdapter is present');
        } else {
            Assert.isTrue(logger instanceof CursorBatchLogger, 
                'Should fall back to default CursorBatchLogger');
        }
    }
    
    @IsTest
    static void testResolveLoggerWithTag() {
        // Arrange - resolveLogger should handle tag even if adapter not found
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorBatchLogger.resolveLogger('TestTag');
        Test.stopTest();
        
        // Assert
        Assert.areNotEqual(null, logger, 'Should return a logger');
    }
    
    // ============================================
    // initializeJobName() Tests
    // ============================================
    
    @IsTest
    static void testInitializeJobNameLoadsConfig() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestInitialize',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob();
        
        // Act
        Test.startTest();
        cursorJob.initializeJobName('TestInitialize');
        String query = cursorJob.buildQuery();
        Test.stopTest();
        
        // Assert
        Assert.areEqual(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 
            'Should load config after initializeJobName()');
    }
    
    // ============================================
    // Metadata Tests
    // ============================================
    
    @IsTest
    static void testRunWithMetadataStoresOnJobRecord() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestMetadataRun',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        Map<String, Object> metadata = new Map<String, Object>{
            'accountId' => '001000000000001'
        };
        
        // Act
        Test.startTest();
        CursorJob.run('TestMetadataRun', metadata);
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestMetadataRun');
        Assert.areEqual(1, jobs.size(), 'Should create job record');
        Assert.areEqual(JSON.serialize(metadata), jobs[0].Metadata_JSON__c,
            'Metadata should be persisted on the job record');
    }
    
    @IsTest
    static void testRunWithoutMetadataLeavesFieldNull() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestNoMetadata',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        // Act
        Test.startTest();
        CursorJob.run('TestNoMetadata');
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestNoMetadata');
        Assert.areEqual(1, jobs.size(), 'Should create job record');
        Assert.isNull(jobs[0].Metadata_JSON__c,
            'Metadata should be null when not provided');
    }
    
    @IsTest
    static void testRunWithDelayAndMetadata() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestMetadataDelay',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        Map<String, Object> metadata = new Map<String, Object>{
            'recordId' => '001000000000002'
        };
        
        // Act
        Test.startTest();
        CursorJob.runWithDelay('TestMetadataDelay', 5, metadata);
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestMetadataDelay');
        Assert.areEqual(1, jobs.size(), 'Should create job record');
        Assert.areEqual(JSON.serialize(metadata), jobs[0].Metadata_JSON__c,
            'Metadata should be persisted on delayed job');
    }
    
    @IsTest
    static void testBuildQueryDispatchesToMetadataInterface() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Map<String, Object> metadata = new Map<String, Object>{
            'accountId' => testAccount.Id
        };
        
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestMetadataBuilder',
            'CursorJobTest.TestMetadataQueryBuilder',
            'getAccountsByIdQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestMetadataBuilder', metadata);
        
        // Act
        Test.startTest();
        String query = cursorJob.buildQuery();
        Test.stopTest();
        
        // Assert
        Assert.isTrue(query.contains(testAccount.Id),
            'Metadata query builder should incorporate the account ID into the query');
    }
    
    @IsTest
    static void testBuildQueryFallsBackToNonMetadataInterface() {
        // Arrange - use the original TestQueryBuilder (implements ICursorBatchQueryBuilder, not metadata version)
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestFallbackBuilder',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestFallbackBuilder', new Map<String, Object>{
            'someKey' => 'someValue'
        });
        
        // Act
        Test.startTest();
        String query = cursorJob.buildQuery();
        Test.stopTest();
        
        // Assert - should fall back to ICursorBatchQueryBuilder and still work
        Assert.areEqual(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query,
            'Should fall back to ICursorBatchQueryBuilder when metadata interface not implemented');
    }
    
    @IsTest
    static void testBuildQueryMetadataBuilderWithNullMetadata() {
        // Arrange - metadata-aware builder should handle null metadata gracefully
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestNullMetaBuilder',
            'CursorJobTest.TestMetadataQueryBuilder',
            'getAccountsByIdQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        CursorJob cursorJob = new CursorJob('TestNullMetaBuilder');
        
        // Act
        Test.startTest();
        String query = cursorJob.buildQuery();
        Test.stopTest();
        
        // Assert - should return default query when metadata is null
        Assert.areEqual(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query,
            'Metadata query builder should handle null metadata gracefully');
    }
    
    @IsTest
    static void testContextCopyPreservesMetadata() {
        // Arrange
        String metadataJson = '{"accountId":"001000000000003"}';
        CursorBatchContext ctx = new CursorBatchContext(
            null, 0, 100, 20, 'TestJob', 1, null,
            'CursorJobTest.TestCursorJobWorker', 'testQueryId', 0, metadataJson
        );
        
        // Act
        Test.startTest();
        CursorBatchContext nextCtx = ctx.withNextPosition(20);
        CursorBatchContext retryCtx = ctx.withRetry(1);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(metadataJson, nextCtx.metadataJson,
            'withNextPosition() should preserve metadata');
        Assert.areEqual(metadataJson, retryCtx.metadataJson,
            'withRetry() should preserve metadata');
    }
    
    @IsTest
    static void testCustomCoordinatorWithMetadata() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestCoordMeta', 5, 20);
        String metadataJson = '{"customParam":"value123"}';
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coord =
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestCoordMeta');
        coord.setMetadata(metadataJson);
        
        // Act
        Test.startTest();
        coord.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestCoordMeta');
        Assert.areEqual(1, jobs.size(), 'Should create job record');
        Assert.areEqual(metadataJson, jobs[0].Metadata_JSON__c,
            'Custom coordinator metadata should be persisted on job record');
    }
    
    // ============================================
    // setMetadata() Validation Tests
    // ============================================
    
    @IsTest
    static void testSetMetadataRejectsInvalidJson() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestInvalidMeta', 5, 20);
        CursorBatchTestUtils.TestCursorBatchCoordinator coord =
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestInvalidMeta');
        
        // Act & Assert
        Test.startTest();
        try {
            coord.setMetadata('{not valid json}');
            Assert.isTrue(false, 'Should throw exception for invalid JSON');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('not valid JSON'),
                'Exception should indicate invalid JSON: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testSetMetadataRejectsOversizedJson() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestOversized', 5, 20);
        CursorBatchTestUtils.TestCursorBatchCoordinator coord =
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestOversized');
        
        // Build a valid JSON string exceeding the 131,072 char limit
        String bigValue = ''.leftPad(CursorBatchCoordinator.METADATA_JSON_MAX_LENGTH, 'x');
        String oversizedJson = '{"d":"' + bigValue + '"}';
        
        // Act & Assert
        Test.startTest();
        try {
            coord.setMetadata(oversizedJson);
            Assert.isTrue(false, 'Should throw exception for oversized JSON');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            Assert.isTrue(e.getMessage().contains('exceeds maximum length'),
                'Exception should indicate size limit: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testSetMetadataAcceptsNullAndBlank() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig('TestNullMeta', 5, 20);
        CursorBatchTestUtils.TestCursorBatchCoordinator coord =
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestNullMeta');
        
        // Act & Assert - none of these should throw
        Test.startTest();
        coord.setMetadata(null);
        coord.setMetadata('');
        coord.setMetadata('  ');
        Test.stopTest();
    }
    
    // ============================================
    // Metadata Propagation Path Tests
    // ============================================
    
    @IsTest
    static void testMetadataRestoredDuringExecute() {
        // Arrange - simulate the coordinator PE path where the coordinator is
        // created via reflection without metadata on the instance
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'TestMetaRestore',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        String metadataJson = '{"accountId":"001000000000004"}';
        
        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = 'TestMetaRestore',
            Status__c = 'Preparing',
            Coordinator_Class__c = 'CursorJob',
            Query__c = CursorBatchTestUtils.DEFAULT_TEST_QUERY,
            Metadata_JSON__c = metadataJson,
            Started_At__c = System.now(),
            Total_Cursor_Retries__c = 0,
            Total_Workers__c = 0,
            Total_Batches__c = 0,
            Completed_Batches__c = 0,
            Workers_Finished__c = 0,
            Failed_Workers__c = 0,
            Total_Worker_Retries__c = 0
        );
        insert job;
        
        CursorJob cursorJob = new CursorJob();
        cursorJob.initializeJobName('TestMetaRestore');
        cursorJob.setJobRecordId(job.Id);
        
        // Act
        Test.startTest();
        cursorJob.execute(null);
        Test.stopTest();
        
        // Assert - job transitions to Processing (metadata was restored and workers fanned out)
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(job.Id);
        Assert.areEqual('Processing', updatedJob.Status__c,
            'Job should transition to Processing after execute()');
        Assert.areEqual(metadataJson, updatedJob.Metadata_JSON__c,
            'Metadata should be preserved on the job record');
    }
    
    @IsTest
    static void testWithCursorPreservesMetadata() {
        // Arrange
        String metadataJson = '{"key":"value"}';
        CursorBatchContext ctx = new CursorBatchContext(
            null, 0, 100, 20, 'TestJob', 1, null,
            'CursorJobTest.TestCursorJobWorker', 'testQueryId', 0, metadataJson
        );
        
        // Act
        Test.startTest();
        CursorBatchContext cursorCtx = ctx.withCursor(null);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(metadataJson, cursorCtx.metadataJson,
            'withCursor() should preserve metadata');
    }
    
    @IsTest
    static void testCoordinatorFinishReceivesMetadata() {
        // Arrange - verify that invokeFinishCallback() restores metadata on the
        // coordinator instance before calling finish()
        resetTestState();
        
        String metadataJson = '{"finishParam":"xyz"}';
        CursorBatch_Job__c job = CursorBatchTestUtils.createTestJobRecord(
            'TestFinishMeta', 1, 'CursorJobTest.TestMetadataAwareCoordinator'
        );
        job.Status__c = 'Completed';
        job.Metadata_JSON__c = metadataJson;
        update job;
        
        // Act
        Test.startTest();
        CursorBatchCoordinator.invokeFinishCallback(
            'CursorJobTest.TestMetadataAwareCoordinator',
            'TestFinishMeta',
            job,
            CursorBatchLogger.getDefault()
        );
        Test.stopTest();
        
        // Assert
        Assert.areEqual(metadataJson, coordinatorFinishMetadata,
            'Coordinator finish() should have access to metadata via this.metadataJson');
    }
    
    // ============================================
    // Bulk Run Tests
    // ============================================
    
    @IsTest
    static void testRunListCreatesOneJobPerDistinctName() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'BulkJobA',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        // Act
        Test.startTest();
        Map<String, Id> jobIdsByName = CursorJob.run(new List<String>{ 'BulkJobA', 'BulkJobB', 'BulkJobA' });
        Test.stopTest();
        
        // Assert
        Assert.areEqual(2, jobIdsByName.size(), 'Repeated names should collapse to one entry');
        Assert.isNotNull(jobIdsByName.get('BulkJobA'), 'BulkJobA should be submitted');
        Assert.isNotNull(jobIdsByName.get('BulkJobB'), 'BulkJobB should be submitted');
        
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByNames(new Set<String>{ 'BulkJobA', 'BulkJobB' });
        Assert.areEqual(2, jobs.size(), 'Should create one job record per distinct name');
        for (CursorBatch_Job__c job : jobs) {
            Assert.areEqual('Preparing', job.Status__c, 'Bulk-submitted jobs should start in Preparing');
            Assert.areEqual(jobIdsByName.get(job.Job_Name__c), job.Id, 'Returned Id should match the job record for its name');
            Assert.isNotNull(job.Job_Parent__c, 'Bulk-submitted jobs should be linked to their parent');
        }
    }
    
    @IsTest
    static void testRunListSkipsAlreadyRunningName() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'BulkRunning',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        CursorBatch_Job__c runningJob = CursorBatchTestUtils.createTestJobRecord('BulkRunning', 1, 'CursorJob');
        
        // Act
        Test.startTest();
        Map<String, Id> jobIdsByName = CursorJob.run(new List<String>{ 'BulkRunning', 'BulkIdle' });
        Test.stopTest();
        
        // Assert
        Assert.isTrue(jobIdsByName.containsKey('BulkRunning'), 'Skipped name should still appear in the result');
        Assert.isNull(jobIdsByName.get('BulkRunning'), 'Already-running job should map to null');
        Assert.isNotNull(jobIdsByName.get('BulkIdle'), 'Idle job should still be submitted');
        
        List<CursorBatch_Job__c> running = CursorBatchSelector.getRunningJobsByName('BulkRunning');
        Assert.areEqual(1, running.size(), 'No second run should be created for the running job');
        Assert.areEqual(runningJob.Id, running[0].Id, 'The original run should be the only one');
    }
    
    @IsTest
    static void testRunListEmptyOrNullDoesNothing() {
        // Act
        Test.startTest();
        Map<String, Id> fromNull = CursorJob.run((List<String>) null);
        Map<String, Id> fromEmpty = CursorJob.run(new List<String>());
        Test.stopTest();
        
        // Assert
        Assert.isTrue(fromNull.isEmpty(), 'Null input should return an empty map');
        Assert.isTrue(fromEmpty.isEmpty(), 'Empty input should return an empty map');
        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Job__c], 'No job records should be created');
    }
    
    @IsTest
    static void testRunListUsesSameQueriesAndDmlForAnyCount() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'BulkLimits',
            'CursorJobTest.TestQueryBuilder',
            'getAccountsQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        Test.startTest();
        // Warm-up so the once-per-interval ledger sweep and watchdog stamps don't skew the counts
        CursorJob.run(new List<String>{ 'BulkLimitsWarmUp' });
        
        // Act
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        CursorJob.run(new List<String>{ 'BulkLimitsOne' });
        Integer singleQueries = Limits.getQueries() - queriesBefore;
        Integer singleDml = Limits.getDmlStatements() - dmlBefore;
        
        queriesBefore = Limits.getQueries();
        dmlBefore = Limits.getDmlStatements();
        CursorJob.run(new List<String>{ 'BulkLimits1', 'BulkLimits2', 'BulkLimits3', 'BulkLimits4', 'BulkLimits5' });
        Integer fiveQueries = Limits.getQueries() - queriesBefore;
        Integer fiveDml = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();
        
        // Assert
        Assert.areEqual(singleQueries, fiveQueries, 'Five jobs should use the same number of queries as one');
        Assert.areEqual(singleDml, fiveDml, 'Five jobs should use the same number of DML statements as one');
    }
    
    @IsTest
    static void testRunMetadataListCreatesOneJobPerMapInOrder() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'BulkMetadata',
            'CursorJobTest.TestMetadataQueryBuilder',
            'getAccountsByIdQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        List<Map<String, Object>> metadataList = new List<Map<String, Object>>{
            new Map<String, Object>{ 'run' => 1 },
            new Map<String, Object>{ 'run' => 2 },
            new Map<String, Object>{ 'run' => 3 }
        };
        
        // Act
        Test.startTest();
        List<Id> jobIds = CursorJob.run('BulkMetadata', metadataList);
        Test.stopTest();
        
        // Assert
        Assert.areEqual(3, jobIds.size(), 'Should return one Id per metadata map');
        Map<Id, CursorBatch_Job__c> jobsById = new Map<Id, CursorBatch_Job__c>(
            CursorBatchSelector.getRunningJobsByName('BulkMetadata')
        );
        Assert.areEqual(3, jobsById.size(), 'Runs in one call should not block each other');
        for (Integer i = 0; i < jobIds.size(); i++) {
            Assert.isNotNull(jobIds[i], 'Every run should be submitted');
            Assert.areEqual(JSON.serialize(metadataList[i]), jobsById.get(jobIds[i]).Metadata_JSON__c,
                'Ids should come back in input order with their own metadata');
        }
    }
    
    @IsTest
    static void testRunMetadataListSkipsAllWhenAlreadyRunning() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'BulkMetadataRunning',
            'CursorJobTest.TestMetadataQueryBuilder',
            'getAccountsByIdQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        CursorBatchTestUtils.createTestJobRecord('BulkMetadataRunning', 1, 'CursorJob');
        
        // Act
        Test.startTest();
        List<Id> jobIds = CursorJob.run('BulkMetadataRunning', new List<Map<String, Object>>{
            new Map<String, Object>{ 'run' => 1 },
            new Map<String, Object>{ 'run' => 2 }
        });
        Test.stopTest();
        
        // Assert
        Assert.areEqual(new List<Id>{ null, null }, jobIds, 'Every entry should be skipped while the job is running');
        Assert.areEqual(1, CursorBatchSelector.getRunningJobsByName('BulkMetadataRunning').size(),
            'No new runs should be created');
    }
    
    @IsTest
    static void testRunMetadataListAllowsDuplicatesWhenSkipDuplicateCheck() {
        // Arrange
        CursorBatch_Config__mdt config = createCursorJobConfig(
            'BulkMetadataSkip',
            'CursorJobTest.TestMetadataQueryBuilder',
            'getAccountsByIdQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        config.Skip_Duplicate_Check__c = true;
        CursorBatchCoordinator.testConfig = config;
        CursorBatchTestUtils.createTestJobRecord('BulkMetadataSkip', 1, 'CursorJob');
        
        // Act
        Test.startTest();
        List<Id> jobIds = CursorJob.run('BulkMetadataSkip', new List<Map<String, Object>>{
            new Map<String, Object>{ 'run' => 1 },
            new Map<String, Object>{ 'run' => 2 }
        });
        Test.stopTest();
        
        // Assert
        Assert.isNotNull(jobIds[0], 'First run should be submitted');
        Assert.isNotNull(jobIds[1], 'Second run should be submitted');
        Assert.areEqual(3, CursorBatchSelector.getRunningJobsByName('BulkMetadataSkip').size(),
            'Both runs should be added alongside the running one');
    }
    
    @IsTest
    static void testRunMetadataListSubmitsNothingWhenOneQueryFails() {
        // Arrange
        CursorBatchCoordinator.testConfig = createCursorJobConfig(
            'BulkMetadataFail',
            'CursorJobTest.TestMetadataQueryBuilder',
            'getAccountsOrNullWhenFailQuery',
            'CursorJobTest.TestCursorJobWorker'
        );
        
        // Act
        Test.startTest();
        CursorBatchCoordinator.CursorBatchException caught;
        try {
            CursorJob.run('BulkMetadataFail', new List<Map<String, Object>>{
                new Map<String, Object>{ 'fail' => false },
                new Map<String, Object>{ 'fail' => true }
            });
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            caught = e;
        }
        Test.stopTest();
        
        // Assert
        Assert.isNotNull(caught, 'A query that fails to build should throw');
        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Job__c WHERE Job_Name__c = 'BulkMetadataFail'],
            'No run should be created when any run in the call fails to build');
    }
    
    @IsTest
    static void testRunMetadataListEmptyOrNullDoesNothing() {
        // Act
        Test.startTest();
        List<Id> fromNull = CursorJob.run('BulkMetadataNone', (List<Map<String, Object>>) null);
        List<Id> fromEmpty = CursorJob.run('BulkMetadataNone', new List<Map<String, Object>>());
        Test.stopTest();
        
        // Assert
        Assert.isTrue(fromNull.isEmpty(), 'Null input should return an empty list');
        Assert.isTrue(fromEmpty.isEmpty(), 'Empty input should return an empty list');
        Assert.areEqual(0, [SELECT COUNT() FROM CursorBatch_Job__c], 'No job records should be created');
    }
}
