/**
 * @description Test utilities for CursorBatchFramework including concrete implementations
 *              of abstract classes and mock objects for testing.
 * @group CursorBatchFramework
 */
@IsTest
public without sharing class CursorBatchTestUtils {
    
    /**
     * @description Creates test Account records for cursor batch testing.
     * @param count Number of accounts to create
     * @return List of inserted Account records
     */
    public static List<Account> createTestAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Description = 'Test account for cursor batch framework testing'
            ));
        }
        insert accounts;
        return accounts;
    }
    
    /**
     * @description Queries Account records for testing. Common pattern for tests that need
     *              to retrieve existing accounts created in @TestSetup.
     * @param limitCount Maximum number of accounts to return (optional, defaults to all)
     * @return List of Account records
     */
    public static List<Account> queryTestAccounts(Integer limitCount) {
        if (limitCount != null && limitCount > 0) {
            return [SELECT Id, Name FROM Account LIMIT :limitCount];
        }
        return [SELECT Id, Name FROM Account];
    }
    
    /**
     * @description Creates a test configuration for cursor batch jobs.
     * @param jobName Job name/label
     * @param workerCount Number of workers
     * @param pageSize Page size for cursor fetching
     * @return CursorBatch_Config__mdt instance (not inserted - custom metadata)
     */
    public static CursorBatch_Config__mdt createTestConfig(
        String jobName, 
        Integer workerCount, 
        Integer pageSize
    ) {
        return createTestConfig(jobName, workerCount, pageSize, 3);
    }
    
    /**
     * @description Creates a test configuration for cursor batch jobs with coordinator max retries.
     * @param jobName Job name/label
     * @param workerCount Number of workers
     * @param pageSize Page size for cursor fetching
     * @param coordinatorMaxRetries Maximum retry attempts for coordinator cursor timeouts
     * @return CursorBatch_Config__mdt instance (not inserted - custom metadata)
     */
    public static CursorBatch_Config__mdt createTestConfig(
        String jobName, 
        Integer workerCount, 
        Integer pageSize,
        Integer coordinatorMaxRetries
    ) {
        return createTestConfig(jobName, workerCount, pageSize, coordinatorMaxRetries, 3, 1);
    }
    
    /**
     * @description Creates a test configuration for cursor batch jobs with full retry settings.
     * @param jobName Job name/label
     * @param workerCount Number of workers
     * @param pageSize Page size for cursor fetching
     * @param coordinatorMaxRetries Maximum retry attempts for coordinator cursor timeouts
     * @param workerMaxRetries Maximum retry attempts for worker page failures
     * @param workerRetryDelay Base delay in minutes for worker retry exponential backoff
     * @return CursorBatch_Config__mdt instance (not inserted - custom metadata)
     */
    public static CursorBatch_Config__mdt createTestConfig(
        String jobName, 
        Integer workerCount, 
        Integer pageSize,
        Integer coordinatorMaxRetries,
        Integer workerMaxRetries,
        Integer workerRetryDelay
    ) {
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = jobName,
            Parallel_Count__c = workerCount,
            Page_Size__c = pageSize,
            Coordinator_Max_Retries__c = coordinatorMaxRetries,
            Worker_Max_Retries__c = workerMaxRetries,
            Worker_Retry_Delay__c = workerRetryDelay,
            Active__c = true
        );
        return config;
    }
    
    /**
     * @description Creates a CursorBatch_Job__c record for testing.
     * @param jobName Job name
     * @param totalWorkers Total number of workers
     * @param coordinatorClass Coordinator class name
     * @return Inserted CursorBatch_Job__c record
     */
    public static CursorBatch_Job__c createTestJobRecord(
        String jobName, 
        Integer totalWorkers, 
        String coordinatorClass
    ) {
        return createTestJobRecord(jobName, totalWorkers, coordinatorClass, null);
    }
    
    /**
     * @description Creates a CursorBatch_Job__c record for testing with record count.
     * @param jobName Job name
     * @param totalWorkers Total number of workers
     * @param coordinatorClass Coordinator class name
     * @param totalRecords Total number of records in the cursor (optional)
     * @return Inserted CursorBatch_Job__c record
     */
    public static CursorBatch_Job__c createTestJobRecord(
        String jobName, 
        Integer totalWorkers, 
        String coordinatorClass,
        Integer totalRecords
    ) {
        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = jobName,
            Total_Workers__c = totalWorkers,
            Total_Records__c = totalRecords,
            Total_Batches__c = totalWorkers,  // Default to 1 batch per worker for tests
            Completed_Batches__c = 0,
            Workers_Finished__c = 0,
            Failed_Workers__c = 0,
            Status__c = 'Processing',
            Coordinator_Class__c = coordinatorClass,
            Cursor_Query_Id__c = 'TestQueryId' + System.currentTimeMillis(),
            Started_At__c = System.now(),
            Total_Cursor_Retries__c = 0,
            Total_Worker_Retries__c = 0
        );
        insert job;
        return job;
    }
    
    /**
     * @description Creates a CursorBatch_Job__c record in 'Preparing' status for finalizer tests.
     *              This simulates a job that the coordinator has started but not yet dispatched workers.
     * @param jobName Job name
     * @param coordinatorClass Coordinator class name
     * @param retryCount Current retry count
     * @return Inserted CursorBatch_Job__c record in Preparing status
     */
    public static CursorBatch_Job__c createPreparingJobRecord(
        String jobName, 
        String coordinatorClass,
        Integer retryCount
    ) {
        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = jobName,
            Status__c = 'Preparing',
            Coordinator_Class__c = coordinatorClass,
            Started_At__c = System.now(),
            Total_Cursor_Retries__c = retryCount != null ? retryCount : 0,
            Total_Workers__c = 0,
            Total_Batches__c = 0,
            Completed_Batches__c = 0,
            Workers_Finished__c = 0,
            Failed_Workers__c = 0,
            Total_Worker_Retries__c = 0
        );
        insert job;
        return job;
    }
    
    /**
     * @description Convenience method that sets test config and creates a preparing job record.
     *              Use this for tests that call execute() directly on a coordinator.
     * @param jobName Job name
     * @param workerCount Number of workers
     * @param pageSize Page size for cursor fetching
     * @return Inserted CursorBatch_Job__c record in Preparing status
     */
    public static CursorBatch_Job__c setupTestJob(String jobName, Integer workerCount, Integer pageSize) {
        CursorBatchCoordinator.testConfig = createTestConfig(jobName, workerCount, pageSize);
        return createPreparingJobRecord(jobName, 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0);
    }
    
    // ============================================
    // Test Context Helper Methods
    // ============================================
    
    /**
     * @description Creates a CursorBatchContext for testing with sensible defaults.
     *              Uses the default test cursor and worker class.
     * @param jobRecordId The job record ID to associate with the context
     * @param retryCount Current retry count
     * @return CursorBatchContext with default test values
     */
    public static CursorBatchContext createTestContext(Id jobRecordId, Integer retryCount) {
        Database.Cursor cursor = createTestCursor();
        String cursorQueryId = extractQueryId(cursor);
        
        return new CursorBatchContext(
            cursor,
            0,                                          // startPosition
            10,                                         // endPosition
            5,                                          // pageSize
            'TestJob',                                  // jobName
            1,                                          // workerNum
            jobRecordId,
            'CursorBatchTestUtils.TestCursorBatchWorker',
            cursorQueryId,
            retryCount != null ? retryCount : 0
        );
    }
    
    /**
     * @description Creates a CursorBatchContext for testing with custom parameters.
     * @param jobRecordId The job record ID to associate with the context
     * @param startPosition Start position in cursor
     * @param endPosition End position in cursor
     * @param pageSize Page size for fetching
     * @param retryCount Current retry count
     * @return CursorBatchContext with specified values
     */
    public static CursorBatchContext createTestContext(
        Id jobRecordId, 
        Integer startPosition,
        Integer endPosition,
        Integer pageSize,
        Integer retryCount
    ) {
        Database.Cursor cursor = createTestCursor();
        String cursorQueryId = extractQueryId(cursor);
        
        return new CursorBatchContext(
            cursor,
            startPosition,
            endPosition,
            pageSize,
            'TestJob',
            1,
            jobRecordId,
            'CursorBatchTestUtils.TestCursorBatchWorker',
            cursorQueryId,
            retryCount != null ? retryCount : 0
        );
    }
    
    /**
     * @description Creates a CursorBatchContext with a null cursorQueryId for testing
     *              cursor reconstruction failure scenarios.
     * @param jobRecordId The job record ID to associate with the context
     * @param retryCount Current retry count
     * @return CursorBatchContext with null cursorQueryId
     */
    public static CursorBatchContext createTestContextWithNullQueryId(Id jobRecordId, Integer retryCount) {
        Database.Cursor cursor = createTestCursor();
        
        return new CursorBatchContext(
            cursor,
            0,
            10,
            5,
            'TestJob',
            1,
            jobRecordId,
            'CursorBatchTestUtils.TestCursorBatchWorker',
            null,  // cursorQueryId is null
            retryCount != null ? retryCount : 0
        );
    }
    
    /**
     * @description Creates a CursorBatchContext with a custom worker class name for testing
     *              invalid worker class scenarios.
     * @param jobRecordId The job record ID to associate with the context
     * @param workerClassName Custom worker class name
     * @param retryCount Current retry count
     * @return CursorBatchContext with specified worker class
     */
    public static CursorBatchContext createTestContextWithWorkerClass(
        Id jobRecordId, 
        String workerClassName,
        Integer retryCount
    ) {
        Database.Cursor cursor = createTestCursor();
        String cursorQueryId = extractQueryId(cursor);
        
        return new CursorBatchContext(
            cursor,
            0,
            10,
            5,
            'TestJob',
            1,
            jobRecordId,
            workerClassName,
            cursorQueryId,
            retryCount != null ? retryCount : 0
        );
    }
    
    // ============================================
    // Test Cursor Helper Methods
    // ============================================
    
    /**
     * @description Default test query string for Account records.
     *              Used by test coordinators and cursor creation helpers.
     */
    public static final String DEFAULT_TEST_QUERY = 'SELECT Id, Name FROM Account ORDER BY Name';
    
    /**
     * @description Extracts the queryId from a Database.Cursor for testing.
     *              Used by trigger handler and finalizer tests for cursor reconstruction.
     * @param cursor The Database.Cursor to extract queryId from
     * @return The queryId string
     */
    public static String extractQueryId(Database.Cursor cursor) {
        String cursorJson = JSON.serialize(cursor);
        Map<String, Object> cursorMap = (Map<String, Object>) JSON.deserializeUntyped(cursorJson);
        return (String) cursorMap.get('queryId');
    }
    
    /**
     * @description Creates a Database.Cursor for testing using the default Account query.
     *              This is the standard pattern used across all tests.
     * @return Database.Cursor instance
     */
    public static Database.Cursor createTestCursor() {
        return Database.getCursor(DEFAULT_TEST_QUERY);
    }
    
    /**
     * @description Creates a Database.Cursor for testing with a LIMIT clause.
     *              Useful for testing pagination and boundary conditions.
     * @param limitCount Number of records to limit
     * @return Database.Cursor instance
     */
    public static Database.Cursor createTestCursor(Integer limitCount) {
        return Database.getCursor(DEFAULT_TEST_QUERY + ' LIMIT ' + limitCount);
    }
    
    /**
     * @description Concrete implementation of CursorBatchCoordinator for testing.
     */
    public class TestCursorBatchCoordinator extends CursorBatchCoordinator {
        
        public Boolean onCompleteCalled = false;
        public Boolean finishCalled = false;
        public CursorBatch_Job__c completedJobRecord;
        public String testQuery;
        public Boolean shouldBlockDuplicate = false;
        
        public TestCursorBatchCoordinator(String jobName) {
            super(jobName);
            // Default query for Account
            this.testQuery = DEFAULT_TEST_QUERY;
        }
        
        public TestCursorBatchCoordinator(String jobName, String query) {
            super(jobName);
            this.testQuery = query;
        }
        
        public override String buildQuery() {
            return testQuery;
        }
        
        public override String getWorkerClassName() {
            return 'CursorBatchTestUtils.TestCursorBatchWorker';
        }
        
        public override void onComplete() {
            super.onComplete();
            onCompleteCalled = true;
        }
        
        public override void finish(CursorBatch_Job__c jobRecord) {
            super.finish(jobRecord);
            finishCalled = true;
            completedJobRecord = jobRecord;
        }
        
        protected override Boolean isJobAlreadyRunning(String jobName) {
            return shouldBlockDuplicate;
        }
        
    }
    
    /**
     * @description Test coordinator that uses the base isJobAlreadyRunning() implementation
     *              to test real duplicate prevention logic.
     */
    public class DuplicateCheckCoordinator extends CursorBatchCoordinator {
        
        public Boolean onCompleteCalled = false;
        
        public DuplicateCheckCoordinator(String jobName) {
            super(jobName);
        }
        
        public override String buildQuery() {
            return DEFAULT_TEST_QUERY;
        }
        
        public override String getWorkerClassName() {
            return 'CursorBatchTestUtils.TestCursorBatchWorker';
        }
        
        public override void onComplete() {
            super.onComplete();
            onCompleteCalled = true;
        }
        
        // Note: Does NOT override isJobAlreadyRunning() to test base implementation
        
    }
    
    // Static fields for TestCursorBatchWorker state tracking
    // Moved to outer class because inner classes cannot have static members in Apex
    public static List<SObject> testWorker_processedRecords = new List<SObject>();
    public static Integer testWorker_processCallCount = 0;
    public static Boolean testWorker_onCompleteCalled = false;
    
    /**
     * @description Resets static state between tests for TestCursorBatchWorker.
     */
    public static void resetTestWorker() {
        testWorker_processedRecords = new List<SObject>();
        testWorker_processCallCount = 0;
        testWorker_onCompleteCalled = false;
    }
    
    /**
     * @description Concrete implementation of CursorBatchWorker for testing.
     */
    public class TestCursorBatchWorker extends CursorBatchWorker {
        
        public Boolean shouldThrowException = false;
        public Boolean shouldThrowRetryException = false;
        public Integer retryExceptionDelay = null;
        
        public TestCursorBatchWorker() {
            super();
        }
        
        public override void process(List<SObject> records) {
            if (shouldThrowRetryException) {
                throw CursorBatchRetryException.create('Test retry exception', retryExceptionDelay);
            }
            if (shouldThrowException) {
                throw new CursorBatchCoordinator.CursorBatchException('Test exception');
            }
            testWorker_processedRecords.addAll(records);
            testWorker_processCallCount++;
        }
        
        public override void onComplete() {
            super.onComplete();
            testWorker_onCompleteCalled = true;
        }
    }
    
    /**
     * @description Mock logger that captures log calls for test assertions.
     */
    public class MockCursorBatchLogger implements ICursorBatchLogger {
        
        public List<String> infoMessages = new List<String>();
        public List<String> errorMessages = new List<String>();
        public List<String> exceptionMessages = new List<String>();
        public List<Exception> loggedExceptions = new List<Exception>();
        
        public void logInfo(String message) {
            infoMessages.add(message);
        }
        
        public void logError(String message) {
            errorMessages.add(message);
        }
        
        public void logException(String message, Exception e) {
            exceptionMessages.add(message);
            loggedExceptions.add(e);
        }
        
        /**
         * @description Checks if any info message contains the given text.
         * @param text Text to search for
         * @return True if found
         */
        public Boolean hasInfoContaining(String text) {
            for (String msg : infoMessages) {
                if (msg.contains(text)) {
                    return true;
                }
            }
            return false;
        }
        
        /**
         * @description Checks if any error message contains the given text.
         * @param text Text to search for
         * @return True if found
         */
        public Boolean hasErrorContaining(String text) {
            for (String msg : errorMessages) {
                if (msg.contains(text)) {
                    return true;
                }
            }
            return false;
        }
    }
    
    /**
     * @description Mock implementation of System.FinalizerContext for testing.
     *              Used by both CursorBatchCoordinatorFinalizerTest and CursorBatchWorkerFinalizerTest.
     */
    public class MockFinalizerContext implements System.FinalizerContext {
        private System.ParentJobResult result;
        private Exception ex;
        
        /**
         * @description Constructs a mock finalizer context with the specified result.
         * @param result The parent job result (SUCCESS or failure type)
         */
        public MockFinalizerContext(System.ParentJobResult result) {
            this.result = result;
            if (result != System.ParentJobResult.SUCCESS) {
                // Use QueryException for coordinator failures, AsyncException for worker failures
                // Default to QueryException, but can be overridden via setException()
                this.ex = new System.QueryException('Mock cursor timeout');
            }
        }
        
        /**
         * @description Sets a custom exception for testing.
         * @param e The exception to set
         */
        public void setException(Exception e) {
            this.ex = e;
        }
        
        /**
         * @description Sets the exception to null for testing null exception scenarios.
         */
        public void setExceptionToNull() {
            this.ex = null;
        }
        
        public Id getAsyncApexJobId() {
            String prefix = AsyncApexJob.SObjectType.getDescribe().getKeyPrefix();
            return Id.valueOf(prefix + '000000000001');
        }
        
        public Exception getException() {
            return this.ex;
        }
        
        public String getRequestId() {
            return 'testRequestId';
        }
        
        public System.ParentJobResult getResult() {
            return this.result;
        }
    }
}