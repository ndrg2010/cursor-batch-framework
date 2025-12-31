/**
 * @description Unit tests for CursorBatchCoordinator abstract base class.
 *              Uses MockCursorBatchCacheService to avoid Platform Cache dependency.
 * @group CursorBatchFramework
 */
@IsTest
private class CursorBatchCoordinatorTest {
    
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
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert - In test context, the job executes synchronously
        System.assert(true, 'Submit should complete without exception');
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
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, coordinator.onCompleteCalled, 
            'onComplete should be called after execution');
        
        // Verify job record was created
        List<CursorBatch_Job__c> jobs = [SELECT Id, Job_Name__c, Total_Workers__c, Status__c 
                                          FROM CursorBatch_Job__c WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(1, jobs.size(), 'Should create one job record');
        System.assertEquals('Running', jobs[0].Status__c, 'Job should be in Running status');
        System.assert(jobs[0].Total_Workers__c > 0, 'Should have workers assigned');
    }
    
    @IsTest
    static void testExecuteWithZeroRecords() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob', 
                'SELECT Id FROM Account WHERE Name = \'NonExistentAccount12345\'');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act & Assert
        Test.startTest();
        try {
            coordinator.execute(null);
            System.assert(true, 'Coordinator should handle zero-record query exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Invalid Apex cursor') || 
                         e.getMessage().contains('cursor'), 
                'Should throw cursor-related exception for zero records');
        }
        Test.stopTest();
        
        // Verify no job record was created
        List<CursorBatch_Job__c> jobs = [SELECT Id FROM CursorBatch_Job__c WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(0, jobs.size(), 'Should not create job record for zero records');
    }
    
    @IsTest
    static void testExecuteWithMissingConfig() {
        // Arrange
        CursorBatchCoordinator.testConfig = null;
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('NonExistentJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
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
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setLogger(mockLogger);
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
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
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
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
        jobRecord.Status__c = 'Complete';
        jobRecord.Completed_Workers__c = 5;
        
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
        String customQuery = 'SELECT Id, Name, Description FROM Account WHERE Name LIKE \'Test%\'';
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob', customQuery);
        
        // Act
        Test.startTest();
        String query = coordinator.buildQuery();
        Test.stopTest();
        
        // Assert
        System.assertEquals(customQuery, query, 'Should return custom query');
    }
    
    @IsTest
    static void testWorkerDistribution() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 3, 10
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> jobs = [SELECT Total_Workers__c FROM CursorBatch_Job__c 
                                          WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(1, jobs.size(), 'Should have one job');
        System.assert(jobs[0].Total_Workers__c <= 3, 'Should not exceed requested worker count');
    }
    
    @IsTest
    static void testExceptionHandling() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatchTestUtils.MockCursorBatchLogger mockLogger = 
            new CursorBatchTestUtils.MockCursorBatchLogger();
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob', 
                'SELECT InvalidField FROM Account');
        coordinator.setLogger(mockLogger);
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
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
    static void testExecuteWithCustomCacheTTL() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 5, 20, 4
        );
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, coordinator.onCompleteCalled, 
            'onComplete should be called with custom TTL config');
        
        List<CursorBatch_Job__c> jobs = [SELECT Id, Job_Name__c FROM CursorBatch_Job__c 
                                          WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(1, jobs.size(), 'Should create job record with custom TTL');
    }
    
    @IsTest
    static void testExecuteWithNullCacheTTL_UsesDefault() {
        // Arrange
        CursorBatch_Config__mdt config = new CursorBatch_Config__mdt(
            MasterLabel = 'TestJob',
            Parallel_Count__c = 5,
            Page_Size__c = 20,
            Cache_TTL_Hours__c = null,
            Active__c = true
        );
        CursorBatchCoordinator.testConfig = config;
        
        CursorBatchTestUtils.TestCursorBatchCoordinator coordinator = 
            new CursorBatchTestUtils.TestCursorBatchCoordinator('TestJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.execute(null);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, coordinator.onCompleteCalled, 
            'onComplete should be called with default TTL');
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
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> runningJobs = [
            SELECT Id FROM CursorBatch_Job__c 
            WHERE Job_Name__c = 'DuplicateTestJob' 
            AND Status__c = 'Running'
        ];
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
        completedJob.Status__c = 'Complete';
        update completedJob;
        
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'CompletedTestJob', 5, 20
        );
        
        CursorBatchTestUtils.DuplicateCheckCoordinator coordinator = 
            new CursorBatchTestUtils.DuplicateCheckCoordinator('CompletedTestJob');
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> newJobs = [
            SELECT Id FROM CursorBatch_Job__c 
            WHERE Job_Name__c = 'CompletedTestJob' 
            AND Status__c = 'Running'
        ];
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
        coordinator.setCacheService(new MockCursorBatchCacheService());
        
        // Act
        Test.startTest();
        coordinator.submit();
        Test.stopTest();
        
        // Assert
        List<CursorBatch_Job__c> newJobs = [
            SELECT Id FROM CursorBatch_Job__c 
            WHERE Job_Name__c = 'NewTestJob' 
            AND Status__c = 'Running'
        ];
        System.assertEquals(1, newJobs.size(), 
            'Job should execute when no existing jobs');
    }
}
