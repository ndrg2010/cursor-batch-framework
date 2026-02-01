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
    
    // ============================================
    // Helper Methods
    // ============================================
    
    private static CursorBatch_Config__mdt createCursorJobConfig(
        String jobName,
        String queryBuilderClass,
        String queryBuilderMethod,
        String workerClass
    ) {
        return createCursorJobConfig(jobName, queryBuilderClass, queryBuilderMethod, workerClass, null, null, null);
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
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = jobName,
            Query_Builder_Class__c = queryBuilderClass,
            Query_Builder_Method__c = queryBuilderMethod,
            Worker_Class__c = workerClass,
            Chain_To_Class__c = chainToClass,
            Chain_To_Method__c = chainToMethod,
            Logger_Tag__c = loggerTag,
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
        System.assertEquals(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 
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
        System.assertNotEquals(null, cursorJob, 'CursorJob should be created');
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
        System.assertEquals(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 
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
            System.assert(false, 'Should throw exception for missing query builder config');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('Query_Builder_Class__c'), 
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
            System.assert(false, 'Should throw exception for missing class');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('not found'), 
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
            System.assert(false, 'Should throw exception when query builder returns null');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('returned null'), 
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
        System.assertEquals('CursorJobTest.TestCursorJobWorker', workerClass, 
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
            System.assert(false, 'Should throw exception for missing worker class');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('Worker_Class__c'), 
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
        System.assert(mockLogger.hasInfoContaining('TestOnComplete'), 
            'Should log job name');
        System.assert(mockLogger.hasInfoContaining('completed worker fanout'), 
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
        System.assertEquals(1, jobs.size(), 'Should create job record');
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
        System.assertEquals(true, workerFinishCalled, 
            'Worker finish() should be called');
        System.assertEquals(job.Id, workerFinishJobRecord.Id, 
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
        System.assert(mockLogger.hasErrorContaining('not found'), 
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
        System.assertEquals(true, chainableCallInvoked, 
            'Chain class should be invoked');
        System.assertEquals('submitJob', chainableCalledMethod, 
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
        System.assertEquals(true, workerFinishCalled, 
            'Worker finish() should be called for CursorJob path');
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
        System.assertEquals('Completed', updatedJob.Status__c, 
            'Job should be completed via coordinator path');
    }
    
    // ============================================
    // resolveLogger() Tests
    // ============================================
    
    @IsTest
    static void testResolveLoggerFallsBackToDefault() {
        // Arrange - No CursorBatchLoggerAdapter exists in package
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorJob.resolveLogger(null);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, logger, 'Should return a logger');
        System.assert(logger instanceof CursorBatchLogger, 
            'Should fall back to default CursorBatchLogger');
    }
    
    @IsTest
    static void testResolveLoggerWithTag() {
        // Arrange - resolveLogger should handle tag even if adapter not found
        
        // Act
        Test.startTest();
        ICursorBatchLogger logger = CursorJob.resolveLogger('TestTag');
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, logger, 'Should return a logger');
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
        System.assertEquals(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 
            'Should load config after initializeJobName()');
    }
}
