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
     * @description Processes a single event by instantiating and enqueueing a handler.
     *              Supports two flows:
     *              1. Standard coordinators (extends CursorBatchCoordinator) -- initialized
     *                 with job name and record ID, then enqueued with optional delay.
     *              2. External callback handlers (implements Queueable but not a coordinator)
     *                 -- PE fields passed via Callable interface, then enqueued immediately.
     *                 Used by CSV_Ready for middleware Platform Event callbacks.
     * @param evt CursorBatch_Coordinator__e event containing handler parameters
     */
    private void processEvent(CursorBatch_Coordinator__e evt) {
        try {
            String handlerClassName = evt.Coordinator_Class__c;
            
            if (String.isBlank(handlerClassName)) {
                logger.logError('CursorBatchCoordinatorTriggerHandler: Coordinator class name not specified for job "' + evt.Job_Name__c + '"');
                return;
            }
            
            Type handlerType = Type.forName(handlerClassName);
            if (handlerType == null) {
                logger.logError('CursorBatchCoordinatorTriggerHandler: Class not found: ' + handlerClassName);
                return;
            }
            
            Object instance = handlerType.newInstance();
            
            if (instance instanceof CursorBatchCoordinator) {
                CursorBatchCoordinator coordinator = (CursorBatchCoordinator) instance;
                coordinator.initializeJobName(evt.Job_Name__c);
                coordinator.setJobRecordId(Id.valueOf(evt.Job_Record_Id__c));
                enqueueCoordinator(coordinator, evt);
            } else if (instance instanceof Queueable) {
                if (instance instanceof Callable) {
                    ((Callable) instance).call('handlePlatformEvent', new Map<String, Object>{
                        'Job_Record_Id__c' => evt.Job_Record_Id__c,
                        'Job_Name__c' => evt.Job_Name__c,
                        'Coordinator_Class__c' => evt.Coordinator_Class__c
                    });
                }
                enqueueCallbackHandler((Queueable) instance, handlerClassName);
            } else {
                logger.logError(
                    'CursorBatchCoordinatorTriggerHandler: Class "' + handlerClassName +
                    '" must extend CursorBatchCoordinator or implement Queueable'
                );
            }
            
        } catch (Exception e) {
            logger.logException('CursorBatchCoordinatorTriggerHandler: Error processing event for job "' + evt.Job_Name__c + '"', e);
        }
    }
    
    /**
     * @description Enqueues an external callback handler (non-coordinator Queueable).
     * @param handler Queueable instance with PE data already set via Callable
     * @param className Class name for logging
     */
    private void enqueueCallbackHandler(Queueable handler, String className) {
        if (!Test.isRunningTest()) {
            System.enqueueJob(handler);
            logger.logInfo('CursorBatchCoordinatorTriggerHandler: Enqueued callback handler ' + className);
        }
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
