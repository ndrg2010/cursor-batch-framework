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
- 📊 **Built-in Job Tracking** — Monitor progress with custom object records and real-time percent complete
- 🧩 **Pluggable Logging** — Integrate with Nebula Logger, Pharos, or custom solutions
- 🔁 **Built-in Retry Support** — Automatic retry for both coordinator cursor queries AND worker page failures
- 🎛️ **Caller-Controlled Retry** — Throw `CursorBatchRetryException` to explicitly request page retry
- 🌐 **Callout Support** — Both coordinator and workers implement `Database.AllowsCallouts` for HTTP callouts

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Configuration Reference](#configuration-reference)
- [Important: Cursor Snapshot Behavior](#important-cursor-snapshot-behavior)
- [Advanced Usage](#advanced-usage)
  - [Monitoring Jobs](#monitoring-jobs)
  - [Job Chaining](#job-chaining)
  - [Preventing Duplicate Jobs](#preventing-duplicate-jobs)
  - [Parent/Child Pattern for Avoiding Record Locks](#parentchild-pattern-for-avoiding-record-locks)
  - [Pluggable Logging](#pluggable-logging)
- [Governor Limits & Best Practices](#governor-limits--best-practices)
- [Troubleshooting](#troubleshooting)
- [Components](#components)

## Installation

### Prerequisites

#### Platform Events

Platform Events must be enabled in your org (enabled by default in most orgs).

### Deploy the Package

#### Option 1: Install via URL (Recommended)

Click the appropriate link below:

| Environment | Install Link |
|-------------|--------------|
| **Production** | [Install in Production](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000CzvlAAC) |
| **Sandbox** | [Install in Sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000CzvlAAC) |

#### Option 2: Install via Salesforce CLI

```bash
sf package install --package 04tfj000000CzvlAAC --target-org your-org --wait 10
```

### Post-Install Setup

After installing the package, you must deploy the **Platform Event Subscriber Configurations** to specify which user runs the Platform Event triggers.

> **Note:** These configs are intentionally **NOT included in the package** so that your customizations (especially the run-as user) are preserved during package upgrades.

#### Why This Is Required

Platform Event triggers run as the **Automated Process** user by default. This system user lacks permissions to:
- Query `CursorBatch_Config__mdt` custom metadata
- Create/update `CursorBatch_Job__c` records
- Instantiate coordinator/worker classes dynamically via `Type.forName()`

Additionally, **all three triggers must run as the same user** because `Database.Cursor` is only accessible to the user who created it. The coordinator creates the cursor, and workers need to access it.

The Platform Event Subscriber Config overrides this default, allowing triggers to run as a **permissioned user** with the necessary access.

#### Deploy the Subscriber Configs

The framework uses **three** Platform Event triggers that require subscriber configurations:

| Trigger | Platform Event | Purpose |
|---------|----------------|---------|
| `CursorBatchCoordinatorTrigger` | `CursorBatch_Coordinator__e` | Enqueues the coordinator queueable |
| `CursorBatchWorkerTrigger` | `CursorBatch_Worker__e` | Spawns workers from coordinator events |
| `CursorBatchWorkerCompleteTrigger` | `CursorBatch_WorkerComplete__e` | Handles worker completion and invokes `finish()` callback |

1. Clone or download the repository to access the `unpackaged/` directory
2. Deploy all three subscriber configurations:

```bash
sf project deploy start --source-dir unpackaged/platformEventSubscriberConfigs --target-org your-org
```

3. Verify deployment in Setup → Platform Events:
   - `CursorBatch_Coordinator__e` → Subscriptions
   - `CursorBatch_Worker__e` → Subscriptions
   - `CursorBatch_WorkerComplete__e` → Subscriptions

#### Choosing the Run-As User

The included configs use a placeholder user. Update all three files in `unpackaged/platformEventSubscriberConfigs/` before deploying:

- `CursorBatchCoordinatorTriggerConfig.platformEventSubscriberConfig-meta.xml`
- `CursorBatchWorkerTriggerConfig.platformEventSubscriberConfig-meta.xml`
- `CursorBatchWorkerCompleteTriggerConfig.platformEventSubscriberConfig-meta.xml`

```xml
<user>your-integration-user@example.com</user>
```

**Requirements for the run-as user:**
- Must have **Read** access to `CursorBatch_Config__mdt`
- Must have **Create/Edit** access to `CursorBatch_Job__c`
- Must have **Apex Class** access to coordinator, worker, and any dependent classes and objects.
- Recommended: Use a dedicated integration user or system administrator
- All three triggers **must use the same user** for cursor access to work

> **Note:** See [unpackaged/README.md](unpackaged/README.md) for complete details and troubleshooting.
> **Note:** Since these configs are not in the package, your customizations are always preserved during upgrades.

### Permission Sets

| Permission Set | Description |
|----------------|-------------|
| **Cursor Batch Job Viewer** | Grants read access and View All Records on `CursorBatch_Job__c` object with tab visibility. Assign to users who need to monitor batch job progress. |

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
    // IMPORTANT: This runs in a SEPARATE TRANSACTION via Platform Event, not in the worker's transaction
    public override void finish(CursorBatch_Job__c jobRecord) {
        super.finish(jobRecord);
        
        // Chain to another job, send notifications, etc.
        if (jobRecord.Status__c == 'Completed') {
            // All workers succeeded
        } else if (jobRecord.Status__c == 'Completed with Errors') {
            // Partial success — some workers failed
            // Check jobRecord.Failed_Workers__c, jobRecord.Total_Worker_Retries__c
        } else {
            // All workers failed
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

## Architecture

### Queueable Execution Model

Both the **Coordinator** and **Workers** are implemented as `Queueable` classes:

- **`CursorBatchCoordinator`** (Queueable): Executes the SOQL query, creates a `Database.Cursor`, extracts its queryId for cross-transaction access, and publishes Platform Events to fan out workers. Uses a Queueable Finalizer to handle cursor query timeouts with automatic retries. **Routed through a Platform Event** to ensure it runs as the dedicated trigger user.
- **`CursorBatchWorker`** (Queueable): Processes batches of records from assigned cursor positions. Workers can re-enqueue themselves to process subsequent pages within their assigned range.

### Cursor User Affinity

`Database.Cursor` is only accessible to the user who created it. To ensure workers can access the cursor:

1. **`submit()` publishes a Platform Event** (`CursorBatch_Coordinator__e`) instead of directly enqueueing the coordinator
2. **Platform Event trigger** runs as the dedicated trigger user (configured in PlatformEventSubscriberConfig)
3. **Coordinator queueable** runs as the trigger user and creates the cursor
4. **Workers** also run as the trigger user (via `CursorBatch_Worker__e` trigger) and can access the cursor

This is why all three Platform Event Subscriber Configs must specify the **same user**.

### Retry Handling for Cursor Timeouts

The `Database.getCursor()` call can timeout on large datasets, throwing an uncatchable `System.QueryException`. The framework handles this automatically:

1. **Job record created first** — Before calling `Database.getCursor()`, the coordinator creates a job record with `Preparing` status and stores the query in `Query__c`
2. **Finalizer attached** — A `CursorBatchCoordinatorFinalizer` is attached to detect failures
3. **Automatic retry** — If the cursor query fails, the finalizer increments `Total_Cursor_Retries__c` and re-enqueues the coordinator using `Type.newInstance()` (requires no-arg constructor)
4. **Stored query reused** — On retry, the coordinator uses the query stored in `Query__c` rather than calling `buildQuery()` again, ensuring retries work even for coordinators with multiple query modes
5. **Max retries** — After `Coordinator_Max_Retries__c` attempts (default: 3), the job is marked `Failed` and the `finish()` callback is invoked

> **Important:** Both coordinator retries and `finish()` callbacks use reflection (`Type.newInstance()`) to instantiate the coordinator. Your coordinator class **must have a no-arg constructor** for these features to work.

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

The framework supports **worker-level retry** for failed page processing. This handles both unexpected failures (uncaught exceptions, CPU limits) and explicit retry requests from your code.

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

### Completion Callback via Platform Event

When all workers complete, the coordinator's `finish()` method is invoked **via Platform Event in a separate transaction**, not in the same transaction as the final worker. This provides important benefits:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       finish() Callback Flow                                │
└─────────────────────────────────────────────────────────────────────────────┘

  Worker Transaction                    Platform Event Transaction
  ───────────────────                   ───────────────────────────

  ┌──────────────┐
  │   Worker     │
  │   process()  │
  └──────────────┘
         │
         ▼
  ┌──────────────┐
  │   Finalizer  │
  │   publishes  │──────────┐
  │   PE event   │          │
  └──────────────┘          │
         │                  │   CursorBatch_WorkerComplete__e
  ┌──────────────┐          │
  │  Transaction │          │
  │   COMMITS    │          │
  └──────────────┘          │
                            ▼
                   ┌──────────────────────┐
                   │ NEW TRANSACTION      │
                   │ ──────────────────── │
                   │ CursorBatchCompletion│
                   │ Handler.handle()     │
                   └──────────────────────┘
                            │
                            ▼
                   ┌──────────────────────┐
                   │ All workers done?    │
                   │ ──────────────────── │
                   │ Yes → invokeFinish() │
                   │ No  → update counts  │
                   └──────────────────────┘
                            │
                            ▼
                   ┌──────────────────────┐
                   │ Coordinator.finish() │
                   │ called via reflection│
                   └──────────────────────┘
```

**Why this matters:**

| Benefit | Description |
|---------|-------------|
| **Transaction isolation** | Worker failures don't roll back completion tracking |
| **Reliable completion** | Even CPU limit or uncaught exceptions trigger the finalizer, which publishes the event |
| **Fresh governor limits** | `finish()` runs with its own limits, enabling DML, callouts, or chaining to another job |
| **Batched completion** | Multiple worker completions can be aggregated in a single trigger execution |

**Implications for your code:**

- `finish()` cannot access in-memory state from workers (they ran in different transactions)
- Use `CursorBatch_Job__c` fields to pass summary data (status, counts, errors)
- Any cleanup or notification logic in `finish()` has its own governor limits

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

### Platform Events: Enabling Parallel Fanout and Cursor Access

**Why Platform Events?** Platform Events serve two critical purposes in the framework:

1. **Cursor User Affinity**: `Database.Cursor` is only accessible to the user who created it. By routing the coordinator through a Platform Event trigger, both coordinator and workers run as the same dedicated user, enabling cursor access.

2. **Parallel Worker Fanout**: Salesforce Queueable chaining is limited to **1 child job per execution**. Platform Events bypass this, allowing 50+ parallel workers to be spawned simultaneously.

**The flow:**

1. **`submit()`** creates a job record and publishes `CursorBatch_Coordinator__e`
2. **Coordinator Trigger** (`CursorBatchCoordinatorTrigger`) enqueues the coordinator queueable
3. **Coordinator** (Queueable) creates `Database.Cursor` and publishes `CursorBatch_Worker__e` events
4. **Worker Trigger** (`CursorBatchWorkerTrigger`) enqueues the worker queueables
5. **Workers** can access the cursor because they run as the same user who created it

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              User calls submit()                             │
│                     (Creates job record, publishes Coordinator PE)           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │ CursorBatch_          │
                          │ Coordinator__e        │
                          │ (Platform Event)      │
                          └───────────────────────┘
                                      │
                                      ▼ (runs as dedicated trigger user)
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
                   │ (same user)      │                  │
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
| `Skip_Duplicate_Check__c` | Checkbox | `false` | When enabled, allows multiple instances of the same job to run concurrently (bypasses duplicate detection) |

### CursorBatch_Job__c Fields

| Field | Type | Description |
|-------|------|-------------|
| `Job_Name__c` | Text | Job identifier matching config MasterLabel |
| `Status__c` | Picklist | `Preparing` → `Processing` → `Completed`/`Completed with Errors`/`Failed` |
| `Total_Workers__c` | Number | Number of parallel workers created |
| `Workers_Finished__c` | Number | Workers that completed all their assigned pages |
| `Total_Batches__c` | Number | Expected total batch/page executions |
| `Completed_Batches__c` | Number | Total batch/page executions completed |
| `Percent_Complete__c` | Formula (%) | Percentage of batches completed (Completed_Batches / Total_Batches × 100) |
| `Failed_Workers__c` | Number | Workers that failed after exhausting retries |
| `Total_Records__c` | Number | Total records in cursor result set |
| `Total_Cursor_Retries__c` | Number | Coordinator retry attempts (cursor query timeouts) |
| `Total_Worker_Retries__c` | Number | Sum of all worker retry attempts across the job |
| `Coordinator_Class__c` | Text | Fully qualified coordinator class name |
| `Cursor_Query_Id__c` | Text | Cursor queryId for cross-transaction access |
| `Query__c` | Long Text | SOQL query used |
| `Query_Duration_Ms__c` | Number | Time to execute cursor query (ms) |
| `Worker_Processing_Time_Min__c` | Formula | Estimated worker processing time in minutes |
| `Error_Message__c` | Long Text | Error details if failed |
| `Started_At__c` | DateTime | Job start time |
| `Completed_At__c` | DateTime | Job completion time |

### Job Statuses

| Status | Description |
|--------|-------------|
| `Preparing` | Job record created, cursor query pending or in progress |
| `Processing` | Cursor query succeeded, workers are processing records |
| `Completed` | All workers completed successfully |
| `Completed with Errors` | Some workers succeeded, some failed |
| `Failed` | All workers failed, or max retries exhausted |

## Important: Cursor Snapshot Behavior

The `Database.Cursor` captures a **snapshot of record IDs** at query time, not a live view. This has significant implications for your worker logic:

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

### When to Revalidate Entry Conditions

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

## Advanced Usage

### Monitoring Jobs

Query `CursorBatch_Job__c` for job status:

```apex
List<CursorBatch_Job__c> jobs = [
    SELECT Job_Name__c, Status__c, Total_Workers__c, 
           Workers_Finished__c, Total_Batches__c, Completed_Batches__c, 
           Percent_Complete__c, Failed_Workers__c,
           Total_Worker_Retries__c, Worker_Processing_Time_Min__c,
           Started_At__c, Completed_At__c, Error_Message__c
    FROM CursorBatch_Job__c
    WHERE Job_Name__c = 'MyDataProcessingJob'
    ORDER BY CreatedDate DESC
    LIMIT 10
];
```

**Interpreting Metrics:**

| Field | Healthy Value | Investigate If |
|-------|---------------|----------------|
| `Percent_Complete__c` | 100% | Stuck below 100% for extended periods |
| `Total_Worker_Retries__c` | 0 | > 0 indicates transient failures (timeouts, rate limits) |
| `Worker_Processing_Time_Min__c` | Varies | Significantly higher than expected |
| `Status__c` | `Completed` | `Completed with Errors` or `Failed` |

The framework includes two list views for monitoring:
- **All Jobs** — Shows all job records
- **Today's Jobs** — Filtered to jobs created today

### Job Chaining

Chain jobs in the `finish()` callback:

```apex
public override void finish(CursorBatch_Job__c jobRecord) {
    if (jobRecord.Status__c == 'Completed') {
        new NextStepCoordinator().submit();
    }
}
```

#### Delayed Job Submission

Use `submitWithDelay()` to defer job execution by 1-10 minutes. This is useful for rate limiting, scheduled retries, or self-chaining patterns:

```apex
// Start a job after a 5-minute delay
new MyCoordinator().submitWithDelay(5);
```

#### Self-Chaining Pattern

A common pattern is for a job to re-enqueue itself with a delay, enabling continuous processing with built-in throttling:

```apex
public class RecurringSyncCoordinator extends CursorBatchCoordinator {
    
    private static final Integer DELAY_MINUTES = 10;
    
    public RecurringSyncCoordinator() {
        super('RecurringSyncJob');
    }
    
    public override String buildQuery() {
        return 'SELECT Id FROM Account WHERE Needs_Sync__c = true LIMIT 10000';
    }
    
    public override String getWorkerClassName() {
        return 'RecurringSyncWorker';
    }
    
    public override void finish(CursorBatch_Job__c jobRecord) {
        super.finish(jobRecord);
        
        // Re-enqueue self with delay for continuous processing
        // Useful for:
        // - Rate-limited API integrations
        // - Continuous data sync that should run periodically
        // - Processing that should pause between batches
        if (jobRecord.Status__c == 'Completed' || jobRecord.Status__c == 'Completed with Errors') {
            new RecurringSyncCoordinator().submitWithDelay(DELAY_MINUTES);
        }
    }
}
```

**Key considerations for self-chaining:**

| Consideration | Recommendation |
|---------------|----------------|
| **Delay range** | 1-10 minutes (platform limit for `System.enqueueJob` delay parameter) |
| **Stopping condition** | Include logic to stop the chain (e.g., no records, error threshold, time window) |
| **Duplicate prevention** | The framework's built-in duplicate detection prevents overlapping runs |
| **Monitoring** | Each cycle creates a new `CursorBatch_Job__c` record for tracking |

### Preventing Duplicate Jobs

The framework automatically prevents duplicate jobs by checking:

1. `CursorBatch_Job__c` records with `Status__c IN ('Preparing', 'Processing')`
2. `AsyncApexJob` for running queueables of the same coordinator class

#### Skip Duplicate Check Option

If you need to allow multiple instances of the same job to run concurrently, enable `Skip_Duplicate_Check__c` in your `CursorBatch_Config__mdt` record. This bypasses both checks above.

**Use cases for skipping duplicate detection:**
- Jobs that process different data subsets and can safely run in parallel
- High-frequency jobs where overlap is acceptable
- Testing or debugging scenarios

> **Caution:** When duplicate detection is disabled, ensure your job logic is idempotent and can handle concurrent execution without data corruption.

#### Self-Chaining from finish()

When using `submitWithDelay()` from within `finish()` for continuous processing patterns, the framework automatically excludes the current job from duplicate detection. This allows the self-chaining pattern to work correctly even when duplicate detection is enabled.

#### Custom Duplicate Detection

Override `isJobAlreadyRunning()` for custom logic:

```apex
protected override Boolean isJobAlreadyRunning(String jobName) {
    // Custom duplicate detection
    return false;
}
```

### Coordinators with Multiple Query Modes

For coordinators that support different query modes (e.g., different billing types, date ranges, or filter criteria), follow this pattern:

```apex
public class BillingBatchCoordinator extends CursorBatchCoordinator {
    
    public static final String JOB_NAME_DAILY = 'Billing Batch Daily';
    public static final String JOB_NAME_MONTHLY = 'Billing Batch Monthly';
    
    public enum BillingType { DAILY, MONTHLY }
    
    private BillingType billingType;
    
    // REQUIRED: No-arg constructor for retry/finish callbacks
    public BillingBatchCoordinator() {
        super();
    }
    
    // Parameterized constructor for normal execution
    public BillingBatchCoordinator(BillingType billingType) {
        super(billingType == BillingType.DAILY ? JOB_NAME_DAILY : JOB_NAME_MONTHLY);
        this.billingType = billingType;
    }
    
    public override String buildQuery() {
        if (billingType == BillingType.DAILY) {
            return 'SELECT Id FROM Invoice__c WHERE Type__c = \'Daily\'';
        } else {
            return 'SELECT Id FROM Invoice__c WHERE Type__c = \'Monthly\'';
        }
    }
    
    public override String getWorkerClassName() {
        return 'BillingBatchWorker';
    }
    
    public override void finish(CursorBatch_Job__c jobRecord) {
        // Set logger based on job name (since no-arg constructor was used)
        setLogger(MyLoggerAdapter.getInstance(jobRecord.Job_Name__c));
        super.finish(jobRecord);
        
        // Chain to next job based on job name
        if (jobRecord.Job_Name__c == JOB_NAME_DAILY) {
            // Chain to daily post-processing...
        }
    }
    
    public static void runDaily() {
        new BillingBatchCoordinator(BillingType.DAILY).submit();
    }
    
    public static void runMonthly() {
        new BillingBatchCoordinator(BillingType.MONTHLY).submit();
    }
}
```

**Key points:**

1. **No-arg constructor is required** — The finalizer and completion handler use `Type.newInstance()` which only works with no-arg constructors
2. **Query is stored on first run** — The framework stores the query in `Query__c` during `submit()`, so retries don't need to reconstruct coordinator state
3. **Use job name to determine mode** — In `finish()`, check `jobRecord.Job_Name__c` to determine which mode just completed
4. **Set logger in finish()** — Since the no-arg constructor doesn't know the job name, set the logger at the start of `finish()` if using a custom logger

### Parent/Child Pattern for Avoiding Record Locks

When processing child records in parallel, you may encounter `UNABLE_TO_LOCK_ROW` errors. The parent/child pattern prevents this.

#### The Problem

When the coordinator queries **child records directly** and distributes them across workers:

```
Coordinator queries: SELECT Id FROM Opportunity WHERE StageName = 'Prospecting'

Worker 1 receives: Opp A (Account X), Opp C (Account Y)
Worker 2 receives: Opp B (Account X), Opp D (Account Z)
                        ↑
                    PROBLEM: Both workers have Opportunities from Account X
```

When Worker 1 and Worker 2 simultaneously update Opportunities belonging to the same Account:
- Master-detail relationships lock the parent during child DML
- Rollup summary fields trigger parent recalculation
- **Result:** `UNABLE_TO_LOCK_ROW` errors and failed batches

#### The Solution

Query **parent records** in the coordinator, then have workers query and process **child records** for their assigned parents:

```
Coordinator queries: SELECT Id FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE StageName = 'Prospecting')

Worker 1 receives: Account X, Account Y
Worker 2 receives: Account Z, Account W

Worker 1 queries: SELECT Id FROM Opportunity WHERE AccountId IN :accountIds AND StageName = 'Prospecting'
  → Gets ALL Opportunities for Account X and Y
  → No other worker touches these Opportunities

Worker 2 queries: SELECT Id FROM Opportunity WHERE AccountId IN :accountIds AND StageName = 'Prospecting'
  → Gets ALL Opportunities for Account Z and W
  → No overlap with Worker 1
```

**Result:** All children of a given parent are processed by the **same worker**. No cross-worker lock contention.

#### When to Use This Pattern

| Scenario | Use Parent/Child Pattern? |
|----------|---------------------------|
| Master-detail relationships | **Yes** — child DML locks the master |
| Rollup summary fields on parent | **Yes** — parent recalculates during child DML |
| Lookup relationships with triggers | **Maybe** — if triggers update the parent |
| Independent records (no parent) | **No** — use simple pattern |
| Parent updates only (no child DML) | **No** — use simple pattern |

#### Implementation Example

**Coordinator**: Query parent records that have qualifying children

```apex
public class AccountOpportunityCoordinator extends CursorBatchCoordinator {
    
    public AccountOpportunityCoordinator() {
        super('AccountOpportunityJob');
    }
    
    public override String buildQuery() {
        // Query Accounts that have Opportunities in target stage
        return 'SELECT Id FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE StageName = \'Prospecting\')';
    }
    
    public override String getWorkerClassName() {
        return 'AccountOpportunityWorker';
    }
}
```

**Worker**: Query and process children for the received parents

```apex
public class AccountOpportunityWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        // Extract parent IDs
        Set<Id> accountIds = new Map<Id, SObject>(records).keySet();
        
        // Query children for these specific parents
        List<Opportunity> opportunities = [
            SELECT Id, StageName, AccountId
            FROM Opportunity
            WHERE AccountId IN :accountIds
            AND StageName = 'Prospecting'
        ];
        
        // Process and update children
        for (Opportunity opp : opportunities) {
            opp.StageName = 'Qualification';
        }
        update opportunities;
    }
}
```

> **Note:** See `unpackaged/classes/SampleAccountOpportunityCoordinator.cls` and `SampleAccountOpportunityWorker.cls` for a complete working example.

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
| Worker distribution | INFO | `Distributing 50000 records across 50 workers (200 batches) via Platform Events` |
| Cursor queryId | INFO | `CursorBatchCoordinator extracted cursor queryId: 0r8xx50caotWO4i` |
| Job record creation | INFO | `CursorBatchCoordinator created job record in submit: a0B...` |
| Event publishing | INFO | `CursorBatchCoordinator published 50 worker events for MyJob` |
| Worker processing | INFO | `CursorBatchWorker (MyJob #1) processing 100 records at position 0` |
| Worker retry | INFO | `CursorBatchWorker (MyJob #1) processing 100 records at position 0 (retry 1)` |
| Retry scheduling | INFO | `CursorBatchWorker (MyJob #1) scheduling retry 1 of 3 in 1 min at position 0` |
| Finalizer retry | INFO | `CursorBatchWorkerFinalizer: Scheduling retry 1 of 3 for worker #1 in 1 min` |
| Max retries exhausted | ERROR | `CursorBatchWorker (MyJob #1) max retries (3) exhausted at position 0` |
| Worker completion | INFO | `CursorBatchWorker (MyJob) worker #1 completed. Position: 0, EndPosition: 1000` |
| Job completion | INFO | `CursorBatchCompletionHandler: Job MyJob completed. Status: Completed, Workers Finished: 48, Failed: 2` |
| Errors | ERROR | `CursorBatchCoordinator error for MyJob: INVALID_QUERY...` |
| Exceptions | ERROR | Full stack trace included via `logException()` |

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
- Job status set to `'Completed with Errors'` if some workers fail, `'Failed'` if all workers fail
- `finish()` callback is always invoked, even on failure, allowing cleanup/notifications

## Troubleshooting

### "No active config found for job"

- Create a `CursorBatch_Config__mdt` record with matching `MasterLabel`
- Set `Active__c = true`

### Workers not processing

- Check Platform Event trigger is deployed
- Verify `CursorBatchWorkerTrigger` is active
- Deploy `CursorBatchWorkerTriggerConfig` subscriber config (see [Post-Install Setup](#post-install-setup))
- Review debug logs for errors

### finish() callback not firing

- Deploy `CursorBatchWorkerCompleteTriggerConfig` subscriber config (see [Post-Install Setup](#post-install-setup))
- Verify `CursorBatchWorkerCompleteTrigger` is active in Setup → Platform Events → `CursorBatch_WorkerComplete__e` → Subscriptions
- Check that the run-as user has permissions to instantiate your coordinator class

### Job stuck at "Preparing"

- Large datasets may require longer cursor query times

### Job shows "Completed with Errors"

- Check `Failed_Workers__c` for count of failed workers
- Review `Error_Message__c` for the first captured error
- Check `Total_Worker_Retries__c` to see if retries were attempted

## Components

### Apex Classes

| Class | Description |
|-------|-------------|
| `CursorBatchCoordinator` | Abstract base for coordinators (Queueable, AllowsCallouts). Runs query, creates cursor, publishes Platform Events to fan out workers |
| `CursorBatchCoordinatorFinalizer` | Queueable finalizer that handles cursor query timeouts with automatic retry logic |
| `CursorBatchCoordinatorTriggerHandler` | Platform Event trigger handler that enqueues coordinator Queueable from submit() |
| `CursorBatchWorker` | Abstract base for workers (Queueable, AllowsCallouts). Processes record batches from cursor positions, supports retry for failed pages |
| `CursorBatchWorkerFinalizer` | Queueable finalizer that handles worker retry and publishes completion events |
| `CursorBatchWorkerTriggerHandler` | Platform Event trigger handler that enqueues Queueable workers from events |
| `CursorBatchRetryException` | Custom exception to explicitly request page retry with optional delay |
| `CursorBatchContext` | Value object encapsulating worker execution parameters including retry state and final page tracking |
| `CursorBatchCompletionHandler` | Handles worker completion events and invokes callbacks |
| `CursorBatchSelector` | Centralized selector class for all SOQL queries in the framework |
| `CursorBatchLogger` | Default `System.debug` logger implementation |
| `ICursorBatchLogger` | Interface for custom logging integrations |

### Custom Objects

| Object | Type | Description |
|--------|------|-------------|
| `CursorBatch_Config__mdt` | Custom Metadata | Job configuration (parallelism, page size, retry settings) |
| `CursorBatch_Job__c` | Custom Object | Job tracking (status, worker counts, progress, timing) |
| `CursorBatch_Coordinator__e` | Platform Event | Routes coordinator execution through trigger for cursor user affinity |
| `CursorBatch_Worker__e` | Platform Event | Orchestration events from coordinator to trigger worker enqueueing (includes retry count) |
| `CursorBatch_WorkerComplete__e` | Platform Event | Worker completion signals for callbacks (includes retry count, Is_Final flag for final page tracking) |

### Triggers

| Trigger | Event | Description |
|---------|-------|-------------|
| `CursorBatchCoordinatorTrigger` | `CursorBatch_Coordinator__e` | Enqueues coordinator from submit() events |
| `CursorBatchWorkerTrigger` | `CursorBatch_Worker__e` | Spawns workers from coordinator events |
| `CursorBatchWorkerCompleteTrigger` | `CursorBatch_WorkerComplete__e` | Handles completion and callbacks |

## License

MIT License — see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Submit a pull request
