# Unpackaged Metadata

This directory contains metadata that is **NOT included in the CursorBatchFramework unlocked package** but is useful for package subscribers. Deploy these components separately after installing the package.

## Contents

| Category | Files | Purpose |
|----------|-------|---------|
| **Platform Event Config** | `platformEventSubscriberConfigs/` | Required trigger configuration with org-specific running user |
| **Sample Implementations** | `classes/Sample*.cls` | Example coordinators and workers demonstrating usage patterns |
| **Nebula Logger Adapter** | `classes/NebulaLoggerAdapterForCursorBatch.cls` | Optional integration with Nebula Logger |

---

## 1. Platform Event Subscriber Configs (Required)

The framework uses **two** Platform Event triggers that require subscriber configurations. These are intentionally **NOT included in the package** for two reasons:

1. **Org-specific user**: The configs require a running user that must be valid in your specific org
2. **Upgrade safety**: By keeping these outside the package, your customizations are preserved during package upgrades

| Config File | Trigger | Platform Event | Purpose |
|-------------|---------|----------------|---------|
| `CursorBatchWorkerTriggerConfig` | `CursorBatchWorkerTrigger` | `CursorBatch_Worker__e` | Spawns Queueable workers from coordinator fanout events |
| `CursorBatchWorkerCompleteTriggerConfig` | `CursorBatchWorkerCompleteTrigger` | `CursorBatch_WorkerComplete__e` | Handles worker completion, updates job tracking, invokes `finish()` callback |

### Post-Install Setup (Required)

After installing the CursorBatchFramework package, deploy both Platform Event Subscriber Configs:

#### Option 1: Deploy as-is (uses default user)

```bash
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs/
```

#### Option 2: Customize the running user

1. Edit both config files in `platformEventSubscriberConfigs/`:
   - `CursorBatchWorkerTriggerConfig.platformEventSubscriberConfig-meta.xml`
   - `CursorBatchWorkerCompleteTriggerConfig.platformEventSubscriberConfig-meta.xml`

2. Update the `<user>` element in each file with your desired running user:

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

1. **Worker Trigger**: Setup → Platform Events → `CursorBatch_Worker__e` → Subscriptions
2. **Completion Trigger**: Setup → Platform Events → `CursorBatch_WorkerComplete__e` → Subscriptions

### Why Both Configs Are Required

| Config | What Happens Without It |
|--------|------------------------|
| **WorkerTriggerConfig** | Workers won't spawn — coordinator publishes events but trigger runs as Automated Process user (lacks permissions) |
| **WorkerCompleteTriggerConfig** | `finish()` callback won't fire — worker completions are tracked but coordinator isn't notified |

### Important Notes

- These configs are **required** for the framework to function properly
- Both configurations are **your responsibility** to maintain
- Package upgrades will **never** overwrite your configurations (they're not in the package)
- If you don't deploy these, the Platform Event triggers will run as Automated Process user (which lacks permissions)
- Both triggers should use the **same running user** for consistency

---

## 2. Sample Coordinators and Workers

Sample implementations demonstrating common usage patterns for the CursorBatch Framework.

| Sample | Pattern | Description |
|--------|---------|-------------|
| `SampleLeadCoordinator` + `SampleLeadWorker` | Simple single-object | Query and process Lead records directly |
| `SampleAccountOpportunityCoordinator` + `SampleAccountOpportunityWorker` | Parent/child | Query Accounts, process their Opportunities (avoids record locks) |

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

---

## 3. Nebula Logger Adapter

Optional adapter for integrating CursorBatch Framework logging with [Nebula Logger](https://github.com/jongpie/NebulaLogger).

### Prerequisites

- Nebula Logger must be installed in your org
- Your project must have an `ILogger` interface that Nebula Logger implements

### Usage

Set the logger in your coordinator or worker constructor:

```apex
public class MyCoordinator extends CursorBatchCoordinator {
    
    public MyCoordinator() {
        super('MyJob');
        setLogger(NebulaLoggerAdapterForCursorBatch.getInstance());
    }
}

public class MyWorker extends CursorBatchWorker {
    
    public MyWorker() {
        super();
        setLogger(NebulaLoggerAdapterForCursorBatch.getInstance());
    }
}
```

### Customization

The provided adapter assumes you have an `ILogger` interface resolved via `Application.Service`. Modify the adapter to match your project's dependency injection pattern:

```apex
// Current implementation
this.nebulaLogger = (ILogger) Application.Service.newInstance(ILogger.class);

// Direct Nebula Logger usage (alternative)
// Logger.info(message);
// Logger.saveLog();
```

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

# Nebula Logger adapter only (optional, requires Nebula Logger)
sf project deploy start --source-dir unpackaged/classes/NebulaLoggerAdapterForCursorBatch.cls
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
```
