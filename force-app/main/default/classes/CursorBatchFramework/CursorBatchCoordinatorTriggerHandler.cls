/**
 * @description Handles CursorBatch_Coordinator__e Platform Events. Instantiates and enqueues
 *              coordinator queueables using dynamic instantiation. This ensures the coordinator
 *              runs as the dedicated trigger user (from PlatformEventSubscriberConfig), which is
 *              required for cursor access by workers running as the same user.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 * @see CursorBatchWorkerTriggerHandler
 */
public without sharing class CursorBatchCoordinatorTriggerHandler {
    
    private ICursorBatchLogger logger;
    
    /**
     * @description Default constructor initializing the logger.
     */
    public CursorBatchCoordinatorTriggerHandler() {
        this.logger = CursorBatchLogger.getDefault();
    }
    
    /**
     * @description Handles incoming Platform Events by creating and enqueueing coordinators.
     * @param events CursorBatch_Coordinator__e events from the Platform Event trigger
     */
    public void handle(List<CursorBatch_Coordinator__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        for (CursorBatch_Coordinator__e evt : events) {
            processEvent(evt);
        }
    }
    
    /**
     * @description Processes a single event by instantiating and enqueueing a coordinator.
     * @param evt CursorBatch_Coordinator__e event containing coordinator parameters
     */
    private void processEvent(CursorBatch_Coordinator__e evt) {
        try {
            String coordinatorClassName = evt.Coordinator_Class__c;
            
            if (String.isBlank(coordinatorClassName)) {
                logger.logError('CursorBatchCoordinatorTriggerHandler: Coordinator class name not specified for job "' + evt.Job_Name__c + '"');
                return;
            }
            
            CursorBatchCoordinator coordinator = createCoordinatorInstance(
                coordinatorClassName, 
                evt.Job_Name__c, 
                evt.Job_Record_Id__c
            );
            
            if (coordinator == null) {
                return;
            }
            
            enqueueCoordinator(coordinator, evt);
            
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinatorTriggerHandler: Error processing event for job "' + evt.Job_Name__c + '"', e);
        }
    }
    
    /**
     * @description Creates a coordinator instance via reflection and initializes it with job context.
     * @param className Fully qualified API name of the coordinator class
     * @param jobName Job name for initialization
     * @param jobRecordId ID of the pre-created job record
     * @return Initialized CursorBatchCoordinator instance, or null on error
     */
    private CursorBatchCoordinator createCoordinatorInstance(String className, String jobName, String jobRecordId) {
        Type coordinatorType = Type.forName(className);
        if (coordinatorType == null) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: Coordinator class not found: ' + className);
            return null;
        }
        
        Object instance = coordinatorType.newInstance();
        if (!(instance instanceof CursorBatchCoordinator)) {
            logger.logError('CursorBatchCoordinatorTriggerHandler: Class "' + className + '" must extend CursorBatchCoordinator');
            return null;
        }
        
        CursorBatchCoordinator coordinator = (CursorBatchCoordinator) instance;
        coordinator.initializeJobName(jobName);
        coordinator.setJobRecordId(Id.valueOf(jobRecordId));
        
        return coordinator;
    }
    
    /**
     * @description Enqueues the coordinator, optionally with a delay.
     * @param coordinator Initialized coordinator instance
     * @param evt Platform Event containing delay configuration
     */
    private void enqueueCoordinator(CursorBatchCoordinator coordinator, CursorBatch_Coordinator__e evt) {
        Integer delayMinutes = evt.Delay_Minutes__c != null ? Integer.valueOf(evt.Delay_Minutes__c) : null;
        
        if (!Test.isRunningTest()) {
            if (delayMinutes != null && delayMinutes > 0) {
                System.enqueueJob(coordinator, delayMinutes);
                logger.logInfo('CursorBatchCoordinatorTriggerHandler: Enqueued ' + evt.Coordinator_Class__c + 
                    ' for job "' + evt.Job_Name__c + '" with ' + delayMinutes + ' min delay');
            } else {
                System.enqueueJob(coordinator);
                logger.logInfo('CursorBatchCoordinatorTriggerHandler: Enqueued ' + evt.Coordinator_Class__c + 
                    ' for job "' + evt.Job_Name__c + '"');
            }
        }
    }
}
