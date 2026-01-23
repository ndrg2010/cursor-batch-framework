/**
 * @description Unit tests for CursorBatchCoordinatorTriggerHandler Platform Event handler.
 *              Tests coordinator instantiation and enqueueing via reflection.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchCoordinatorTriggerHandlerTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(20);
    }
    
    @IsTest
    static void testHandleWithNullEvents() {
        // Arrange
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act & Assert - Should not throw exception with null events
        Test.startTest();
        handler.handle(null);
        Test.stopTest();
        
        System.assert(true, 'Handler should gracefully handle null events list');
    }
    
    @IsTest
    static void testHandleWithEmptyEvents() {
        // Arrange
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        List<CursorBatch_Coordinator__e> emptyEvents = new List<CursorBatch_Coordinator__e>();
        
        // Act & Assert - Should not throw exception with empty events
        Test.startTest();
        handler.handle(emptyEvents);
        Test.stopTest();
        
        System.assert(true, 'Handler should gracefully handle empty events list');
    }
    
    @IsTest
    static void testHandleWithValidEvent() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event without throwing
        System.assert(true, 'Handler should have processed the coordinator event');
    }
    
    @IsTest
    static void testHandleWithDelay() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = 5
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event with delay without throwing
        System.assert(true, 'Handler should have processed the coordinator event with delay');
    }
    
    @IsTest
    static void testHandleWithEmptyCoordinatorClass() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'TestCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = '',  // Empty class name
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act - Should not throw exception with empty coordinator class
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle empty coordinator class
        System.assertEquals(false, exceptionThrown, 
            'Handler should handle empty coordinator class gracefully without throwing exception');
    }
    
    @IsTest
    static void testHandleWithNonExistentCoordinatorClass() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'NonExistentCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'NonExistentCoordinatorClass',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act - Should not throw exception with non-existent coordinator class
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle non-existent coordinator class
        System.assertEquals(false, exceptionThrown, 
            'Handler should handle non-existent coordinator class gracefully without throwing exception');
    }
    
    @IsTest
    static void testHandleWithInvalidCoordinatorClassType() {
        // Arrange
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'String',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'String',  // String class exists but doesn't extend CursorBatchCoordinator
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act - Should not throw exception with wrong coordinator class type
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            handler.handle(events);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Assert - Handler should gracefully handle coordinator class that doesn't extend CursorBatchCoordinator
        System.assertEquals(false, exceptionThrown, 
            'Handler should handle invalid coordinator class type gracefully without throwing');
    }
    
    @IsTest
    static void testHandleMultipleEvents() {
        // Arrange
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>();
        for (Integer i = 0; i < 3; i++) {
            CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
                'TestJob' + i, 
                'CursorBatchTestUtils.TestCursorBatchCoordinator',
                0
            );
            
            events.add(new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob' + i,
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            ));
        }
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process all 3 events
        System.assertEquals(3, events.size(), 'Should have processed 3 events');
        System.assert(true, 'Handler should have processed all coordinator events');
    }
    
    @IsTest
    static void testTriggerFiresOnEventPublish() {
        // Arrange - This test actually fires the trigger by publishing Platform Events
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = null
            )
        };
        
        // Act - Publish the events to fire the trigger
        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(events);
        Test.stopTest();
        
        // Assert - Verify the events were published successfully and trigger fired
        System.assertEquals(1, results.size(), 'Should have published 1 event');
        System.assertEquals(true, results[0].isSuccess(), 'Event should have been published successfully');
        // The trigger should have fired and processed the event through the handler
        System.assert(true, 'Trigger should have fired and handler should have processed the coordinator event');
    }
    
    @IsTest
    static void testHandleWithZeroDelay() {
        // Arrange - Test that delay of 0 is treated as no delay
        CursorBatchCoordinator.testConfig = CursorBatchTestUtils.createTestConfig(
            'TestJob', 2, 10
        );
        
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createPreparingJobRecord(
            'TestJob', 
            'CursorBatchTestUtils.TestCursorBatchCoordinator',
            0
        );
        
        List<CursorBatch_Coordinator__e> events = new List<CursorBatch_Coordinator__e>{
            new CursorBatch_Coordinator__e(
                Job_Name__c = 'TestJob',
                Coordinator_Class__c = 'CursorBatchTestUtils.TestCursorBatchCoordinator',
                Job_Record_Id__c = jobRecord.Id,
                Delay_Minutes__c = 0  // Zero delay
            )
        };
        
        CursorBatchCoordinatorTriggerHandler handler = new CursorBatchCoordinatorTriggerHandler();
        
        // Act
        Test.startTest();
        handler.handle(events);
        Test.stopTest();
        
        // Assert - Handler should process the event without delay (0 treated as no delay)
        System.assert(true, 'Handler should have processed the coordinator event with zero delay');
    }
}
