# Unpackaged Metadata

This directory contains metadata that is **NOT included in the CursorBatchFramework unlocked package** but is useful for package subscribers. Deploy these components separately after installing the package.

## Contents

| Category | Files | Purpose |
|----------|-------|---------|
| **Platform Event Config** | `platformEventSubscriberConfigs/` | Required trigger configuration with org-specific running user |
| **Sample Implementations** | `classes/Sample*.cls` | Example coordinators and workers demonstrating usage patterns |
| **Logger Adapter** | `classes/CursorBatchLoggerAdapter.cls` | Optional template for routing framework logging into Nebula Logger, Pharos, or a custom logger |
| **CSV Middleware Credentials** | `namedCredentials/`, `externalCredentials/` | Templates for CSV middleware connectivity |

---

## 1. Platform Event Subscriber Configs (Required)

The framework uses **three** Platform Event triggers that require subscriber configurations. These are intentionally **NOT included in the package** for two reasons:

1. **Org-specific user**: The configs require a running user that must be valid in your specific org
2. **Upgrade safety**: By keeping these outside the package, your customizations are preserved during package upgrades

| Config File | Trigger | Platform Event | Purpose |
|-------------|---------|----------------|---------|
| `CursorBatchCoordinatorTriggerConfig` | `CursorBatchCoordinatorTrigger` | `CursorBatch_Coordinator__e` | Enqueues the coordinator queueable, ensuring it runs as the dedicated user |
| `CursorBatchWorkerTriggerConfig` | `CursorBatchWorkerTrigger` | `CursorBatch_Worker__e` | Spawns Queueable workers from coordinator fanout events |
| `CursorBatchWorkerCompleteTriggerConfig` | `CursorBatchWorkerCompleteTrigger` | `CursorBatch_WorkerComplete__e` | Handles worker completion, updates job tracking, invokes `finish()` callback |

> **Important:** All three triggers **must use the same user**. This is critical because `Database.Cursor` is only accessible by the user who created it. By running all triggers as the same user, the coordinator creates the cursor, and workers can access it.

### Post-Install Setup (Required)

After installing the CursorBatchFramework package, deploy all three Platform Event Subscriber Configs:

#### Option 1: Deploy as-is (uses default user)

```bash
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs/
```

#### Option 2: Customize the running user

1. Edit all three config files in `platformEventSubscriberConfigs/`:
   - `CursorBatchCoordinatorTriggerConfig.platformEventSubscriberConfig-meta.xml`
   - `CursorBatchWorkerTriggerConfig.platformEventSubscriberConfig-meta.xml`
   - `CursorBatchWorkerCompleteTriggerConfig.platformEventSubscriberConfig-meta.xml`

2. Update the `<user>` element in each file with your desired running user (must be the **same user** in all three):

**CursorBatchCoordinatorTriggerConfig** (enqueues coordinator):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PlatformEventSubscriberConfig xmlns="http://soap.sforce.com/2006/04/metadata">
    <batchSize>1</batchSize>
    <isProtected>true</isProtected>
    <masterLabel>CursorBatchCoordinatorTriggerConfig</masterLabel>
    <platformEventConsumer>CursorBatchCoordinatorTrigger</platformEventConsumer>
    <user>your-integration-user@example.com</user>
</PlatformEventSubscriberConfig>
```

**CursorBatchWorkerTriggerConfig** (spawns workers):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PlatformEventSubscriberConfig xmlns="http://soap.sforce.com/2006/04/metadata">
    <batchSize>50</batchSize>
    <isProtected>true</isProtected>
    <masterLabel>CursorBatchWorkerTriggerConfig</masterLabel>
    <platformEventConsumer>CursorBatchWorkerTrigger</platformEventConsumer>
    <user>your-integration-user@example.com</user>
</PlatformEventSubscriberConfig>
```

**CursorBatchWorkerCompleteTriggerConfig** (handles completion):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PlatformEventSubscriberConfig xmlns="http://soap.sforce.com/2006/04/metadata">
    <batchSize>50</batchSize>
    <isProtected>true</isProtected>
    <masterLabel>CursorBatchWorkerCompleteTriggerConfig</masterLabel>
    <platformEventConsumer>CursorBatchWorkerCompleteTrigger</platformEventConsumer>
    <user>your-integration-user@example.com</user>
</PlatformEventSubscriberConfig>
```

3. Deploy:

```bash
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs/
```

#### Option 3: Configure via Setup UI

Configure each trigger subscription in Setup:

1. **Coordinator Trigger**: Setup → Platform Events → `CursorBatch_Coordinator__e` → Subscriptions
2. **Worker Trigger**: Setup → Platform Events → `CursorBatch_Worker__e` → Subscriptions
3. **Completion Trigger**: Setup → Platform Events → `CursorBatch_WorkerComplete__e` → Subscriptions

### Why All Three Configs Are Required

| Config | What Happens Without It |
|--------|------------------------|
| **CoordinatorTriggerConfig** | Coordinator won't run — `submit()` publishes event but trigger runs as Automated Process user (lacks permissions) |
| **WorkerTriggerConfig** | Workers won't spawn — coordinator publishes events but trigger runs as Automated Process user (lacks permissions) |
| **WorkerCompleteTriggerConfig** | `finish()` callback won't fire — worker completions are tracked but coordinator isn't notified |

### Why All Three Must Use the Same User

`Database.Cursor` is only accessible to the user who created it. The framework routes the coordinator through a Platform Event trigger so that:

1. The coordinator runs as the dedicated trigger user and creates the cursor
2. Workers also run as the dedicated trigger user and can access the cursor
3. If different users were used, workers would fail with cursor access errors

### Important Notes

- These configs are **required** for the framework to function properly
- All three configurations are **your responsibility** to maintain
- Package upgrades will **never** overwrite your configurations (they're not in the package)
- If you don't deploy these, the Platform Event triggers will run as Automated Process user (which lacks permissions)
- All three triggers **must use the same running user** for cursor access to work

---

## 2. Sample Coordinators and Workers

Sample implementations demonstrating common usage patterns for the CursorBatch Framework.

| Sample | Pattern | Description |
|--------|---------|-------------|
| `SampleLeadCoordinator` + `SampleLeadWorker` | Simple single-object | Query and process Lead records directly |
| `SampleAccountOpportunityCoordinator` + `SampleAccountOpportunityWorker` | Parent/child | Query Accounts, process their Opportunities (avoids record locks) |
| `SampleStatefulLeadQueryBuilder` + `SampleStatefulLeadWorker` + `SampleStatefulLeadReducer` | Reducer-based `CursorJob` state | Read state snapshots in workers and merge page deltas centrally |

### Simple Pattern: Lead Processing

The Lead sample demonstrates the most common pattern where the coordinator queries records and the worker updates them directly.

```apex
// Execute the sample Lead job
new SampleLeadCoordinator().submit();
```

**Setup Required:**
- Create `CursorBatch_Config__mdt` record with `MasterLabel = 'SampleLeadJob'`
- Set `Active__c = true`

### Parent/Child Pattern: Account/Opportunity Processing

The Account/Opportunity sample demonstrates the parent/child pattern for **avoiding record lock contention** when processing child records in parallel.

```apex
// Execute the sample Account/Opportunity job
new SampleAccountOpportunityCoordinator().submit();
```

**Setup Required:**
- Create `CursorBatch_Config__mdt` record with `MasterLabel = 'SampleAccountOpportunityJob'`
- Set `Active__c = true`

> **See the main [README.md](../README.md#parentchild-pattern-for-avoiding-record-locks)** for a detailed explanation of this pattern and when to use it.

### Reducer-Based Stateful Pattern: CursorJob Lead Processing

The stateful Lead sample demonstrates the reducer-based shared-state API for metadata-driven `CursorJob` jobs.

```apex
// Execute the reducer-enabled sample job
CursorJob.run('SampleStatefulLeadJob');
```

**What it shows:**
- `SampleStatefulLeadQueryBuilder` provides the cursor query
- `SampleStatefulLeadWorker` reads `getCurrentState()` before processing each page
- `SampleStatefulLeadWorker.buildStateDelta()` emits a page delta after successful processing
- `SampleStatefulLeadReducer` merges those deltas into `CursorBatch_Job__c.State_JSON__c`
- `SampleStatefulLeadWorker.finish()` reads the final reduced state

**Setup Required:**
- Create `CursorBatch_Config__mdt` record with `MasterLabel = 'SampleStatefulLeadJob'`
- Set `Active__c = true`
- Set `Query_Builder_Class__c = 'SampleStatefulLeadQueryBuilder'`
- Set `Query_Builder_Method__c = 'buildOpenLeadQuery'`
- Set `Worker_Class__c = 'SampleStatefulLeadWorker'`
- Set `State_Reducer_Class__c = 'SampleStatefulLeadReducer'`

---

### CSV File Processing Pattern

The CSV samples demonstrate file-based processing using the same framework features as SOQL jobs.

| Sample | Description |
|--------|-------------|
| `SampleCsvLeadWorker` | Processes CSV rows and upserts Lead records by Email |
| `SampleCsvStatefulWorker` | CSV worker with reducer-based shared state and `finish()` callback |

```apex
// Process a CSV file
CursorJob.run('SampleCsvLeadJob', new Map<String, Object>{
    'contentVersionId' => '068xx...'
});

// CSV job with stateful reducer
CursorJob.run('SampleCsvStatefulJob', new Map<String, Object>{
    'contentVersionId' => '068xx...'
});
```

**Setup Required:**

1. Deploy the Named Credential and External Credential from `unpackaged/namedCredentials/` and `unpackaged/externalCredentials/`
2. Update the Named Credential URL to point at your [cursor-csv](https://github.com/ndrg2010/cursor-csv) middleware instance
3. Create `CursorBatch_Config__mdt` records:
   - `MasterLabel = 'SampleCsvLeadJob'`, `Processing_Type__c = 'CSV'`, `Worker_Class__c = 'SampleCsvLeadWorker'`
   - `MasterLabel = 'SampleCsvStatefulJob'`, `Processing_Type__c = 'CSV'`, `Worker_Class__c = 'SampleCsvStatefulWorker'`, `Enable_State_Reducer__c = true`

---

## 3. Logger Adapter

Optional adapter that routes framework logging into your org's logging framework — [Nebula Logger](https://github.com/jongpie/NebulaLogger), Pharos, a custom logging object, or anything else. `classes/CursorBatchLoggerAdapter.cls` is a fill-in-the-blanks template: it implements `ICursorBatchLogger` and `Callable`, falls back to `System.debug`, and marks with `TODO` every place your logging framework's calls belong.

### Prerequisites

- Your logging framework installed in the org (for Nebula Logger, an `ILogger` interface that Nebula Logger implements)

### Usage

There is no wiring code. The framework discovers the adapter by class name and tags it from metadata.

**1. Deploy a class named exactly `CursorBatchLoggerAdapter`** implementing both `ICursorBatchLogger` and `Callable`. Start from the template and replace the `TODO` markers with your logging framework's calls:

```bash
sf project deploy start --source-dir unpackaged/classes/CursorBatchLoggerAdapter.cls
```

**2. Set `Logger_Tag__c`** on each job's `CursorBatch_Config__mdt` record, e.g. `Billing Engine`.

**3. Write no constructor.** Coordinators and workers resolve the adapter by convention and are tagged automatically:

```apex
public class MyWorker extends CursorBatchWorker {

    public override void process(List<SObject> records) {
        logger.logInfo('Processing ' + records.size() + ' records');  // tagged 'Billing Engine'
    }

    public override void finish(CursorBatch_Job__c jobRecord) {
        logger.logInfo('Job done');  // also tagged 'Billing Engine'
    }
}
```

> **Do not call `setLogger()`.** As of v0.33.0 the framework applies `Logger_Tag__c` on both the processing path (`initialize()`) and the `finish()` path (`initializeFinishState()` / `initializeJobName()`). A `setLogger()` call placed inside `finish()` runs *after* the framework has tagged the logger, and replaces that tagged instance with an untagged one — stripping the tag from everything logged afterwards.

> **`Callable` is not optional.** The framework hands `Logger_Tag__c` to the adapter through `Callable.call('addTag', ...)` so it needs no compile-time dependency on a class it doesn't own. An adapter that implements `ICursorBatchLogger` but **not** `Callable` still logs, but can never receive `Logger_Tag__c` — its tags can only ever be hardcoded at the call site.

### Customization

Wire the adapter to your logging framework by filling in the `TODO` markers. For Nebula Logger resolved through a dependency-injection layer:

```apex
// In the constructor
this.nebulaLogger = (ILogger) Application.Service.newInstance(ILogger.class);

// In logInfo() / logError() / logException()
ILogEntryBuilder entry = nebulaLogger.info(LOG_PREFIX + message);
if (!this.tags.isEmpty()) {
    entry.addTags(this.tags);
}
nebulaLogger.save();
```

Or calling Nebula Logger directly, with no DI layer:

```apex
Logger.info(LOG_PREFIX + message).addTags(new List<String>(this.tags));
Logger.saveLog();
```

Keep the `tags` set, `addTag()`, `addTags()`, and `call()` intact — that is the path `Logger_Tag__c` and the framework's scope tags travel through.

---

## Deployment

### Deploy All Unpackaged Components

```bash
sf project deploy start --source-dir unpackaged/
```

### Deploy Specific Components

```bash
# Platform Event Config only (required)
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs/

# Sample classes only (optional, for learning/templates)
sf project deploy start --source-dir unpackaged/classes/SampleLeadCoordinator.cls
sf project deploy start --source-dir unpackaged/classes/SampleLeadWorker.cls
sf project deploy start --source-dir unpackaged/classes/SampleAccountOpportunityCoordinator.cls
sf project deploy start --source-dir unpackaged/classes/SampleAccountOpportunityWorker.cls
sf project deploy start --source-dir unpackaged/classes/SampleStatefulLeadQueryBuilder.cls
sf project deploy start --source-dir unpackaged/classes/SampleStatefulLeadWorker.cls
sf project deploy start --source-dir unpackaged/classes/SampleStatefulLeadReducer.cls

# Logger adapter only (optional, must be named CursorBatchLoggerAdapter for discovery)
sf project deploy start --source-dir unpackaged/classes/CursorBatchLoggerAdapter.cls
```

### After Deployment

1. **Create Config Records**: For each sample you want to run, create a `CursorBatch_Config__mdt` record with matching `MasterLabel`
2. **Assign Permissions**: Assign the `Cursor Batch Job Viewer` permission set to users who need to monitor jobs
3. **Test**: Execute a sample job to verify the framework is working correctly

```apex
// Test Lead processing
new SampleLeadCoordinator().submit();

// Test Account/Opportunity processing
new SampleAccountOpportunityCoordinator().submit();

// Test reducer-based stateful processing
CursorJob.run('SampleStatefulLeadJob');
```
