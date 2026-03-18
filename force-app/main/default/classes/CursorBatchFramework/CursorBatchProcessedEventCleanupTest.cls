/**
 * @description Unit tests for CursorBatchProcessedEventCleanup Queueable.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchProcessedEventCleanupTest {
    
    @TestSetup
    static void setup() {
        CursorBatchTestUtils.createTestAccounts(5);
    }
    
    @IsTest
    static void testCleanupDeletesProcessedEventsForJobIds() {
        CursorBatch_Job__c jobRecord = CursorBatchTestUtils.createTestJobRecord(
            'TestJob', 1, 'CursorBatchTestUtils.TestCursorBatchCoordinator'
        );
        insert new List<CursorBatch_Processed_Event__c>{
            new CursorBatch_Processed_Event__c(
                Cursor_Batch_Job__c = jobRecord.Id,
                Replay_Id__c = 'replay-1',
                Processed_Event_Key__c = jobRecord.Id + '#replay-1'
            ),
            new CursorBatch_Processed_Event__c(
                Cursor_Batch_Job__c = jobRecord.Id,
                Replay_Id__c = 'replay-2',
                Processed_Event_Key__c = jobRecord.Id + '#replay-2'
            )
        };
        Assert.areEqual(2, [SELECT COUNT() FROM CursorBatch_Processed_Event__c WHERE Cursor_Batch_Job__c = :jobRecord.Id],
            'Setup: should have 2 processed events');
        
        Test.startTest();
        System.enqueueJob(new CursorBatchProcessedEventCleanup(new Set<Id>{ jobRecord.Id }));
        Test.stopTest();
        
        Integer remaining = [SELECT COUNT() FROM CursorBatch_Processed_Event__c WHERE Cursor_Batch_Job__c = :jobRecord.Id];
        Assert.areEqual(0, remaining, 'Queueable should delete all processed events for the job');
    }
    
    @IsTest
    static void testCleanupWithEmptySetDoesNothing() {
        Test.startTest();
        System.enqueueJob(new CursorBatchProcessedEventCleanup(new Set<Id>()));
        Test.stopTest();
        // No exception; empty set is handled
        Assert.isTrue(true, 'Empty job IDs should not throw');
    }
}
