# CursorBatch Framework

A high-performance parallel batch processing framework for Salesforce that leverages `Database.Cursor`, Platform Events and Queueables to overcome governor limits and achieve massive parallelization.

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
- 🔁 **Built-in Retry Support** — Automatic retry for both coordinator cursor queries AND worker page failures
- 🎛️ **Caller-Controlled Retry** — Throw `CursorBatchRetryException` to explicitly request page retry
- 🌐 **Callout Support** — Both coordinator and workers implement `Database.AllowsCallouts` for HTTP callouts

## Architecture

### Queueable Execution Model

Both the **Coordinator** and **Workers** are implemented as `Queueable` classes:

- **`CursorBatchCoordinator`** (Queueable): Executes the SOQL query, creates a `Database.Cursor`, extracts its queryId for cross-transaction access, and publishes Platform Events to fan out workers. Uses a Queueable Finalizer to handle cursor query timeouts with automatic retries.
- **`CursorBatchWorker`** (Queueable): Processes batches of records from assigned cursor positions. Workers can re-enqueue themselves to process subsequent pages within their assigned range.

### Retry Handling for Cursor Timeouts

The `Database.getCursor()` call can timeout on large datasets, throwing an uncatchable `System.QueryException`. The framework handles this automatically:

1. **Job record created first** — Before calling `Database.getCursor()`, the coordinator creates a job record with `Preparing` status
2. **Finalizer attached** — A `CursorBatchCoordinatorFinalizer` is attached to detect failures
3. **Automatic retry** — If the cursor query fails, the finalizer increments `Retry_Count__c` and re-enqueues the coordinator
4. **Max retries** — After `Max_Retries__c` attempts (default: 3), the job is marked `Failed` and the `finish()` callback is invoked

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Retry Flow                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │  Coordinator │────▶│   Create     │────▶│   Attach     │
  │   execute()  │     │   Job Rec    │     │  Finalizer   │
  └──────────────┘     │  (Preparing) │     └──────────────┘
                       └──────────────┘            │
                                                   ▼
                                         ┌──────────────────┐
                                         │ Database.        │
                                         │ getCursor()      │
                                         └──────────────────┘
                                                   │
                              ┌────────────────────┴────────────────────┐
                              ▼                                         ▼
                      ┌──────────────┐                         ┌──────────────┐
                      │   Success    │                         │   Timeout    │
                      │  Update to   │                         │  (Uncaught)  │
                      │  Processing  │                         └──────────────┘
                      └──────────────┘                                 │
                                                                       ▼
                                                           ┌──────────────────┐
                                                           │    Finalizer     │
                                                           │    Executes      │
                                                           └──────────────────┘
                                                                       │
                                              ┌────────────────────────┴────────┐
                                              ▼                                 ▼
                                    ┌──────────────────┐              ┌──────────────────┐
                                    │ Retries < Max?   │              │ Max Retries Hit  │
                                    │ Re-enqueue with  │              │ Mark as Failed   │
                                    │ same Job ID      │              │ Call finish()    │
                                    └──────────────────┘              └──────────────────┘
```

### Worker Page Retry

In addition to coordinator-level retry for cursor timeouts, the framework supports **worker-level retry** for failed page processing. This handles both unexpected failures (uncaught exceptions, CPU limits) and explicit retry requests from your code.

#### How It Works

Workers use a **sequential retry strategy**: when a page fails, the worker retries the same page before continuing to the next one. This ensures no records are skipped.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Worker Page Retry Flow                               │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐     ┌──────────────┐
  │   Worker     │────▶│   process()  │
  │   execute()  │     │   called     │
  └──────────────┘     └──────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
  │   Success    │   │ Retry        │   │ Other        │
  │   Continue   │   │ Exception    │   │ Exception    │
  │   to next    │   │ (Explicit)   │   │ (Uncaught)   │
  │   page       │   └──────────────┘   └──────────────┘
  └──────────────┘          │                  │
                            ▼                  ▼
                   ┌──────────────────────────────────┐
                   │      Retry Count < Max?          │
                   └──────────────────────────────────┘
                            │                  │
                      ┌─────┴─────┐      ┌─────┴─────┐
                      ▼           ▼      ▼           ▼
             ┌──────────────┐  ┌──────────────┐
             │ Re-enqueue   │  │ Publish      │
             │ with delay   │  │ Failure      │
             │ (exp backoff)│  │ Event        │
             └──────────────┘  └──────────────┘
```

#### Two Retry Mechanisms

| Type | Triggered By | Handler |
|------|--------------|---------|
| **Soft Retry** | `CursorBatchRetryException` thrown by caller | Worker catches, self-enqueues with delay |
| **Hard Retry** | Uncaught exceptions, CPU/heap limits | Finalizer catches, enqueues with delay |

#### Using CursorBatchRetryException

Throw `CursorBatchRetryException` from your `process()` method to explicitly request a retry:

```apex
public class MyWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        try {
            // Make external callout
            HttpResponse response = makeCallout(records);
            
            if (response.getStatusCode() == 429) {
                // Rate limited — request retry with 5 minute delay
                throw CursorBatchRetryException.create('Rate limited', 5);
            }
            
            if (response.getStatusCode() >= 500) {
                // Server error — request retry with default exponential backoff
                throw new CursorBatchRetryException('Server error: ' + response.getStatus());
            }
            
            // Process successful response...
            
        } catch (System.CalloutException e) {
            // Callout timeout — request retry
            throw new CursorBatchRetryException('Callout timeout: ' + e.getMessage());
        }
    }
}
```

#### Retry Configuration

Configure retry behavior per job in `CursorBatch_Config__mdt`:

| Field | Default | Description |
|-------|---------|-------------|
| `Worker_Max_Retries__c` | 3 | Maximum retry attempts per page |
| `Worker_Retry_Delay__c` | 1 | Base delay in minutes for exponential backoff |

The actual delay follows exponential backoff: `delay = min(base × 2^retryCount, 10)` minutes.

| Retry # | Delay (base=1) |
|---------|----------------|
| 1st | 1 min |
| 2nd | 2 min |
| 3rd | 4 min |
| 4th+ | 8-10 min (capped) |

### How Cursor Sharing Works

The `Database.Cursor` is serializable to JSON with a `queryId` property. The coordinator:
1. Creates the cursor via `Database.getCursor(query)`
2. Extracts the `queryId` using `JSON.serialize(cursor)`
3. Passes the `queryId` to workers via Platform Events

Workers reconstruct the cursor using:
```apex
Database.Cursor cursor = (Database.Cursor) JSON.deserialize(
    '{"queryId":"' + queryId + '"}', 
    Database.Cursor.class
);
```

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
│           Database.Cursor → Extract queryId → Store in Job Record           │
│                    (queryId passed to workers via Platform Events)           │
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

#### Platform Events

Platform Events must be enabled in your org (enabled by default in most orgs).

### Deploy the Package

#### Option 1: Install via URL (Recommended)

Click the appropriate link below:

| Environment | Install Link |
|-------------|--------------|
| **Production** | [Install in Production](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tg500000015dZAAQ) |
| **Sandbox** | [Install in Sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tg500000015dZAAQ) |

#### Option 2: Install via Salesforce CLI

```bash
sf package install --package 04tg500000015dZAAQ --target-org your-org --wait 10
```

#### Option 3: Deploy from Source

```bash
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
    
    // Optional: Called when coordinator completes worker fanout
    public override void onComplete() {
        super.onComplete();
        // Custom logic after workers are dispatched
    }
    
    // Optional: Called when ALL workers have completed (success or failure)
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

The worker processes batches of records. Both coordinator and worker implement `Database.AllowsCallouts`, so callouts are supported out of the box:

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
    
    // Optional: Called when this worker finishes ALL its assigned pages
    public override void onComplete() {
        super.onComplete();
        // Custom cleanup or logging for this worker
    }
}
```

**With retry handling for callouts:**

```apex
public class MyCalloutWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        HttpResponse response = makeExternalCallout(records);
        
        if (response.getStatusCode() == 429) {
            // Rate limited — retry after 5 minutes
            throw CursorBatchRetryException.create('Rate limited', 5);
        }
        
        if (response.getStatusCode() >= 500) {
            // Server error — retry with exponential backoff
            throw new CursorBatchRetryException('Server error');
        }
        
        // Process successful response...
    }
}
```

**With custom logger (e.g., Nebula Logger):**

```apex
public class MyLoggingWorker extends CursorBatchWorker {
    
    public MyLoggingWorker() {
        super();
        setLogger(new NebulaLoggerAdapter()); // See Pluggable Logging section
    }
    
    public override void process(List<SObject> records) {
        // Processing logic...
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
| **Coordinator_Max_Retries__c** | `3` | Max retries for cursor query timeouts |
| **Worker_Max_Retries__c** | `3` | Max retries for failed pages |
| **Worker_Retry_Delay__c** | `1` | Base delay (minutes) for retry backoff |

### 4. Execute

```apex
new MyDataProcessingCoordinator().submit();
```

## Components

### Apex Classes

| Class | Description |
|-------|-------------|
| `CursorBatchCoordinator` | Abstract base for coordinators (Queueable, AllowsCallouts). Runs query, creates cursor, publishes Platform Events to fan out workers |
| `CursorBatchCoordinatorFinalizer` | Queueable finalizer that handles cursor query timeouts with automatic retry logic |
| `CursorBatchWorker` | Abstract base for workers (Queueable, AllowsCallouts). Processes record batches from cursor positions, supports retry for failed pages |
| `CursorBatchWorkerFinalizer` | Queueable finalizer that handles worker retry and publishes completion events |
| `CursorBatchRetryException` | Custom exception to explicitly request page retry with optional delay |
| `CursorBatchContext` | Value object encapsulating worker execution parameters including retry state |
| `CursorBatchCompletionHandler` | Handles worker completion events and invokes callbacks |
| `CursorBatchWorkerTriggerHandler` | Platform Event trigger handler that enqueues Queueable workers from events |
| `CursorBatchSelector` | Centralized selector class for all SOQL queries in the framework |
| `CursorBatchLogger` | Default `System.debug` logger implementation |
| `ICursorBatchLogger` | Interface for custom logging integrations |

### Custom Objects

| Object | Type | Description |
|--------|------|-------------|
| `CursorBatch_Config__mdt` | Custom Metadata | Job configuration (parallelism, page size, retry settings) |
| `CursorBatch_Job__c` | Custom Object | Job tracking (status, worker counts, timing) |
| `CursorBatch_Worker__e` | Platform Event | Orchestration events from coordinator to trigger worker enqueueing (includes retry count) |
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
| `Coordinator_Max_Retries__c` | Number | 3 | Max retry attempts for coordinator cursor query timeouts |
| `Worker_Max_Retries__c` | Number | 3 | Max retry attempts for failed worker page processing |
| `Worker_Retry_Delay__c` | Number | 1 | Base delay in minutes for worker retry exponential backoff |

### CursorBatch_Job__c Fields

| Field | Type | Description |
|-------|------|-------------|
| `Job_Name__c` | Text | Job identifier matching config MasterLabel |
| `Status__c` | Picklist | `Preparing` → `Processing` → `Complete`/`Failed` |
| `Total_Workers__c` | Number | Number of parallel workers created |
| `Completed_Workers__c` | Number | Workers that completed successfully |
| `Failed_Workers__c` | Number | Workers that failed |
| `Total_Records__c` | Number | Total records in cursor result set |
| `Retry_Count__c` | Number | Number of retry attempts made (default: 0) |
| `Coordinator_Class__c` | Text | Fully qualified coordinator class name |
| `Cursor_Query_Id__c` | Text | Cursor queryId for cross-transaction access |
| `Query__c` | Long Text | SOQL query used |
| `Query_Duration_Ms__c` | Number | Time to execute cursor query (ms) |
| `Error_Message__c` | Long Text | Error details if failed |
| `Started_At__c` | DateTime | Job start time |
| `Completed_At__c` | DateTime | Job completion time |

### Job Statuses

| Status | Description |
|--------|-------------|
| `Preparing` | Job record created, cursor query pending or in progress |
| `Processing` | Cursor query succeeded, workers are processing records |
| `Complete` | All workers completed successfully |
| `Failed` | One or more workers failed, or max retries exhausted |

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

#### What Gets Logged

The framework logs key events at each stage:

| Event | Level | Example Message |
|-------|-------|-----------------|
| Query execution | INFO | `CursorBatchCoordinator query for MyJob: SELECT Id FROM Account...` |
| Query timing | INFO | `CursorBatchCoordinator cursor query took 150ms, totalRecords: 50000` |
| Worker distribution | INFO | `Distributing 50000 records across 50 workers via Platform Events` |
| Cursor queryId | INFO | `CursorBatchCoordinator extracted cursor queryId: 0r8xx50caotWO4i` |
| Job record creation | INFO | `CursorBatchCoordinator created job record with Preparing status: a0B...` |
| Event publishing | INFO | `CursorBatchCoordinator published 50 worker events for MyJob` |
| Worker processing | INFO | `CursorBatchWorker (MyJob #1) processing 100 records at position 0` |
| Worker retry | INFO | `CursorBatchWorker (MyJob #1) processing 100 records at position 0 (retry 1)` |
| Retry scheduling | INFO | `CursorBatchWorker (MyJob #1) scheduling retry 1 of 3 in 1 min at position 0` |
| Finalizer retry | INFO | `CursorBatchWorkerFinalizer: Scheduling retry 1 of 3 for worker #1 in 1 min` |
| Max retries exhausted | ERROR | `CursorBatchWorker (MyJob #1) max retries (3) exhausted at position 0` |
| Worker completion | INFO | `CursorBatchWorker (MyJob) worker #1 completed. Position: 0, EndPosition: 1000` |
| Errors | ERROR | `CursorBatchCoordinator error for MyJob: INVALID_QUERY...` |
| Exceptions | ERROR | Full stack trace included via `logException()` |

### Preventing Duplicate Jobs

The framework automatically prevents duplicate jobs by checking:

1. `CursorBatch_Job__c` records with `Status__c IN ('Preparing', 'Processing')`
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

### Error Handling

- **Coordinator retry**: Cursor query timeouts are automatically retried up to `Coordinator_Max_Retries__c` times
- **Worker retry**: Failed pages are automatically retried up to `Worker_Max_Retries__c` times with exponential backoff
- **Explicit retry**: Throw `CursorBatchRetryException` from `process()` to request retry with optional delay
- Workers automatically track failures via finalizers
- First error is captured in `CursorBatch_Job__c.Error_Message__c`
- Failed worker count available in `Failed_Workers__c`
- Job status set to `'Failed'` if any worker exhausts retries
- `finish()` callback is always invoked, even on failure, allowing cleanup/notifications

### Cursor Snapshot Behavior & Entry Condition Revalidation

**Important:** The `Database.Cursor` captures a **snapshot of record IDs** at query time, not a live view. This has significant implications:

| Behavior | Description |
|----------|-------------|
| **Record IDs are cached** | Once the cursor is created, the set of record IDs is fixed |
| **Field values are current** | When `fetch()` is called, field values reflect the current database state |
| **Modified records still returned** | Records that no longer match the original WHERE clause are still returned |
| **Deleted records silently excluded** | Deleted record IDs are filtered out — `fetch()` returns fewer records, no exception thrown |
| **`getNumRecords()` becomes stale** | The count doesn't update after deletions — may report more records than actually exist |

**Example Scenario:**

1. Coordinator runs: `SELECT Id FROM Lead WHERE Status = 'Open'` → Returns 1000 leads
2. Another process updates 500 of those leads to `Status = 'Closed'`
3. Workers fetch from the cursor → **All 1000 leads are still returned**, even though 500 no longer have `Status = 'Open'`

**When to Revalidate Entry Conditions:**

Depending on your use case, you may need to revalidate that records still meet the original query criteria before processing:

```apex
public class MyWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        List<Lead> leads = (List<Lead>) records;
        
        // Option 1: Filter in memory (if you have the field values)
        List<Lead> stillQualifying = new List<Lead>();
        for (Lead l : leads) {
            if (l.Status == 'Open') {
                stillQualifying.add(l);
            }
        }
        
        // Option 2: Re-query to get fresh data with entry conditions
        Set<Id> recordIds = new Map<Id, Lead>(leads).keySet();
        List<Lead> freshLeads = [
            SELECT Id, Name, Status 
            FROM Lead 
            WHERE Id IN :recordIds 
            AND Status = 'Open'  // Re-apply entry conditions
        ];
        
        // Process only the records that still qualify
        processQualifyingRecords(freshLeads);
    }
}
```

**When Revalidation is NOT Needed:**

- The processing logic is idempotent and safe to run regardless of current state
- You're performing read-only operations (reporting, analysis)
- The query criteria are immutable (e.g., `CreatedDate`, `Id`, `RecordType`)
- You have exclusive ownership of the records during processing

**When Revalidation IS Recommended:**

- Records may be modified by users, triggers, or other processes during job execution
- Processing has side effects that should only apply to records meeting specific criteria
- Long-running jobs where data staleness is a concern
- Financial or compliance-sensitive operations requiring current state validation

**Handling Deleted Records:**

Since deleted records are silently excluded from `fetch()` results, your worker may receive fewer records than expected. This is generally safe — just process what you receive. However, be aware that:

- `getNumRecords()` may overstate the actual record count
- Page sizes may be smaller than configured if records were deleted
- Progress calculations based on record counts may be inaccurate

## Troubleshooting

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

### v0.4.0

- **New Feature**: Worker page retry with exponential backoff
  - Failed pages are automatically retried up to `Worker_Max_Retries__c` times
  - Uses delayed queueable enqueue: `System.enqueueJob(worker, delayMinutes)`
  - Exponential backoff: `delay = min(baseDelay × 2^retryCount, 10)` minutes
- **New Feature**: Caller-controlled retry via `CursorBatchRetryException`
  - Throw from `process()` to explicitly request page retry
  - Optional `suggestedDelayMinutes` parameter for custom delay
- **New Configuration Fields**:
  - `Worker_Max_Retries__c` — Max retry attempts for worker pages (default: 3)
  - `Worker_Retry_Delay__c` — Base delay in minutes for exponential backoff (default: 1)
- **Renamed Field**: `Max_Retries__c` → `Coordinator_Max_Retries__c` for clarity
- `CursorBatchContext` now includes `retryCount` and `cursorQueryId` for retry state tracking
- `CursorBatchWorkerFinalizer` now handles retry logic in addition to completion tracking
- Added `Retry_Count__c` field to `CursorBatch_Worker__e` Platform Event

### v0.3.0

- **New Feature**: Built-in retry support for cursor query timeouts
- Added `CursorBatchCoordinatorFinalizer` to handle uncatchable `System.QueryException`
- Added `Coordinator_Max_Retries__c` field to `CursorBatch_Config__mdt` (default: 3)
- Added `Retry_Count__c` field to `CursorBatch_Job__c`
- **Breaking Change**: Job status values changed to mirror Batch Apex conventions:
  - `Running` replaced with `Preparing` (before cursor query) and `Processing` (after workers fanned out)
  - `finish()` callback now invoked even when job fails due to exhausted retries
- Coordinator now creates job record before cursor query to enable retry tracking

### v0.2.0

- **Breaking Change**: Removed Platform Cache dependency
- Cursor queryId is now stored in `Cursor_Query_Id__c` field (renamed from `Cache_Key__c`)
- Removed `ICursorBatchCacheService` interface and `CursorBatchCacheServiceImpl`
- Removed `Cache_TTL_Hours__c` configuration field (no longer needed)
- Simplified installation — no Platform Cache capacity required
- Works on all Salesforce editions that support Platform Events

### v0.1.0

- Initial beta release
- Coordinator/Worker pattern with Platform Event fanout
- Platform Cache cursor storage
- Automatic completion tracking with Queueable Finalizers
- Configurable parallelism, page size, and cache TTL
- Pluggable logging interface
