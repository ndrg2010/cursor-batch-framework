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
}