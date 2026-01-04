# Unpackaged Metadata

This directory contains metadata that is **NOT included in the CursorBatchFramework unlocked package** but is useful for package subscribers. Deploy these components separately after installing the package.

## Contents

| Category | Files | Purpose |
|----------|-------|---------|
| **Platform Event Config** | `platformEventSubscriberConfigs/` | Required trigger configuration with org-specific running user |
| **Sample Implementations** | `classes/Sample*.cls` | Example coordinators and workers demonstrating usage patterns |
| **Nebula Logger Adapter** | `classes/NebulaLoggerAdapterForCursorBatch.cls` | Optional integration with Nebula Logger |

---

## 1. Platform Event Subscriber Config

The `PlatformEventSubscriberConfig` configures the trigger that processes worker Platform Events. This **cannot** be included in the package because it requires a running user that must be valid in your specific org.

### Post-Install Setup (Required)

After installing the CursorBatchFramework package, deploy the Platform Event Subscriber Config:

#### Option 1: Deploy as-is (uses default user)

```bash
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs/
```

#### Option 2: Customize the running user

1. Edit `platformEventSubscriberConfigs/CursorBatchWorkerTrigger.platformEventSubscriberConfig-meta.xml`
2. Update the `<user>` element with your desired running user:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PlatformEventSubscriberConfig xmlns="http://soap.sforce.com/2006/04/metadata">
    <batchSize>50</batchSize>
    <isProtected>false</isProtected>
    <masterLabel>CursorBatchWorkerTrigger</masterLabel>
    <platformEventConsumer>CursorBatchWorkerTrigger</platformEventConsumer>
    <user>your-integration-user@yourorg.com</user>
</PlatformEventSubscriberConfig>
```

3. Deploy:

```bash
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs/
```

#### Option 3: Configure via Setup UI

1. Go to **Setup → Platform Events → CursorBatch_Worker__e**
2. Click on **Subscriptions**
3. Configure the `CursorBatchWorkerTrigger` subscription with your desired running user

### Important Notes

- This configuration is **your responsibility** to maintain
- Package upgrades will **not** overwrite your configuration
- If you don't deploy this, the Platform Event trigger will use default settings

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
