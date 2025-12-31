/**
 * @description Test utilities for CursorBatchFramework including concrete implementations
 *              of abstract classes and mock objects for testing.
 * @group CursorBatchFramework
 */
@IsTest
public class CursorBatchTestUtils {
    
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
        return createTestConfig(jobName, workerCount, pageSize, null);
    }
    
    /**
     * @description Creates a test configuration for cursor batch jobs with TTL.
     * @param jobName Job name/label
     * @param workerCount Number of workers
     * @param pageSize Page size for cursor fetching
     * @param cacheTtlHours Cache TTL in hours (null for default)
     * @return CursorBatch_Config__mdt instance (not inserted - custom metadata)
     */
    public static CursorBatch_Config__mdt createTestConfig(
        String jobName, 
        Integer workerCount, 
        Integer pageSize,
        Integer cacheTtlHours
    ) {
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = jobName,
            Parallel_Count__c = workerCount,
            Page_Size__c = pageSize,
            Cache_TTL_Hours__c = cacheTtlHours,
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
        CursorBatch_Job__c job = new CursorBatch_Job__c(
            Job_Name__c = jobName,
            Total_Workers__c = totalWorkers,
            Completed_Workers__c = 0,
            Failed_Workers__c = 0,
            Status__c = 'Running',
            Coordinator_Class__c = coordinatorClass,
            Cache_Key__c = 'TestCacheKey' + System.currentTimeMillis(),
            Started_At__c = System.now()
        );
        insert job;
        return job;
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
            this.testQuery = 'SELECT Id, Name FROM Account ORDER BY Name';
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
            return 'SELECT Id, Name FROM Account ORDER BY Name';
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
        
        public TestCursorBatchWorker() {
            super();
        }
        
        public override void process(List<SObject> records) {
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
}

