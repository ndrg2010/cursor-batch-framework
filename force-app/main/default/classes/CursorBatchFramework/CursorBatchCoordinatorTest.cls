/**
 * @description Unit tests for CursorBatchCoordinator abstract base class.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCoordinatorTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(100);
    }
    
    @IsTest
    static void testSubmitEnqueuesJob() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - In test context, the job executes synchronously
        // Verify job was created by checking for job records
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('TestJob');
        System.assertEquals(1, jobs.size(), 'Should create one job record');
    }
    
    @IsTest
    static void testSubmitBlockedByDuplicateCheck() {
        // Arrange
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.shouldBlockDuplicate = true;
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - Job should not be enqueued due to duplicate check
        System.assertEquals(false, coordinator.onCompleteCalled, 
            'Job should not execute when duplicate check returns true');
    }
    
    @IsTest
    static void testExecuteWithRecords() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('TestJob', 5, 20);
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, coordinator.onCompleteCalled, 
            'onComplete should be called after execution');
        
        // Verify job record was updated
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Processing', updatedJob.Status__c, 'Job should be in Processing status');
        System.assert(updatedJob.Total_Workers__c > 0, 'Should have workers assigned');
    }
    
    @IsTest
    static void testExecuteWithZeroRecords() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('TestJob', 5, 20);
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob', 
                'SELECT Id FROM Account WHERE Name = \'NonExistentAccount12345\'');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act & Assert - Database.getCursor throws FatalCursorException for zero records
        // This is expected behavior - coordinators should ensure their query returns records
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            coordinator.execute(null);
        } catch (System.FatalCursorException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Invalid Apex cursor'), 
                'Should throw FatalCursorException for zero records');
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            'Should throw FatalCursorException when query returns zero records');
    }
    
    @IsTest
    static void testExecuteWithMissingConfig() {
        // Arrange
        CursorBatchCoordinator.testConfig = null;
        
        // Create job record externally
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'NonExistentJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('NonExistentJob');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act & Assert
        Test.startTest();
        try {
            coordinator.execute(null);
            System.assert(false, 'Should throw exception for missing config');
        } catch (CursorBatchCoordinator.CursorBatchException e) {
            System.assert(e.getMessage().contains('No active config'), 
                'Exception should mention missing config');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testExecuteWithCustomLogger() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('TestJob', 2, 10);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setLogger(mockLogger);
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        System.assert(mockLogger.infoMessages.size() > 0, 'Should have logged info messages');
        System.assert(mockLogger.hasInfoContaining('query'), 'Should log query');
        System.assert(mockLogger.hasInfoContaining('totalRecords'), 'Should log total records');
    }
    
    @IsTest
    static void testExecuteWithDefaultWorkerAndPageSize() {
        // Arrange
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = 'TestJob',
            Parallel_Count__c = null,
            Page_Size__c = null,
            Active__c = true
        );
        CursorBatchCoordinator.testConfig = config;
        
        // Create job record externally
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, coordinator.onCompleteCalled, 
            'Should complete with default values');
    }
    
    @IsTest
    static void testGetConfigStatic() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'StaticTestJob', 10, 25
        );
        
        // Act
        Test.startTest();
        CursorBatch_Config__mdt config = CursorBatchCoordinator.getConfig('StaticTestJob');
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, config, 'Should return config');
        System.assertEquals('StaticTestJob', config.MasterLabel, 'Should have correct label');
        System.assertEquals(10, config.Parallel_Count__c, 'Should have correct worker count');
        System.assertEquals(25, config.Page_Size__c, 'Should have correct page size');
    }
    
    @IsTest
    static void testOnAllWorkersComplete() {
        // Arrange
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 5, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        jobRecord.Workers_Finished__c = 5;
        
        // Act
        Test.startTest();
        coordinator.finish(jobRecord);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, coordinator.finishCalled, 
            'finish callback should be invoked');
        System.assertEquals(jobRecord, coordinator.completedJobRecord, 
            'Should receive the job record');
    }
    
    @IsTest
    static void testBuildQueryAbstractMethod() {
        // Arrange
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        
        // Act
        Test.startTest();
        String query = coordinator.buildQuery();
        Test.stopTest();
        
        // Assert
        System.assertEquals(CursorBatchTestUtils.DEFAULT_TEST_QUERY, query, 'Should return default test query');
    }
    
    @IsTest
    static void testWorkerDistribution() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('TestJob', 3, 10);
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assert(updatedJob.Total_Workers__c <= 3, 'Should not exceed requested worker count');
    }
    
    @IsTest
    static void testExceptionHandling() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('TestJob', 2, 10);
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob', 
                'SELECT InvalidField FROM Account');
        coordinator.setLogger(mockLogger);
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        try {
            coordinator.execute(null);
            System.assert(false, 'Should throw exception for invalid query');
        } catch (Exception e) {
            // Expected
        }
        Test.stopTest();
        
        // Assert
        System.assert(mockLogger.exceptionMessages.size() > 0 || 
                      mockLogger.loggedExceptions.size() > 0, 
            'Should log exception');
    }
    
    @IsTest
    static void testCursorQueryIdExtraction() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('TestJob', 5, 20);
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert - Verify job record has cursor query ID
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertNotEquals(null, updatedJob.Cursor_Query_Id__c, 'Should have cursor query ID');
        System.assert(updatedJob.Cursor_Query_Id__c.length() > 0, 'Cursor query ID should not be empty');
    }
    
    @IsTest
    static void testIsJobAlreadyRunning_WithRunningJobRecord_ReturnsTrue() {
        // Arrange
        CursorBatch_Job__c runningJob = CursorBatchTestUtils.createTestJobRecord(
            'DuplicateTestJob', 5, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'DuplicateTestJob', 5, 20
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('DuplicateTestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> runningJobs = CursorBatchSelector.getRunningJobsByName('DuplicateTestJob');
        System.assertEquals(1, runningJobs.size(), 
            'Should still have only the original running job record');
        System.assertEquals(runningJob.Id, runningJobs[0].Id, 
            'Job should not execute when running job record exists');
    }
    
    @IsTest
    static void testIsJobAlreadyRunning_WithCompletedJobRecord_ReturnsFalse() {
        // Arrange
        CursorBatch_Job__c completedJob = CursorBatchTestUtils.createTestJobRecord(
            'CompletedTestJob', 5, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        completedJob.Status__c = 'Completed';
        update completedJob;
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'CompletedTestJob', 5, 20
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('CompletedTestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> newJobs = CursorBatchSelector.getRunningJobsByName('CompletedTestJob');
        System.assertEquals(1, newJobs.size(), 
            'Job should execute when no running job record exists');
    }
    
    @IsTest
    static void testIsJobAlreadyRunning_NoExistingJobs_ReturnsFalse() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'NewTestJob', 5, 20
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('NewTestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> newJobs = CursorBatchSelector.getRunningJobsByName('NewTestJob');
        System.assertEquals(1, newJobs.size(), 
            'Job should execute when no existing jobs');
    }
    
    @IsTest
    static void testSetJobRecordId() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'RetryTestJob', 5, 20
        );
        
        // Create an existing job in Preparing status (simulates retry scenario)
        CursorBatch_Job__c existingJob = CursorBatchTestUtils.createPreparingJobRecord(
            'RetryTestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 1
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('RetryTestJob');
        coordinator.setJobRecordId(existingJob.Id);
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert - Should reuse existing job record
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(existingJob.Id);
        System.assertEquals('Processing', updatedJob.Status__c, 'Job should be in Processing status');
        System.assertEquals(1, updatedJob.Total_Cursor_Retries__c, 'Retry count should be preserved');
    }
    
    @IsTest
    static void testCurrentAsyncJobIdExcludesCurrentJobFromDuplicateCheck() {
        // Arrange - Simulate being inside execute() by setting currentAsyncJobId
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'ExcludeTestJob', 5, 20
        );
        
        // Create a mock job ID to simulate current running job
        // Use a valid-looking AsyncApexJob ID format
        String prefix = AsyncApexJob.SObjectType.getDescribe().getKeyPrefix();
        Id mockCurrentJobId = Id.valueOf(prefix + '000000000001');
        
        // Set the static field to simulate being inside execute()
        CursorBatchCoordinator.currentAsyncJobId = mockCurrentJobId;
        
        try {
            CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
                new CursorBatchTestUtils.DuplicateCheckCoordinator('ExcludeTestJob');
            
            // Act
            Test.startTest();
            coordinator.submit();
            Test.stopTest();
            
            // Assert - Job should execute because we excluded the "current" job
            // (In real scenario, the current job would be in AsyncApexJob, but our mock ID
            // doesn't exist in the table, so this just verifies the code path works)
            List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('ExcludeTestJob');
            System.assertEquals(1, jobs.size(), 'Should create one job record when current job is excluded');
        } finally {
            // Clean up
            CursorBatchCoordinator.currentAsyncJobId = null;
        }
    }
    
    @IsTest
    static void testCurrentAsyncJobIdClearedAfterExecuteCompletes() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('ClearIdTestJob', 5, 20);
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('ClearIdTestJob');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Verify currentAsyncJobId starts as null
        System.assertEquals(null, CursorBatchCoordinator.currentAsyncJobId, 
            'currentAsyncJobId should be null before execute()');
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert - currentAsyncJobId should be cleared in finally block
        System.assertEquals(null, CursorBatchCoordinator.currentAsyncJobId, 
            'currentAsyncJobId should be null after execute() completes');
    }
    
    @IsTest
    static void testCurrentAsyncJobIdClearedAfterExecuteThrowsException() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.setupTestJob('ExceptionClearIdTestJob', 5, 20);
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('ExceptionClearIdTestJob',
                'SELECT InvalidField FROM Account');
        coordinator.setJobRecordId(jobRecord.Id);
        
        // Act
        Test.startTest();
        try {
            coordinator.execute(null);
        } catch (Exception e) {
            // Expected - invalid query
        }
        Test.stopTest();
        
        // Assert - currentAsyncJobId should be cleared even after exception
        System.assertEquals(null, CursorBatchCoordinator.currentAsyncJobId, 
            'currentAsyncJobId should be null after execute() throws exception');
    }
    
    @IsTest
    static void testGetRunningAsyncJobsByClassWithExcludeId() {
        // This test verifies the selector method works correctly with exclusion
        // We can't easily create real AsyncApexJob records, but we can verify the method runs
        
        // Act
        Test.startTest();
        
        // Test with null excludeJobId (should work like original method)
        List<AsyncApexJob> jobsWithoutExclude = 
            CursorBatchSelector.getRunningAsyncJobsByClass('CursorBatchTestUtils.TestCursorBatchCoordinator', null);
        
        // Test with a fake excludeJobId (should exclude it from results if it existed)
        String prefix = AsyncApexJob.SObjectType.getDescribe().getKeyPrefix();
        Id fakeJobId = Id.valueOf(prefix + '000000000001');
        List<AsyncApexJob> jobsWithExclude = 
            CursorBatchSelector.getRunningAsyncJobsByClass('CursorBatchTestUtils.TestCursorBatchCoordinator', fakeJobId);
        
        Test.stopTest();
        
        // Assert - Both should return empty since no real async jobs exist in test context
        System.assertEquals(0, jobsWithoutExclude.size(), 'Should return empty list without exclude');
        System.assertEquals(0, jobsWithExclude.size(), 'Should return empty list with exclude');
    }
    
    @IsTest
    static void testGetRunningAsyncJobsByClassWithEmptyClassName() {
        // Act
        Test.startTest();
        List<AsyncApexJob> jobsNull = CursorBatchSelector.getRunningAsyncJobsByClass(null, null);
        List<AsyncApexJob> jobsEmpty = CursorBatchSelector.getRunningAsyncJobsByClass('', null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(0, jobsNull.size(), 'Should return empty list for null className');
        System.assertEquals(0, jobsEmpty.size(), 'Should return empty list for empty className');
    }
    
    @IsTest
    static void testSkipDuplicateCheck_AllowsJobWhenRunningJobExists() {
        // Arrange - Create a running job record to simulate duplicate scenario
        CursorBatch_Job__c runningJob = CursorBatchTestUtils.createTestJobRecord(
            'SkipDuplicateTestJob', 5, 'CursorBatchTestUtils.DuplicateCheckCoordinator'
        );
        
        // Config with Skip_Duplicate_Check__c = true
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'SkipDuplicateTestJob', 5, 20, 3, 3, 1, true
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('SkipDuplicateTestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - Should have 2 job records: original + new one (duplicate check skipped)
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('SkipDuplicateTestJob');
        System.assertEquals(2, jobs.size(), 
            'Should create second job record when Skip_Duplicate_Check__c is enabled');
    }
    
    @IsTest
    static void testSkipDuplicateCheck_BlocksJobWhenDisabled() {
        // Arrange - Create a running job record to simulate duplicate scenario
        CursorBatch_Job__c runningJob = CursorBatchTestUtils.createTestJobRecord(
            'NoSkipDuplicateTestJob', 5, 'CursorBatchTestUtils.DuplicateCheckCoordinator'
        );
        
        // Config with Skip_Duplicate_Check__c = false (default)
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'NoSkipDuplicateTestJob', 5, 20, 3, 3, 1, false
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('NoSkipDuplicateTestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - Should still have only 1 job record (duplicate check blocked the new one)
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('NoSkipDuplicateTestJob');
        System.assertEquals(1, jobs.size(), 
            'Should not create second job record when Skip_Duplicate_Check__c is disabled');
        System.assertEquals(runningJob.Id, jobs[0].Id, 
            'Should still be the original job record');
    }
    
    @IsTest
    static void testSkipDuplicateCheck_LogsMessageWhenSkipping() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'SkipDuplicateLogTestJob', 5, 20, 3, 3, 1, true
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('SkipDuplicateLogTestJob');
        coordinator.setLogger(mockLogger);
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - Should log that duplicate check was skipped
        System.assert(mockLogger.hasInfoContaining('Skipping duplicate check'), 
            'Should log message about skipping duplicate check');
        System.assert(mockLogger.hasInfoContaining('Skip_Duplicate_Check__c enabled'), 
            'Should mention Skip_Duplicate_Check__c in log message');
    }
    
    @IsTest
    static void testSkipDuplicateCheck_DefaultsToFalse() {
        // Arrange - Config without explicitly setting Skip_Duplicate_Check__c
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'DefaultSkipTestJob', 5, 20
        );
        
        // Create a running job to test duplicate detection
        CursorBatch_Job__c runningJob = CursorBatchTestUtils.createTestJobRecord(
            'DefaultSkipTestJob', 5, 'CursorBatchTestUtils.DuplicateCheckCoordinator'
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('DefaultSkipTestJob');
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - Default behavior should block duplicates
        List<CursorBatch_Job__c> jobs = CursorBatchSelector.getRunningJobsByName('DefaultSkipTestJob');
        System.assertEquals(1, jobs.size(), 
            'Default config should block duplicate jobs (Skip_Duplicate_Check__c defaults to false)');
    }
    
    // ============================================
    // Kill Switch Tests
    // ============================================
    
    @IsTest
    static void testKillJob_CancelsRunningJob() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'KillTestJob', 5, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        System.assertEquals('Processing', jobRecord.Status__c, 'Job should start in Processing status');
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchCoordinator.killJob(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result, 'killJob should return true for running job');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Cancelled', updatedJob.Status__c, 'Status should be Cancelled');
        System.assertNotEquals(null, updatedJob.Completed_At__c, 'Completed_At should be set');
    }
    
    @IsTest
    static void testKillJob_ReturnsFalseForNonExistentJob() {
        // Arrange - Use a fake job ID
        Id fakeJobId = CursorBatch_Job__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchCoordinator.killJob(fakeJobId);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result, 'killJob should return false for non-existent job');
    }
    
    @IsTest
    static void testKillJob_ReturnsFalseForCompletedJob() {
        // Arrange - Create a completed job
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'CompletedKillTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Completed';
        jobRecord.Completed_At__c = System.now();
        update jobRecord;
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchCoordinator.killJob(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result, 'killJob should return false for completed job');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Completed', updatedJob.Status__c, 'Status should remain Completed');
    }
    
    @IsTest
    static void testKillJob_ReturnsFalseForFailedJob() {
        // Arrange - Create a failed job
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'FailedKillTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Failed';
        jobRecord.Completed_At__c = System.now();
        update jobRecord;
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchCoordinator.killJob(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result, 'killJob should return false for failed job');
    }
    
    @IsTest
    static void testKillJob_ReturnsFalseForAlreadyCancelledJob() {
        // Arrange - Create an already cancelled job
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'AlreadyCancelledTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Cancelled';
        jobRecord.Completed_At__c = System.now();
        update jobRecord;
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchCoordinator.killJob(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result, 'killJob should return false for already cancelled job');
    }
    
    @IsTest
    static void testKillJob_CancelsPreparingJob() {
        // Arrange - Create a job in Preparing status
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'PreparingKillTestJob', 'CursorBatchTestUtils.TestCursorBatchCoordinator', 0
        );
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchCoordinator.killJob(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result, 'killJob should return true for preparing job');
        CursorBatch_Job__c updatedJob = CursorBatchSelector.getJobById(jobRecord.Id);
        System.assertEquals('Cancelled', updatedJob.Status__c, 'Status should be Cancelled');
    }
    
    // ============================================
    // isJobCancelled Selector Tests
    // ============================================
    
    @IsTest
    static void testIsJobCancelled_ReturnsTrueForCancelledJob() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'CancelledCheckTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        jobRecord.Status__c = 'Cancelled';
        update jobRecord;
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchSelector.isJobCancelled(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result, 'Should return true for cancelled job');
    }
    
    @IsTest
    static void testIsJobCancelled_ReturnsFalseForProcessingJob() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'ProcessingCheckTestJob', 2, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        
        // Act
        Test.startTest();
        Boolean result = CursorBatchSelector.isJobCancelled(jobRecord.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result, 'Should return false for processing job');
    }
    
    @IsTest
    static void testIsJobCancelled_ReturnsFalseForNullId() {
        // Act
        Test.startTest();
        Boolean result = CursorBatchSelector.isJobCancelled(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result, 'Should return false for null job ID');
    }
}