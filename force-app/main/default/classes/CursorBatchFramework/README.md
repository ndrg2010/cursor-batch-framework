# CursorBatch Framework

A high-performance parallel batch processing framework for Salesforce that leverages `Database.Cursor`, Platform Cache, Platform Events and Queueables to overcome governor limits and achieve massive parallelization.

## Why CursorBatch?

Traditional Salesforce batch processing has limitations:

| Approach | Limitation |
|----------|-----------|
| `Database.Batchable` | Sequential execution, one batch at a time |
| Queueable chaining | Limited to 1 child job per execution |
| `@future` methods | No chaining, limited control |

**CursorBatch solves these by:**

- ⚡ **Parallel Execution** — Fan out up to 50+ workers simultaneously using Queueable + Platform Events
- 🎯 **Cursor-Based Pagination** — Efficient, server-side position tracking
- 📡 **Platform Event Orchestration** — Bypass Queueable chaining limits (1 child job) to enable parallel fanout
- 🔄 **Automatic Completion Callbacks** — Chain jobs or send notifications when done
- 📊 **Built-in Job Tracking** — Monitor progress with custom object records
- 🧩 **Pluggable Logging** — Integrate with Nebula Logger, Pharos, or custom solutions

## Architecture

### Queueable Execution Model

Both the **Coordinator** and **Workers** are implemented as `Queueable` classes:

- **`CursorBatchCoordinator`** (Queueable): Executes the SOQL query, creates a `Database.Cursor`, caches it in Platform Cache, and publishes Platform Events to fan out workers.
- **`CursorBatchWorker`** (Queueable): Processes batches of records from assigned cursor positions. Workers can re-enqueue themselves to process subsequent pages within their assigned range.

### Platform Events: Enabling Parallel Fanout

**Why Platform Events?** Salesforce Queueable chaining is limited to **1 child job per execution**. This means a Queueable can only directly enqueue one other Queueable job. To achieve parallel execution of 50+ workers, the framework uses Platform Events as an orchestration mechanism:

1. **Coordinator** (Queueable) publishes `CursorBatch_Worker__e` Platform Events (one per worker)
2. **Platform Event Trigger** (`CursorBatchWorkerTrigger`) receives these events
3. **Trigger Handler** (`CursorBatchWorkerTriggerHandler`) enqueues the actual Queueable workers
4. This bypasses the Queueable chaining limitation, allowing 50+ parallel workers to be spawned simultaneously

Platform Events are **not** used for the actual work execution—they're purely an orchestration mechanism to overcome the Queueable chaining constraint.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CursorBatchCoordinator                             │
│                     (Queueable - executes query, fans out)                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                Database.Cursor → Platform Cache (CursorBatch partition)      │
│                        (Cached for cross-transaction access)                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                   ┌──────────────────┼──────────────────┐
                   ▼                  ▼                  ▼
          ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
          │ CursorBatch_  │  │ CursorBatch_  │  │ CursorBatch_  │
          │ Worker__e #1  │  │ Worker__e #2  │  │ Worker__e #N  │
          │ (Platform     │  │ (Platform     │  │ (Platform     │
          │  Event)       │  │  Event)       │  │  Event)       │
          └───────────────┘  └───────────────┘  └───────────────┘
                   │                  │                  │
                   │  (Orchestration) │                  │
                   ▼                  ▼                  ▼
          ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
          │ CursorBatch   │  │ CursorBatch   │  │ CursorBatch   │
          │ Worker #1     │  │ Worker #2     │  │ Worker #N     │
          │ (Queueable)   │  │ (Queueable)   │  │ (Queueable)   │
          └───────────────┘  └───────────────┘  └───────────────┘
                   │                  │                  │
                   └──────────────────┼──────────────────┘
                                      ▼
                          ┌───────────────────────┐
                          │ CursorBatch_Worker    │
                          │ Complete__e           │
                          │ (via Finalizers)      │
                          └───────────────────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │ CursorBatchCompletion │
                          │ Handler → finish()    │
                          └───────────────────────┘
```

## Installation

### Prerequisites

#### Salesforce Edition (Required)

This framework requires **Enterprise Edition or higher**:

| Edition | Supported | Default Cache Capacity |
|---------|-----------|------------------------|
| **Performance** | ✅ Yes | 30 MB |
| **Unlimited** | ✅ Yes | 30 MB |
| **Enterprise** | ✅ Yes | 10 MB |
| **Professional** | ❌ No | N/A (Platform Cache unavailable) |
| **Developer** | ⚠️ Limited | 0 MB (trial capacity may be available) |

#### Platform Cache (Required)

This framework **requires** Platform Cache because `Database.Cursor` can **only** be stored in Platform Cache — this is a Salesforce platform limitation, not a design choice.

**The package includes a dedicated `CursorBatch` cache partition** (1 MB default allocation). After installation, you can adjust the capacity:

1. Go to **Setup → Platform Cache**
2. Click on the **CursorBatch** partition
3. Increase **Org Cache** allocation as needed for your workload


> **Note:** If your org has zero available Platform Cache capacity, the package installation will fail. Verify capacity in **Setup → Platform Cache** before installing.

#### Platform Events

Platform Events must be enabled in your org (enabled by default in most orgs).

### Deploy the Package

```bash
sf package install --package YOUR_PACKAGE_VERSION_ID --target-org your-org
```

Or deploy from source:

```bash
# Deploy cache partition first
sf project deploy start --source-dir force-app/main/default/cachePartitions/CursorBatch.cachePartition-meta.xml

# Deploy framework classes
sf project deploy start --source-dir force-app/main/default/classes/CursorBatchFramework

# Deploy custom objects and metadata
sf project deploy start --source-dir force-app/main/default/objects/CursorBatch_Config__mdt
sf project deploy start --source-dir force-app/main/default/objects/CursorBatch_Job__c
sf project deploy start --source-dir force-app/main/default/objects/CursorBatch_Worker__e
sf project deploy start --source-dir force-app/main/default/objects/CursorBatch_WorkerComplete__e

# Deploy triggers
sf project deploy start --source-dir force-app/main/default/triggers
```

## Quick Start

### 1. Create a Coordinator

The coordinator defines your query and specifies the worker class:

```apex
public class MyDataProcessingCoordinator extends CursorBatchCoordinator {
    
    public MyDataProcessingCoordinator() {
        super('MyDataProcessingJob'); // Must match CursorBatch_Config__mdt.MasterLabel
    }
    
    public override String buildQuery() {
        // IMPORTANT: Use inline values, not bind variables (required by Database.Cursor)
        return 'SELECT Id, Name, Status__c FROM Account WHERE Status__c = \'Pending\'';
    }
    
    public override String getWorkerClassName() {
        return 'MyDataProcessingWorker';
    }
    
    public override void finish(CursorBatch_Job__c jobRecord) {
        super.finish(jobRecord);
        
        // Chain to another job, send notifications, etc.
        if (jobRecord.Status__c == 'Complete') {
            // All workers succeeded
        } else {
            // Some workers failed — check jobRecord.Failed_Workers__c
        }
    }
}
```

### 2. Create a Worker

The worker processes batches of records:

```apex
public class MyDataProcessingWorker extends CursorBatchWorker {
    
    public MyDataProcessingWorker() {
        super();
    }
    
    public override void process(List<SObject> records) {
        List<Account> accounts = (List<Account>) records;
        
        for (Account acc : accounts) {
            acc.Status__c = 'Processed';
        }
        
        update accounts;
    }
}
```

### 3. Configure the Job

Create a `CursorBatch_Config__mdt` record:

| Field | Value | Description |
|-------|-------|-------------|
| **MasterLabel** | `MyDataProcessingJob` | Must match coordinator constructor |
| **Active__c** | `true` | Enable/disable the job |
| **Parallel_Count__c** | `10` | Number of parallel workers (default: 50) |
| **Page_Size__c** | `100` | Records per fetch (default: 20) |
| **Cache_TTL_Hours__c** | `4` | Cache expiration (default: 8 hours) |

### 4. Execute

```apex
new MyDataProcessingCoordinator().submit();
```

## Components

### Apex Classes

| Class | Description |
|-------|-------------|
| `CursorBatchCoordinator` | Abstract base for coordinators (Queueable). Runs query, creates cursor, publishes Platform Events to fan out workers |
| `CursorBatchWorker` | Abstract base for workers (Queueable). Processes record batches from cursor positions, can re-enqueue for pagination |
| `CursorBatchContext` | Value object encapsulating worker execution parameters |
| `ICursorBatchCacheService` | Interface for cursor caching operations (dependency injection pattern) |
| `CursorBatchCacheServiceImpl` | Default implementation for caching cursors in Platform Cache (`CursorBatch` partition) |
| `CursorBatchCompletionHandler` | Handles worker completion events and invokes callbacks |
| `CursorBatchWorkerFinalizer` | Queueable finalizer that publishes completion events |
| `CursorBatchWorkerTriggerHandler` | Platform Event trigger handler that enqueues Queueable workers from events |
| `CursorBatchLogger` | Default `System.debug` logger implementation |
| `ICursorBatchLogger` | Interface for custom logging integrations |

### Custom Objects

| Object | Type | Description |
|--------|------|-------------|
| `CursorBatch_Config__mdt` | Custom Metadata | Job configuration (parallelism, page size, TTL) |
| `CursorBatch_Job__c` | Custom Object | Job tracking (status, worker counts, timing) |
| `CursorBatch_Worker__e` | Platform Event | Orchestration events from coordinator to trigger worker enqueueing (bypasses Queueable chaining limit) |
| `CursorBatch_WorkerComplete__e` | Platform Event | Worker completion signals for callbacks |

### Triggers

| Trigger | Event | Description |
|---------|-------|-------------|
| `CursorBatchWorkerTrigger` | `CursorBatch_Worker__e` | Spawns workers from coordinator events |
| `CursorBatchWorkerCompleteTrigger` | `CursorBatch_WorkerComplete__e` | Handles completion and callbacks |

## Configuration Reference

### CursorBatch_Config__mdt Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Active__c` | Checkbox | — | Must be `true` to run |
| `Parallel_Count__c` | Number | 50 | Max concurrent workers |
| `Page_Size__c` | Number | 20 | Records per cursor fetch |
| `Cache_TTL_Hours__c` | Number | 8 | Cursor cache expiration |

## Advanced Usage

### Pluggable Logging

The framework uses an `ICursorBatchLogger` interface to decouple logging from implementation. By default, it uses `System.debug`, but you can plug in Nebula Logger, Pharos, custom object logging, or any other framework.

#### The ICursorBatchLogger Interface

```apex
public interface ICursorBatchLogger {
    void logInfo(String message);      // Informational messages
    void logError(String message);     // Error messages without exception
    void logException(String message, Exception e);  // Errors with exception context
}
```

#### Default Logger

The framework ships with `CursorBatchLogger`, which writes to `System.debug` with a `[CursorBatch]` prefix:

```apex
// Default behavior — no configuration needed
public class MyCoordinator extends CursorBatchCoordinator {
    public MyCoordinator() {
        super('MyJob');
        // Uses CursorBatchLogger.getDefault() automatically
    }
}
```

#### Setting a Custom Logger

Call `setLogger()` in your coordinator or worker constructor:

```apex
public class MyCoordinator extends CursorBatchCoordinator {
    
    public MyCoordinator() {
        super('MyJob');
        setLogger(new NebulaLoggerAdapter());
    }
}

public class MyWorker extends CursorBatchWorker {
    
    public MyWorker() {
        super();
        setLogger(new NebulaLoggerAdapter());
    }
}
```

#### Nebula Logger Integration

```apex
public class NebulaLoggerAdapter implements ICursorBatchLogger {
    
    public void logInfo(String message) {
        Logger.info(message);
        Logger.saveLog();
    }
    
    public void logError(String message) {
        Logger.error(message);
        Logger.saveLog();
    }
    
    public void logException(String message, Exception e) {
        Logger.error(message, e);
        Logger.saveLog();
    }
}
```

#### Pharos Integration

```apex
public class PharosLoggerAdapter implements ICursorBatchLogger {
    
    public void logInfo(String message) {
        pharos.Logger.log('INFO', message);
    }
    
    public void logError(String message) {
        pharos.Logger.log('ERROR', message);
    }
    
    public void logException(String message, Exception e) {
        pharos.Logger.log(e).setMessage(message);
    }
}
```

#### Custom Object Logger

Log to a custom `Log__c` object for dashboards and reporting:

```apex
public class CustomObjectLogger implements ICursorBatchLogger {
    
    private List<Log__c> pendingLogs = new List<Log__c>();
    private static final Integer FLUSH_THRESHOLD = 100;
    
    public void logInfo(String message) {
        addLog('INFO', message, null);
    }
    
    public void logError(String message) {
        addLog('ERROR', message, null);
    }
    
    public void logException(String message, Exception e) {
        addLog('ERROR', message + ': ' + e.getMessage(), e.getStackTraceString());
    }
    
    private void addLog(String level, String message, String stackTrace) {
        pendingLogs.add(new Log__c(
            Level__c = level,
            Message__c = message.left(131072),
            Stack_Trace__c = stackTrace?.left(131072),
            Source__c = 'CursorBatch',
            Timestamp__c = System.now()
        ));
        
        if (pendingLogs.size() >= FLUSH_THRESHOLD) {
            flush();
        }
    }
    
    public void flush() {
        if (!pendingLogs.isEmpty()) {
            insert pendingLogs;
            pendingLogs.clear();
        }
    }
}
```

#### Composite Logger

Log to multiple destinations simultaneously:

```apex
public class CompositeLogger implements ICursorBatchLogger {
    
    private List<ICursorBatchLogger> loggers;
    
    public CompositeLogger(List<ICursorBatchLogger> loggers) {
        this.loggers = loggers;
    }
    
    public void logInfo(String message) {
        for (ICursorBatchLogger logger : loggers) {
            logger.logInfo(message);
        }
    }
    
    public void logError(String message) {
        for (ICursorBatchLogger logger : loggers) {
            logger.logError(message);
        }
    }
    
    public void logException(String message, Exception e) {
        for (ICursorBatchLogger logger : loggers) {
            logger.logException(message, e);
        }
    }
}

// Usage: log to both Nebula and a custom object
public class MyCoordinator extends CursorBatchCoordinator {
    public MyCoordinator() {
        super('MyJob');
        setLogger(new CompositeLogger(new List<ICursorBatchLogger>{
            new NebulaLoggerAdapter(),
            new CustomObjectLogger()
        }));
    }
}
```

#### What Gets Logged

The framework logs key events at each stage:

| Event | Level | Example Message |
|-------|-------|-----------------|
| Query execution | INFO | `CursorBatchCoordinator query for MyJob: SELECT Id FROM Account...` |
| Record count | INFO | `CursorBatchCoordinator totalRecords: 50000` |
| Worker distribution | INFO | `Distributing 50000 records across 50 workers via Platform Events` |
| Cursor caching | INFO | `CursorBatchCoordinator cached cursor with key: MyJob_abc123` |
| Job record creation | INFO | `CursorBatchCoordinator created job tracking record: a0B...` |
| Event publishing | INFO | `CursorBatchCoordinator published 50 worker events for MyJob` |
| Worker processing | INFO | `CursorBatchWorker (MyJob #1) processing 100 records at position 0` |
| Worker completion | INFO | `CursorBatchWorker (MyJob) worker #1 completed` |
| Errors | ERROR | `CursorBatchCoordinator error for MyJob: INVALID_QUERY...` |
| Exceptions | ERROR | Full stack trace included via `logException()` |

#### Testing with Mock Loggers

Create a mock logger to capture and assert log messages in tests:

```apex
@IsTest
public class MockCursorBatchLogger implements ICursorBatchLogger {
    
    public List<String> infoMessages = new List<String>();
    public List<String> errorMessages = new List<String>();
    public List<String> exceptionMessages = new List<String>();
    
    public void logInfo(String message) {
        infoMessages.add(message);
    }
    
    public void logError(String message) {
        errorMessages.add(message);
    }
    
    public void logException(String message, Exception e) {
        exceptionMessages.add(message + ': ' + e.getMessage());
    }
}

// In your test
@IsTest
static void testLogging() {
    MockCursorBatchLogger mockLogger = new MockCursorBatchLogger();
    MyCoordinator coordinator = new MyCoordinator();
    coordinator.setLogger(mockLogger);
    
    // ... execute coordinator ...
    
    System.assert(mockLogger.infoMessages.size() > 0, 'Expected info logs');
    System.assert(mockLogger.infoMessages[0].contains('query'), 'Expected query log');
}
```

### Preventing Duplicate Jobs

The framework automatically prevents duplicate jobs by checking:

1. `CursorBatch_Job__c` records with `Status__c = 'Running'`
2. `AsyncApexJob` for running queueables of the same coordinator class

Override `isJobAlreadyRunning()` for custom logic:

```apex
protected override Boolean isJobAlreadyRunning(String jobName) {
    // Custom duplicate detection
    return false;
}
```

### Job Chaining

Chain jobs in the `finish()` callback:

```apex
public override void finish(CursorBatch_Job__c jobRecord) {
    if (jobRecord.Status__c == 'Complete') {
        new NextStepCoordinator().submit();
    }
}
```

### Monitoring Jobs

Query `CursorBatch_Job__c` for job status:

```apex
List<CursorBatch_Job__c> jobs = [
    SELECT Job_Name__c, Status__c, Total_Workers__c, 
           Completed_Workers__c, Failed_Workers__c,
           Started_At__c, Completed_At__c, Error_Message__c
    FROM CursorBatch_Job__c
    WHERE Job_Name__c = 'MyDataProcessingJob'
    ORDER BY CreatedDate DESC
    LIMIT 10
];
```

## Governor Limits & Best Practices

### Recommended Settings

| Use Case | Parallel Count | Page Size |
|----------|---------------|-----------|
| Light processing | 50 | 200 |
| DML-heavy | 20 | 50 |
| Callouts | 10 | 20 |
| Complex calculations | 30 | 100 |

### Platform Cache Considerations

- The framework uses a dedicated `CursorBatch` partition (included with the package)
- Default allocation is 1 MB — increase via **Setup → Platform Cache** for larger jobs
- Cursors consume cache space proportional to query complexity and result set size
- Use appropriate `Cache_TTL_Hours__c` to balance availability vs. capacity
- Multiple concurrent jobs share the same partition — scale capacity accordingly

### Error Handling

- Workers automatically track failures via finalizers
- First error is captured in `CursorBatch_Job__c.Error_Message__c`
- Failed worker count available in `Failed_Workers__c`
- Job status set to `'Failed'` if any worker fails

## Troubleshooting

### "Platform Cache is required but not available"

This error indicates Platform Cache is not properly configured:

1. **Check Salesforce Edition** — Must be Enterprise, Unlimited, or Performance Edition
2. **Verify cache capacity** — Go to **Setup → Platform Cache** and confirm available capacity
3. **Confirm partition exists** — The `CursorBatch` partition should be visible after package installation
4. **Allocate capacity** — If the partition shows 0 MB, increase the Org Cache allocation

### "Cursor not found in cache"

- Check `Cache_TTL_Hours__c` — cursor may have expired before workers completed
- Verify the `CursorBatch` partition has adequate capacity allocated
- For large jobs, increase cache allocation in **Setup → Platform Cache**

### "No active config found for job"

- Create a `CursorBatch_Config__mdt` record with matching `MasterLabel`
- Set `Active__c = true`

### Workers not processing

- Check Platform Event trigger is deployed
- Verify `CursorBatchWorkerTrigger` is active
- Review debug logs for errors

### Duplicate job prevention not working

- Ensure `CursorBatch_Job__c` records are being created
- Check that previous job's `Status__c` is properly set

## License

MIT License — see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Submit a pull request

## Changelog

### v0.1.0

- Initial bet release
- Coordinator/Worker pattern with Platform Event fanout
- Platform Cache cursor storage
- Automatic completion tracking with Queueable Finalizers
- Configurable parallelism, page size, and cache TTL
- Pluggable logging interface

