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
- 🧩 **Pluggable Logging** — Integrate with Nebula Logger, Pharos, or custom solutions with convention-based discovery
- 🔁 **Built-in Retry Support** — Automatic retry for both coordinator cursor queries AND worker page failures
- 🎛️ **Caller-Controlled Retry** — Throw `CursorBatchRetryException` to explicitly request page retry
- 🌐 **Callout Support** — Both coordinator and workers implement `Database.AllowsCallouts` for HTTP callouts
- 🚀 **Metadata-Driven Jobs** — Use `CursorJob` to configure jobs entirely in metadata with zero boilerplate code
- 📦 **Reducer-Based Shared State** — Optional shared state across parallel workers with snapshot reads, delta emission, and centralized reduction
- 📄 **CSV File Processing** — Process uploaded CSV files (up to 2 GB) through an external middleware with the same config-driven API, reducers, and chaining
- 👨‍👦 **Per-Config Parent Records** — Every metadata-defined job gets a single `CursorBatch_Job_Parent__c` record aggregating all runs of that job, with last status, last started time, and a `Job_Parent__c` lookup on every run — no extra code required

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
  - [Option A: Metadata-Driven Jobs (CursorJob)](#option-a-metadata-driven-jobs-cursorjob)
  - [Option B: Custom Coordinator Classes](#option-b-custom-coordinator-classes)
  - [Option C: CSV File Processing](#option-c-csv-file-processing)
- [Architecture](#architecture)
- [Configuration Reference](#configuration-reference)
- [Important: Cursor Snapshot Behavior](#important-cursor-snapshot-behavior)
- [Advanced Usage](#advanced-usage)
  - [Monitoring Jobs](#monitoring-jobs)
  - [Per-Config Parent Records](#per-config-parent-records)
  - [Job Chaining](#job-chaining)
  - [Worker finish() Method](#worker-finish-method)
  - [Reducer-Based Shared State](#reducer-based-shared-state)
  - [Job Invocation Metadata](#job-invocation-metadata)
  - [Preventing Duplicate Jobs](#preventing-duplicate-jobs)
  - [Kill Switch (Cancelling Jobs)](#kill-switch-cancelling-jobs)
  - [Parent/Child Pattern for Avoiding Record Locks](#parentchild-pattern-for-avoiding-record-locks)
  - [Pluggable Logging](#pluggable-logging)
  - [Convention-Based Logger Discovery](#convention-based-logger-discovery)
- [Migration Guide](#migration-guide)
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
| **Production** | [Install in Production](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000J121AAC) |
| **Sandbox** | [Install in Sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000J121AAC) |

#### Option 2: Install via Salesforce CLI

```bash
sf package install --package 04tfj000000J121AAC --target-org your-org --wait 10
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
| **Cursor Batch Job Viewer** | Grants read access and View All Records on `CursorBatch_Job__c` and `CursorBatch_Job_Parent__c` objects, with tab visibility on both. Assign to users who need to monitor batch job progress and per-config job history. |

## Quick Start

Choose your approach based on complexity:

| Approach | Best For | Boilerplate |
|----------|----------|-------------|
| **CursorJob (Metadata-Driven)** | Simple jobs with standard query/worker pattern | Zero code — configure in metadata |
| **Custom Coordinator** | Complex logic, conditional queries, custom callbacks | ~50-80 lines |
| **CSV File Processing** | Process uploaded CSV files with same config-driven API | Worker class only (~20 lines) |

### Option A: Metadata-Driven Jobs (CursorJob)

For most batch jobs, you can eliminate coordinator classes entirely and configure everything in metadata.

#### 1. Create a Worker

```apex
public class MyDataProcessingWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        List<Account> accounts = (List<Account>) records;
        
        for (Account acc : accounts) {
            acc.Status__c = 'Processed';
        }
        
        update accounts;
    }
}
```

#### 2. Implement ICursorBatchQueryBuilder in Your Selector

Extend your selector to provide queries for metadata-driven jobs:

```apex
public class AccountSelector implements ICursorBatchQueryBuilder {
    
    // Required by ICursorBatchQueryBuilder - routes method names to actual methods
    public String buildQuery(String methodName) {
        switch on methodName {
            when 'buildPendingAccountsQuery' {
                return buildPendingAccountsQuery();
            }
            when else { 
                return null; 
            }
        }
    }
    
    public String buildPendingAccountsQuery() {
        return 'SELECT Id, Name, Status__c FROM Account WHERE Status__c = \'Pending\'';
    }
}
```

#### 3. Configure Metadata

Create a `CursorBatch_Config__mdt` record:

| Field | Value |
|-------|-------|
| **MasterLabel** | `MyDataProcessingJob` |
| **Active__c** | `true` |
| **Query_Builder_Class__c** | `AccountSelector` |
| **Query_Builder_Method__c** | `buildPendingAccountsQuery` |
| **Worker_Class__c** | `MyDataProcessingWorker` |
| **Logger_Tag__c** | `Data Processing` (optional) |

#### 4. Execute

```apex
// Returns the CursorBatch_Job__c record Id (or null if a duplicate was already running)
Id jobId = CursorJob.run('MyDataProcessingJob');

// Or with a delay (1-10 minutes)
Id jobId = CursorJob.runWithDelay('MyDataProcessingJob', 5);

// Or with runtime metadata (e.g., a record ID for the query builder or worker)
Id jobId = CursorJob.run('MyDataProcessingJob', new Map<String, Object>{
    'accountId' => '001xx0000012345'
});
```

**That's it!** No coordinator class needed. All `run()` and `runWithDelay()` overloads return the `CursorBatch_Job__c` record `Id`, letting callers immediately track, query, or link to the job. Returns `null` when duplicate detection prevents submission.

---

### Option B: Custom Coordinator Classes

For complex scenarios requiring custom logic, conditional queries, or specialized callbacks, create a coordinator class.

#### 1. Create a Coordinator

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

#### 2. Create a Worker

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

#### 3. Configure the Job

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

#### 4. Execute

```apex
// submit() returns the CursorBatch_Job__c record Id (or null if duplicate)
Id jobId = new MyDataProcessingCoordinator().submit();
```

### Option C: CSV File Processing

Process uploaded CSV files using the same framework — same config-driven API, same reducers, same chaining. The only difference is the `process()` signature.

#### 1. Create a CSV Worker

```apex
public class LeadImportWorker extends CursorBatchCsvWorker {

    public override void process(List<Map<String, Object>> rows) {
        List<Lead> leads = new List<Lead>();
        for (Map<String, Object> row : rows) {
            leads.add(new Lead(
                FirstName = (String) row.get('FirstName'),
                LastName  = (String) row.get('LastName'),
                Email     = (String) row.get('Email'),
                Company   = (String) row.get('Company')
            ));
        }
        upsert leads Email;
    }
}
```

All other overridable methods — `buildStateDelta()`, `buildSerializedWorkerState()`, `finish()`, `onComplete()` — work identically to SOQL workers.

#### 2. Create Config Record

| Field | Value |
|-------|-------|
| `MasterLabel` | `Lead CSV Import` |
| `Processing_Type__c` | `CSV` |
| `Worker_Class__c` | `LeadImportWorker` |
| `Parallel_Count__c` | `10` |
| `Page_Size__c` | `200` |
| `Active__c` | `true` |

No `Query_Builder_Class__c` is needed for CSV jobs.

#### 3. Set Up the CSV Middleware

The framework uses an external middleware ([cursor-csv](https://github.com/ndrg2010/cursor-csv)) that indexes CSV files and serves rows via HTTP. The middleware calls back into Salesforce via Platform Events when indexing is complete — no polling.

Deploy the Named Credential and External Credential from `unpackaged/`:

```bash
sf project deploy start --source-dir unpackaged/namedCredentials/
sf project deploy start --source-dir unpackaged/externalCredentials/
```

Update the Named Credential URL to point at your middleware instance.

#### 4. Run

```apex
CursorJob.run('Lead CSV Import', new Map<String, Object>{
    'contentVersionId' => '068xx...'
});
```

The `contentVersionId` is the Salesforce `ContentVersion` ID of the uploaded CSV file. The framework handles everything else: middleware session init, callback, fan-out, parallel processing, retry, completion, and chaining.

#### CSV Architecture

```
CursorJob.run() → createJobRecord (Preparing) → CursorBatch_Coordinator__e
    → CursorJob.execute() detects CSV → CsvCursorClient.initSession()
    → Persist csvQueryId, status → Extracting File
    → Middleware indexes file → CursorBatch_Coordinator__e (CSV_Ready)
    → CursorBatchCsvCallbackCoordinator.execute()
        → CsvCursorClient.getRowCount() → fanOutJob() (Processing) → CursorBatch_Worker__e
    → Workers: CsvCursorClient.getRows() → process(List<Map<String, Object>>)
    → Completion: same as SOQL (reducers, finish, chaining)
```

## Architecture

### Queueable Execution Model

Both the **Coordinator** and **Workers** are implemented as `Queueable` classes:

- **`CursorBatchCoordinator`** (Queueable): Executes the SOQL query, creates a `Database.Cursor`, extracts its queryId for cross-transaction access, and publishes Platform Events to fan out workers. Uses a Queueable Finalizer to handle cursor query timeouts with automatic retries. **Routed through a Platform Event** to ensure it runs as the dedicated trigger user.
- **`CursorBatchWorker`** (Queueable): Processes batches of records from assigned cursor positions. Workers can re-enqueue themselves to process subsequent pages within their assigned range.

### Cursor User Affinity

`Database.Cursor` is only accessible to the user who created it. To ensure workers can access the cursor:

1. **`submit()` publishes a Platform Event** (`CursorBatch_Coordinator__e`) instead of directly enqueueing the coordinator, and returns the `CursorBatch_Job__c` record `Id` (or `null` if the job was already running)
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
- Use `getCurrentState()` to read the final reduced state and `getMetadata()` to read runtime parameters — both work in `process()` and `finish()` with the same API
- Use `CursorBatch_Job__c` fields to read job-level summary data (status, counts, errors)
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

#### Core Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Active__c` | Checkbox | — | Must be `true` to run |
| `Parallel_Count__c` | Number | 50 | Max concurrent workers |
| `Page_Size__c` | Number | 20 | Records per cursor fetch |
| `Coordinator_Max_Retries__c` | Number | 3 | Max retry attempts for coordinator cursor query timeouts |
| `Worker_Max_Retries__c` | Number | 3 | Max retry attempts for failed worker page processing |
| `Worker_Retry_Delay__c` | Number | 1 | Base delay in minutes for worker retry exponential backoff |
| `Skip_Duplicate_Check__c` | Checkbox | `false` | When enabled, allows multiple instances of the same job to run concurrently (bypasses duplicate detection) |
| `Processing_Type__c` | Text(10) | `SOQL` | Data source type: `SOQL` for cursor-based queries, `CSV` for file-based processing via external middleware |
| `Enable_State_Reducer__c` | Checkbox | `false` | When enabled, uses built-in `CursorBatchCounterReducer` for additive numeric counter state (no custom reducer class needed). Ignored when `State_Reducer_Class__c` is set |

#### CursorJob Settings (Metadata-Driven Jobs)

| Field | Type | Description |
|-------|------|-------------|
| `Query_Builder_Class__c` | Text(255) | Class implementing `ICursorBatchQueryBuilder` |
| `Query_Builder_Method__c` | Text(255) | Method name to call on query builder |
| `Worker_Class__c` | Text(255) | Worker class extending `CursorBatchWorker` |
| `Chain_To_Job__c` | Text(255) | Job name (MasterLabel) to chain to after completion — simplest chaining option |
| `Chain_To_Class__c` | Text(255) | Class to chain to after completion (must implement `Callable`) |
| `Chain_To_Method__c` | Text(255) | Method to call on chain class (default: `run`) |
| `Logger_Tag__c` | Text(255) | Tag to apply to all log entries |
| `State_Reducer_Class__c` | Text(255) | Optional class implementing `ICursorBatchStateReducer` for reducer-based shared state in `CursorJob` |

**Note:** When `Query_Builder_Class__c` is set, use `CursorJob.run('JobName')` instead of creating a coordinator class.

### CursorBatch_Job__c Fields

| Field | Type | Description |
|-------|------|-------------|
| `Job_Name__c` | Text | Job identifier matching config MasterLabel |
| `Status__c` | Picklist | `Preparing` → [`Extracting File` →] `Processing` → `Completed`/`Completed with Errors`/`Failed` |
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
| `Query_Duration_Ms__c` | Number | Time to execute cursor query (SOQL) or middleware indexing time (CSV), in ms |
| `Worker_Processing_Time_Min__c` | Formula | Estimated worker processing time in minutes |
| `Error_Message__c` | Long Text | Error details if failed |
| `State_JSON__c` | Long Text | Serialized reducer-managed shared state for stateful `CursorJob` runs |
| `Metadata_JSON__c` | Long Text | Optional JSON metadata passed at job invocation time (runtime parameters for query builders and workers) |
| `Started_At__c` | DateTime | Job start time |
| `Completed_At__c` | DateTime | Job completion time |
| `Job_Parent__c` | Lookup | Optional link to the per-config `CursorBatch_Job_Parent__c` record. Set automatically by the framework when an active `CursorBatch_Config__mdt` matches the job name; `null` for custom coordinators with no metadata config |

### Job Statuses

| Status | Description |
|--------|-------------|
| `Preparing` | Job record created, cursor query pending or in progress |
| `Extracting File` | CSV middleware is indexing the uploaded file (CSV jobs only) |
| `Processing` | Cursor query succeeded, workers are processing records |
| `Completed` | All workers completed successfully |
| `Completed with Errors` | Some workers succeeded, some failed |
| `Failed` | All workers failed, or max retries exhausted |
| `Cancelled` | Job was manually stopped via kill switch (`killJob()`) |

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

### Per-Config Parent Records

Every metadata-defined job (i.e. any job backed by a `CursorBatch_Config__mdt` record) gets a single, persistent `CursorBatch_Job_Parent__c` record that aggregates all runs of that config. This gives operators a stable landing page per job, with a related list of every historical run, instead of having to filter the All Jobs list by `Job_Name__c`.

Custom coordinators that are *not* backed by a metadata config leave `Job_Parent__c` null and behave exactly as before.

#### How parents are populated

The framework manages the parent for you — there is nothing to wire up:

1. On `submit()`, `CursorBatchCoordinator` looks up the active `CursorBatch_Config__mdt` for the job name. If found, it upserts a `CursorBatch_Job_Parent__c` record using the config's `DeveloperName` as the external-ID key (Salesforce does not allow Lookup fields to target custom metadata records, so the unique external-ID enforces 1:1 with the config).
2. The new run record links to the parent via the `Job_Parent__c` lookup field.
3. `Last_Job_Started_At__c` is refreshed on every run.
4. `Last_Job_Status__c` mirrors the run lifecycle in real time: `Preparing` on submission, `Processing` once the cursor query succeeds, then `Completed` / `Completed with Errors` / `Failed` / `Cancelled` on termination. The parent always reflects the latest run's current state, never a previous run's stale terminal status.

All parent writes are best-effort and wrapped in try/catch; any FLS, sharing, or validation issue on the parent object is logged and swallowed so it can never block job creation or completion.

#### Parent fields

| Field | Type | Description |
|-------|------|-------------|
| `Name` | Auto Number (`CBJP-{0000000}`) | Stable display key |
| `Config_Developer_Name__c` | Text(40), unique external ID | Anchors the 1:1 relationship to `CursorBatch_Config__mdt.DeveloperName` |
| `Config_Label__c` | Text(255) | Denormalized copy of `CursorBatch_Config__mdt.MasterLabel`, refreshed on every run |
| `Description__c` | Long Text Area | Customer-managed free-form notes — never written by the framework |
| `Last_Job_Started_At__c` | DateTime | Refreshed at every run submission |
| `Last_Job_Status__c` | Text(40) | Live status of the most recent run — `Preparing` on submit, `Processing` once the cursor query succeeds, then `Completed` / `Completed with Errors` / `Failed` / `Cancelled` on termination |

#### Working with the parent in code

Because the link is a standard lookup, you can navigate from runs to their parent (and back) with normal SOQL:

```apex
// All runs of a given config, newest first
List<CursorBatch_Job__c> runs = [
    SELECT Id, Status__c, Started_At__c, Completed_At__c
    FROM CursorBatch_Job__c
    WHERE Job_Parent__r.Config_Developer_Name__c = 'My_Sync_Job'
    ORDER BY CreatedDate DESC
    LIMIT 50
];

// Current state of every metadata-defined job
List<CursorBatch_Job_Parent__c> parents = [
    SELECT Name, Config_Label__c, Last_Job_Status__c, Last_Job_Started_At__c
    FROM CursorBatch_Job_Parent__c
    ORDER BY Last_Job_Started_At__c DESC NULLS LAST
];
```

#### Lightning record pages

The package ships two Lightning record pages, both set as the org default:

- **Cursor Batch Job Record Page** — surfaces the new `Job Parent` lookup so users can navigate from a run to its parent in one click.
- **Cursor Batch Job Parent Record Page** — highlights panel (`Name`, `Config Label`, `Last Job Status`, `Last Job Started At`), free-form `Description__c` section, and a Jobs related list (`lst:dynamicRelatedList`) showing every historical run with `Name`, `Status`, `Percent Complete`, `Started At`, `Completed At`, `Total Records`, `Total Worker Retries`, and `Failed Workers`, sorted by Created Date desc, action bar visible, 20 records per page.

Both pages are assigned as the Lightning org default for both desktop (`Large`) and mobile (`Small`) form factors via `actionOverrides` in the source-controlled `CustomObject` metadata, so the assignment travels with deploys — no manual "Set as Org Default" click required after install.

### Job Chaining

The framework provides multiple ways to chain jobs, from simple metadata configuration to complex conditional logic.

#### Option 1: Chain_To_Job__c (Simplest)

For simple linear chaining, configure `Chain_To_Job__c` in your `CursorBatch_Config__mdt` record:

| Field | Value |
|-------|-------|
| `Chain_To_Job__c` | `Next Job Name` |

When the job completes, the framework automatically calls `CursorJob.run('Next Job Name')`. No code required.

#### Option 2: Chain_To_Class__c (Class-Based)

For chaining to a class that implements `Callable`:

| Field | Value |
|-------|-------|
| `Chain_To_Class__c` | `MyChainableClass` |
| `Chain_To_Method__c` | `submitJob` (optional, defaults to `run`) |

The class receives the job record for context:

```apex
public class MyChainableClass implements Callable {
    public Object call(String action, Map<String, Object> args) {
        CursorBatch_Job__c jobRecord = (CursorBatch_Job__c) args.get('jobRecord');
        // Chain logic here
        return null;
    }
}
```

#### Option 3: finish() Callback (Most Flexible)

For complex conditional logic, override `finish()` in your worker or coordinator:

```apex
public override void finish(CursorBatch_Job__c jobRecord) {
    if (jobRecord.Status__c == 'Completed') {
        new NextStepCoordinator().submit();
    }
}
```

#### Chaining Priority

When a job completes, the framework checks in order:

1. **Chain_To_Job__c** → Calls `CursorJob.run(jobName)`
2. **Chain_To_Class__c** → Invokes `Callable.call(method, args)`
3. **Query_Builder_Class__c set** (CursorJob) → Calls `worker.finish()`
4. **Custom Coordinator** → Calls `coordinator.finish()`

The first matching condition is executed; subsequent options are skipped.

#### Delayed Job Submission

Use `submitWithDelay()` to defer job execution by 1-10 minutes. This is useful for rate limiting, scheduled retries, or self-chaining patterns:

```apex
// Start a job after a 5-minute delay (returns job record Id or null)
Id jobId = new MyCoordinator().submitWithDelay(5);
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

### Job Invocation Metadata

Pass runtime parameters (record IDs, flags, contextual data) to jobs at invocation time. Metadata is persisted on the `CursorBatch_Job__c` record and automatically carried to every worker via Platform Events.

#### Invoking with Metadata

```apex
// Pass metadata as a map — serialized to JSON internally
CursorJob.run('Process Account Children', new Map<String, Object>{
    'accountId' => parentAccountId,
    'source' => 'nightly-sync'
});

// With a delay
CursorJob.runWithDelay('Sync Records', 5, new Map<String, Object>{
    'batchId' => myBatchId
});

// Custom coordinator with metadata (setMetadata accepts a JSON string)
MyCoordinator coord = new MyCoordinator();
coord.setMetadata('{"recordId": "001xx0000012345"}');
coord.submit();
```

#### Metadata-Aware Query Builders

When the query needs runtime parameters, implement `ICursorBatchMetadataQueryBuilder` instead of (or in addition to) `ICursorBatchQueryBuilder`. The framework deserializes the metadata JSON once and passes a ready-to-use `Map<String, Object>` (empty map when no metadata, never null):

```apex
public class ContactsByAccountSelector implements ICursorBatchMetadataQueryBuilder {
    
    public String buildQuery(String methodName, Map<String, Object> metadata) {
        String accountId = (String) metadata.get('accountId');
        
        switch on methodName {
            when 'buildContactsForAccountQuery' {
                if (String.isBlank(accountId)) {
                    return null;
                }
                return 'SELECT Id, Name FROM Contact WHERE AccountId = \'' +
                       String.escapeSingleQuotes(accountId) + '\'';
            }
            when else { return null; }
        }
    }
}
```

The framework automatically detects which interface your query builder implements. Existing `ICursorBatchQueryBuilder` implementations continue to work unchanged — the framework checks for the metadata interface first and falls back automatically.

#### Accessing Metadata in Workers

Workers access metadata via `getMetadata()`, which returns `Map<String, Object>` and works in both `process()` and `finish()`. Metadata is automatically preserved across pages and retries:

```apex
public class MyWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        Map<String, Object> meta = getMetadata();
        if (meta != null) {
            Id targetId = (Id) meta.get('recordId');
            // Use targetId during processing...
        }
        
        // Process records...
    }
}
```

> The raw JSON string is also available via `ctx.metadataJson` during `process()` if needed.

#### How Metadata Flows

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Metadata Propagation Flow                            │
└─────────────────────────────────────────────────────────────────────────────┘

  CursorJob.run(name, metadata)
       │
       ▼
  ┌──────────────────────┐
  │ CursorBatch_Job__c   │
  │ Metadata_JSON__c     │ ← persisted for auditing & coordinator retries
  └──────────────────────┘
       │
       ▼
  ┌──────────────────────┐
  │ ICursorBatch         │
  │ MetadataQueryBuilder │ ← buildQuery(methodName, metadata)
  │ .buildQuery()        │
  └──────────────────────┘
       │
       ▼
  ┌──────────────────────┐
  │ CursorBatch_Worker__e│
  │ Metadata_JSON__c     │ ← carried to workers via Platform Event
  └──────────────────────┘
       │
       ▼
  ┌──────────────────────┐
  │ CursorBatchContext   │
  │ ctx.metadataJson     │ ← available in process(), preserved across retries
  └──────────────────────┘
```

| Stage | How Metadata Is Available |
|-------|---------------------------|
| **Query Builder** | Passed as the second argument to `buildQuery(methodName, metadata)` as a pre-parsed `Map<String, Object>` |
| **Worker `process()`** | Via `getMetadata()` (or `ctx.metadataJson` for the raw JSON string) |
| **Worker `finish()`** | Via `getMetadata()` (reads from `CursorBatch_Job__c.Metadata_JSON__c`) |
| **Coordinator retries** | Restored from `CursorBatch_Job__c.Metadata_JSON__c` |

#### Backward Compatibility

- Invoking `CursorJob.run('JobName')` without metadata continues to work — `ICursorBatchMetadataQueryBuilder` receives an empty map (never null), and worker `getMetadata()` returns `null`
- Query builders implementing only `ICursorBatchQueryBuilder` are unaffected
- Workers that don't reference `ctx.metadataJson` are unaffected
- Custom coordinators that don't call `setMetadata()` behave exactly as before

### Preventing Duplicate Jobs

The framework automatically prevents duplicate jobs using a three-layer check:

1. **Job tracking records** — `CursorBatch_Job__c` with `Status__c IN ('Preparing', 'Extracting File', 'Processing')` and matching job name
2. **Coordinator class** — `AsyncApexJob` for running queueables of the coordinator class (skipped for `CursorJob` since all metadata-driven jobs share the same class)
3. **Worker class** — `AsyncApexJob` for running queueables of the worker class (guardrail for cases where job records were lost but workers are still running)

#### Skip Duplicate Check Option

If you need to allow multiple instances of the same job to run concurrently, enable `Skip_Duplicate_Check__c` in your `CursorBatch_Config__mdt` record. This bypasses both checks above.

**Use cases for skipping duplicate detection:**
- Jobs that process different data subsets and can safely run in parallel
- High-frequency jobs where overlap is acceptable
- Testing or debugging scenarios

> **Caution:** When duplicate detection is disabled, ensure your job logic is idempotent and can handle concurrent execution without data corruption.

#### Self-Chaining from finish()

When using `submitWithDelay()` from within `finish()` for continuous processing patterns, the framework automatically excludes the current job from duplicate detection. This allows the self-chaining pattern to work correctly even when duplicate detection is enabled.

### Kill Switch (Cancelling Jobs)

The framework provides a kill switch to stop running jobs gracefully. When activated, workers complete their current page but don't process additional pages.

#### Using the Kill Switch

```apex
// Capture the job record ID when launching
Id jobRecordId = CursorJob.run('MyDataProcessingJob');

// Cancel the job
Boolean cancelled = CursorBatchCoordinator.killJob(jobRecordId);

if (cancelled) {
    System.debug('Job cancelled successfully');
} else {
    System.debug('Job could not be cancelled (not found or already in terminal state)');
}
```

#### How It Works

1. `killJob()` sets the job status to `Cancelled` and records `Completed_At__c`
2. Workers check `CursorBatchSelector.isJobCancelled()` before enqueueing the next page
3. If cancelled, workers stop processing and call `onComplete()`
4. The completion handler preserves the `Cancelled` status (doesn't overwrite to `Completed` or `Failed`)
5. The `finish()` callback is **not invoked** for cancelled jobs

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Kill Switch Flow                                   │
└─────────────────────────────────────────────────────────────────────────────┘

  Admin/Code calls                Worker finishes
  killJob(jobId)                  current page
       │                               │
       ▼                               ▼
  ┌──────────────┐            ┌──────────────────┐
  │ Job.Status = │            │ isJobCancelled() │
  │ 'Cancelled'  │            │ returns true     │
  └──────────────┘            └──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │ Worker stops,    │
                              │ calls onComplete │
                              │ (no next page)   │
                              └──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │ Completion       │
                              │ handler skips    │
                              │ finish() callback│
                              └──────────────────┘
```

#### killJob() Return Values

| Return Value | Meaning |
|--------------|---------|
| `true` | Job was cancelled successfully |
| `false` | Job not found, or already in terminal state (`Completed`, `Failed`, `Completed with Errors`, `Cancelled`) |

#### Use Cases

- **Emergency stop** — Stop a runaway job that's causing issues
- **Maintenance windows** — Gracefully stop long-running jobs before deployments
- **User-initiated cancellation** — Allow admins to cancel jobs from a custom UI
- **Timeout handling** — Implement custom timeout logic that cancels stale jobs

### Worker finish() Method

Workers can implement completion logic that runs when ALL workers for a job complete. The `finish()` method has access to two framework-provided accessors that work the same way they do in `process()`:

| Accessor | Returns | What it contains |
|----------|---------|-----------------|
| `getCurrentState()` | `Map<String, Object>` | The fully reduced shared state from all workers |
| `getMetadata()` | `Map<String, Object>` | The runtime parameters passed at job launch |

Both return `null` when no data was provided.

**Example: Writing reduced state back to a record**

```apex
public class OrderSumWorker extends CursorBatchWorker {
    private Decimal pageTotal = 0;

    public override void process(List<SObject> records) {
        for (Order__c order : (List<Order__c>) records) {
            pageTotal += order.Amount__c;
        }
    }

    protected override Object buildStateDelta() {
        return new Map<String, Object>{ 'totalOrderAmount' => pageTotal };
    }

    public override void finish(CursorBatch_Job__c jobRecord) {
        Map<String, Object> state = getCurrentState();
        Map<String, Object> meta  = getMetadata();

        if (state == null || meta == null) {
            return;
        }

        update new Opportunity(
            Id = (Id) meta.get('opportunityId'),
            Amount = (Decimal) state.get('totalOrderAmount')
        );
    }
}
```

Launched with:

```apex
CursorJob.run('Order Sum Job', new Map<String, Object>{
    'opportunityId' => someOppId
});
```

**Example: Conditional chaining based on job results**

```apex
public class BillingBatchWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        // Process records...
    }
    
    public override void finish(CursorBatch_Job__c jobRecord) {
        String jobName = jobRecord.Job_Name__c;
        
        if (jobName == 'Billing Before Advance') {
            CursorJob.run('Submit For Advance Approval');
        } else if (jobName == 'Billing After Advance') {
            if (shouldRunGCS()) {
                CursorJob.run('GCS Debt Set Batch');
            }
        }
    }
}
```

#### Finish Flow Logic

When all workers complete, the framework determines which `finish()` method to call:

```
┌─────────────────────────┐
│   All Workers Complete  │
└───────────┬─────────────┘
            │
            ▼
    ┌───────────────────┐
    │ Chain_To_Class    │──Yes──▶ Invoke Chain_To_Class.method()
    │ is set?           │
    └───────┬───────────┘
            │ No
            ▼
    ┌───────────────────┐
    │ Query_Builder     │──Yes──▶ Call worker.finish()
    │ is set?           │         (CursorJob path)
    └───────┬───────────┘
            │ No
            ▼
    ┌───────────────────┐
    │ Custom Coordinator│──────▶ Call coordinator.finish()
    └───────────────────┘
```

| Config Pattern | What Happens | Use Case |
|----------------|--------------|----------|
| `Chain_To_Class__c` set | Invoke chain class directly | Simple linear chaining |
| `Query_Builder_Class__c` set (no chain) | Call `worker.finish()` | Complex conditional logic |
| Neither set | Call `coordinator.finish()` | Legacy custom coordinators |

### Reducer-Based Shared State

`CursorJob` can optionally persist reducer-managed shared state on the job record so workers can read a snapshot of the latest state and contribute deltas after successful page processing.

Configure `State_Reducer_Class__c` with a class that implements `ICursorBatchStateReducer`. Custom coordinator jobs also support stateful behavior: ensure the job's `CursorBatch_Config__mdt` has `State_Reducer_Class__c` set; the framework sets initial state at job creation and workers use the same reducer. No coordinator code change is required beyond using the same job name as the config. Custom coordinators can still override `getInitialJobStateJson()` to supply custom initial state (e.g. when not using a config reducer).

```apex
public class MyStateReducer implements ICursorBatchStateReducer {
    
    public Object createInitialState(CursorBatch_Job__c jobRecord) {
        return new Map<String, Object>{ 'processedCount' => 0 };
    }
    
    public Object reduce(Object currentState, Object delta, CursorBatch_Job__c jobRecord) {
        Map<String, Object> state = currentState != null
            ? (Map<String, Object>) currentState
            : new Map<String, Object>{ 'processedCount' => 0 };
        Map<String, Object> deltaMap = (Map<String, Object>) delta;
        Integer processedCount = ((Decimal) state.get('processedCount')).intValue();
        processedCount += ((Decimal) deltaMap.get('processedCount')).intValue();
        state.put('processedCount', processedCount);
        return state;
    }
    
    public String serializeState(Object state) { return JSON.serialize(state); }
    public Object deserializeState(String stateJson) { return JSON.deserializeUntyped(stateJson); }
    public String serializeDelta(Object delta) { return JSON.serialize(delta); }
    public Object deserializeDelta(String deltaJson) { return JSON.deserializeUntyped(deltaJson); }
}
```

Workers can read the current snapshot with `getCurrentState()` and emit a delta by overriding `buildStateDelta()`. Both `getCurrentState()` and `getMetadata()` return `Map<String, Object>` and work identically in `process()` and `finish()`:

```apex
public class MyStatefulWorker extends CursorBatchWorker {
    private Integer lastPageSize = 0;
    
    public override void process(List<SObject> records) {
        Map<String, Object> state = getCurrentState();
        Map<String, Object> meta  = getMetadata();
        // Both return Map<String, Object> — use .get('key') to access values
        lastPageSize = records.size();
    }
    
    protected override Object buildStateDelta() {
        return new Map<String, Object>{
            'processedCount' => lastPageSize
        };
    }
    
    public override void finish(CursorBatch_Job__c jobRecord) {
        Map<String, Object> finalState = getCurrentState();
        // finalState reflects the fully reduced State_JSON__c value
    }
}
```

**Semantics of v1 shared state:**

- Workers read a **snapshot** of `State_JSON__c` at page start; concurrent workers may see slightly stale state
- Workers do **not** write shared state directly; they emit deltas that are merged later in `CursorBatchCompletionHandler`
- Deltas are only applied after a page succeeds and its completion event is processed
- Reducers should be deterministic, preferably idempotent, and commutative (order of delta application must not affect the final result) because event delivery order across batches is not guaranteed
- If recording the processed event fails after state has been updated, a replayed event may apply the same delta again; design reducers for occasional double-application (e.g. idempotent or commutative)
- The final reduced state is persisted on `CursorBatch_Job__c.State_JSON__c` and is available to `worker.finish()`
- State reads are lazy — SOQL only runs when the worker calls `getCurrentState()`, so pages that only emit deltas incur zero read overhead
- Serialized state and deltas are validated against the 131,072-character field limit; oversized values are discarded with an error log
- Idempotency tracking (via `CursorBatch_Processed_Event__c`) runs only for stateful jobs; non-stateful jobs have zero overhead
- Processed event records are cleaned up asynchronously via `CursorBatchProcessedEventCleanup` when a stateful job completes

#### Per-Worker Page-to-Page State

Workers processing multi-page ranges can accumulate local state across pages without reading shared state. Override `buildSerializedWorkerState()` to carry serialized state through `ctx.workerState`:

```apex
public class MyAccumulatingWorker extends CursorBatchWorker {
    private Integer recordsProcessedThisWorker = 0;
    
    public override void process(List<SObject> records) {
        // Restore accumulated state from previous page
        if (ctx != null && String.isNotBlank(ctx.workerState)) {
            Map<String, Object> prev = (Map<String, Object>) JSON.deserializeUntyped(ctx.workerState);
            recordsProcessedThisWorker = (Integer) prev.get('count');
        }
        recordsProcessedThisWorker += records.size();
    }
    
    protected override String buildSerializedWorkerState() {
        return JSON.serialize(new Map<String, Object>{ 'count' => recordsProcessedThisWorker });
    }
    
    protected override Object buildStateDelta() {
        // Only flush to shared state on the final page to avoid double-counting
        if (ctx.isFinal) {
            return new Map<String, Object>{ 'processedCount' => recordsProcessedThisWorker };
        }
        return null;
    }
}
```

**Key points:**
- `workerState` is carried across pages and retries via the context, not sent on completion events
- Format and size are the worker's responsibility
- Use this to accumulate per-worker metrics and flush to shared state once on the final page

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

### Convention-Based Logger Discovery

The framework automatically discovers custom loggers without requiring explicit configuration. Both `CursorBatchCoordinator` and `CursorBatchWorker` check for a class named `CursorBatchLoggerAdapter` at runtime.

#### How It Works

```apex
// Automatic resolution in base classes
private static ICursorBatchLogger resolveLogger() {
    try {
        Type adapterType = Type.forName('CursorBatchLoggerAdapter');
        if (adapterType != null) {
            Object instance = adapterType.newInstance();
            if (instance instanceof ICursorBatchLogger) {
                return (ICursorBatchLogger) instance;
            }
        }
    } catch (Exception e) {
        // Class not found or instantiation failed - use default
    }
    return CursorBatchLogger.getDefault();
}
```

#### Setting Up Convention-Based Logging

1. Create a class named `CursorBatchLoggerAdapter` that implements `ICursorBatchLogger` and `Callable`:

```apex
public class CursorBatchLoggerAdapter implements ICursorBatchLogger, Callable {
    
    private static final String LOG_PREFIX = '[CursorBatch] ';
    private Set<String> tags = new Set<String>();
    
    public CursorBatchLoggerAdapter addTag(String tag) {
        if (String.isNotBlank(tag)) { this.tags.add(tag); }
        return this;
    }
    
    public void logInfo(String message) {
        Logger.info(LOG_PREFIX + message);
        applyTags();
        Logger.saveLog();
    }
    
    public void logError(String message) {
        Logger.error(LOG_PREFIX + message);
        applyTags();
        Logger.saveLog();
    }
    
    public void logException(String message, Exception e) {
        Logger.error(LOG_PREFIX + message, e);
        applyTags();
        Logger.saveLog();
    }
    
    // Required: enables the framework to pass Logger_Tag__c from metadata config
    public Object call(String action, Map<String, Object> args) {
        if (action == 'addTag') {
            addTag((String) args.get('tag'));
        }
        return this;
    }
    
    private void applyTags() {
        // Apply tags to log entries per your logging framework
    }
}
```

2. Deploy the class to your org. **That's it!** All coordinators and workers automatically use it.

> **Important:** The `Callable` implementation is required for `Logger_Tag__c` propagation. The framework uses `Callable` to pass tags from metadata config to the adapter without a compile-time dependency. If your adapter doesn't implement `Callable`, logging will work but tags will be silently ignored.

> **Tip:** See `unpackaged/classes/CursorBatchLoggerAdapter.cls` for a complete template.

#### Benefits

- **Zero configuration** — Workers don't need constructors to set up logging
- **Org-wide consistency** — All jobs use the same logger automatically
- **Override when needed** — Call `setLogger()` to use a different logger for specific jobs

#### Simplifying Existing Workers

With convention-based logging, you can remove boilerplate from workers:

**Before (with explicit logger):**

```apex
public class BillingBatchWorker extends CursorBatchWorker {
    
    public BillingBatchWorker() {
        super();
        setLogger(NebulaLoggerAdapterForCursorBatch.getInstance('Billing'));
    }
    
    public override void process(List<SObject> records) {
        // ...
    }
}
```

**After (with convention-based discovery):**

```apex
public class BillingBatchWorker extends CursorBatchWorker {
    
    public override void process(List<SObject> records) {
        Set<Id> dealIds = new Map<Id, SObject>(records).keySet();
        
        IBillingService billingService = (IBillingService) Application.Service.newInstance(IBillingService.class);
        billingService.rebillDeals(dealIds, true);
        logger.logInfo('Rebilled ' + dealIds.size() + ' deals');
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

## Migration Guide

### Migrating from Custom Coordinators to CursorJob

For simple coordinators that just define a query and worker, you can eliminate the coordinator class entirely.

#### Before: Custom Coordinator (~50 lines)

```apex
public class Five9DeleteCoordinator extends CursorBatchCoordinator {
    private static final String JOB_NAME = 'Five9 Delete Batch';
    
    public Five9DeleteCoordinator() {
        super(JOB_NAME);
        setLogger(NebulaLoggerAdapterForCursorBatch.getInstance());
    }
    
    public override String buildQuery() {
        return CampaignMembersSelector.newInstance()
            .buildScheduledDeleteMembersQuery();
    }
    
    public override String getWorkerClassName() {
        return 'Five9DeleteWorker';
    }
}
```

#### After: Metadata-Driven (0 lines)

**Step 1:** Extend your selector interface to include `ICursorBatchQueryBuilder`:

```apex
// ICampaignMembersSelector.cls
public interface ICampaignMembersSelector extends ndr_ISObjectSelector, ICursorBatchQueryBuilder {
    // Existing method signatures...
    String buildScheduledDeleteMembersQuery();
}
```

> **Note:** Only add `ICursorBatchQueryBuilder` to selector interfaces that will be used with CursorJob.

**Step 2:** Add the dispatch method to your selector class:

```apex
// CampaignMembersSelector.cls
public class CampaignMembersSelector extends ndr_SObjectSelector 
    implements ICampaignMembersSelector {
    
    // Required by ICursorBatchQueryBuilder - routes method names to actual methods
    public String buildQuery(String methodName) {
        switch on methodName {
            when 'buildScheduledDeleteMembersQuery' {
                return buildScheduledDeleteMembersQuery();
            }
            when else { 
                return null; 
            }
        }
    }
    
    // Existing query method (no changes needed)
    public String buildScheduledDeleteMembersQuery() {
        return 'SELECT Id FROM CampaignMember WHERE ...';
    }
}
```

**Step 3:** Configure metadata:

| Field | Value |
|-------|-------|
| MasterLabel | `Five9 Delete Batch` |
| Query_Builder_Class__c | `CampaignMembersSelector` |
| Query_Builder_Method__c | `buildScheduledDeleteMembersQuery` |
| Worker_Class__c | `Five9DeleteWorker` |
| Logger_Tag__c | `Five9 Sync` |

**Step 4:** Delete the coordinator class

**Step 5:** Update callers:

```apex
// Old
new Five9DeleteCoordinator().submit();

// New
CursorJob.run('Five9 Delete Batch');
```

### Migrating Complex Coordinators

If your coordinator has conditional chaining logic in `finish()`, move it to the worker:

```apex
public class BillingBatchWorker extends CursorBatchWorker {
    
    public override void finish(CursorBatch_Job__c jobRecord) {
        String jobName = jobRecord.Job_Name__c;
        
        if (jobName == 'Billing Before Advance') {
            CursorJob.run('Submit For Advance Approval');
        } else if (jobName == 'Billing After Advance') {
            if (shouldRunGCS()) {
                CursorJob.run('GCS Debt Set Batch');
            }
        }
    }
}
```

### Sample CursorJob Configurations

```yaml
# Simple job with query builder
MasterLabel: Five9 Delete Batch
Active__c: true
Parallel_Count__c: 50
Page_Size__c: 20
Query_Builder_Class__c: CampaignMembersSelector
Query_Builder_Method__c: buildScheduledDeleteMembersQuery
Worker_Class__c: Five9DeleteWorker
Logger_Tag__c: Five9 Sync

# Job with simple job-name chaining (recommended for most cases)
MasterLabel: Billing Before Advance
Active__c: true
Parallel_Count__c: 25
Page_Size__c: 50
Query_Builder_Class__c: DealsSelector
Query_Builder_Method__c: buildDealsForBillingQuery
Worker_Class__c: BillingBatchWorker
Chain_To_Job__c: Submit For Advance Approval

# Job with class-based chaining (for custom chain logic)
MasterLabel: TAP Transaction Finder
Active__c: true
Parallel_Count__c: 25
Page_Size__c: 50
Query_Builder_Class__c: DealsSelector
Query_Builder_Method__c: buildAllPendingDealsCursorQuery
Worker_Class__c: TAPTransactionFinderWorker
Chain_To_Class__c: TAPTransactionJob
Chain_To_Method__c: run
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

### Job stuck at "Extracting File"

- The CSV middleware has not called back yet — check the middleware logs
- Verify the Named Credential URL and External Credential are configured correctly
- The middleware publishes `CSV_Ready` or `CSV_Error` via Platform Event when indexing completes

### Job shows "Completed with Errors"

- Check `Failed_Workers__c` for count of failed workers
- Review `Error_Message__c` for the first captured error
- Check `Total_Worker_Retries__c` to see if retries were attempted

### Job shows "Cancelled"

- Job was stopped via `CursorBatchCoordinator.killJob(jobRecordId)`
- Workers completed their current page but didn't process additional pages
- The `finish()` callback was not invoked (by design)
- Check `Completed_At__c` to see when the job was cancelled

## Components

### Apex Classes

| Class | Description |
|-------|-------------|
| `CursorJob` | Metadata-driven coordinator that reads configuration from `CursorBatch_Config__mdt` and executes jobs without custom code. `run()` / `runWithDelay()` return the job record `Id` for tracking |
| `CursorBatchCoordinator` | Abstract base for custom coordinators (Queueable, AllowsCallouts). Runs query, creates cursor, publishes Platform Events to fan out workers. `submit()` / `submitWithDelay()` return the job record `Id` |
| `CursorBatchCoordinatorFinalizer` | Queueable finalizer that handles cursor query timeouts with automatic retry logic |
| `CursorBatchCoordinatorTriggerHandler` | Platform Event trigger handler that enqueues coordinator Queueable from submit() |
| `CursorBatchWorker` | Abstract base for workers (Queueable, AllowsCallouts). Processes record batches from cursor positions, supports retry for failed pages. Includes `finish()` virtual method for completion logic |
| `CursorBatchWorkerFinalizer` | Queueable finalizer that handles worker retry and publishes completion events |
| `CursorBatchWorkerTriggerHandler` | Platform Event trigger handler that enqueues Queueable workers from events |
| `CursorBatchRetryException` | Custom exception to explicitly request page retry with optional delay |
| `CursorBatchContext` | Value object encapsulating worker execution parameters including retry state and final page tracking |
| `CursorBatchCompletionHandler` | Handles worker completion events and invokes callbacks (coordinator, worker, or chain class) |
| `CursorBatchSelector` | Centralized selector class for all SOQL queries in the framework |
| `CursorBatchLogger` | Default `System.debug` logger implementation |
| `ICursorBatchLogger` | Interface for custom logging integrations |
| `ICursorBatchQueryBuilder` | Interface for selectors to provide queries for metadata-driven jobs |
| `ICursorBatchMetadataQueryBuilder` | Interface for query builders that receive pre-parsed runtime metadata as `Map<String, Object>` (extends query builder pattern with a second argument) |
| `ICursorBatchStateReducer` | Interface for reducer-managed shared state in `CursorJob` |
| `CursorBatchCounterReducer` | Built-in reducer for additive numeric counters — enables shared state with just a checkbox toggle (`Enable_State_Reducer__c`), no custom reducer class needed |
| `CursorBatchStateManager` | Helper for reducer resolution, serialization, and delta reduction |
| `CursorBatchProcessedEventCleanup` | Queueable that asynchronously deletes `CursorBatch_Processed_Event__c` records for completed stateful jobs using `Database.Cursor`-based pagination |
| `CursorBatchCsvWorker` | Abstract base for CSV file workers. Receives `List<Map<String, Object>>` rows instead of `List<SObject>` — all other features (reducers, retry, chaining) work identically |
| `CursorBatchCsvCallbackCoordinator` | Handles CSV middleware callback — receives row count via Platform Event and triggers worker fan-out |
| `CsvCursorClient` | HTTP client for the CSV middleware (Content Session API v1). Manages session init, status polling, paginated row fetches, and session deletion via Named Credential |

### Custom Objects

| Object | Type | Description |
|--------|------|-------------|
| `CursorBatch_Config__mdt` | Custom Metadata | Job configuration (parallelism, page size, retry settings, CursorJob settings) |
| `CursorBatch_Job__c` | Custom Object | Job tracking (status, worker counts, progress, timing). Includes optional `Job_Parent__c` lookup to the per-config parent record |
| `CursorBatch_Job_Parent__c` | Custom Object | Per-config parent record aggregating all runs of a metadata-defined job. One per `CursorBatch_Config__mdt` (keyed by `Config_Developer_Name__c` external ID). Tracks `Last_Job_Status__c` and `Last_Job_Started_At__c`, exposes a Jobs related list, and supports a customer-managed `Description__c` |
| `CursorBatch_Processed_Event__c` | Custom Object | Idempotency tracking for stateful jobs — stores (Job, ReplayId) pairs to detect replayed Platform Events. Master-Detail to `CursorBatch_Job__c` with cascade delete |
| `CursorBatch_Coordinator__e` | Platform Event | Routes coordinator execution through trigger for cursor user affinity |
| `CursorBatch_Worker__e` | Platform Event | Orchestration events from coordinator to trigger worker enqueueing (includes retry count, metadata JSON) |
| `CursorBatch_WorkerComplete__e` | Platform Event | Worker completion signals for callbacks (includes retry count, Is_Final flag, State_Delta for reducer-managed state) |

### Metadata Fields Added Since v0.10

| Field | Added | Type | Description |
|-------|-------|------|-------------|
| `Query_Builder_Class__c` | v0.11 | Text(255) | Class implementing `ICursorBatchQueryBuilder` |
| `Query_Builder_Method__c` | v0.11 | Text(255) | Method name to call on query builder |
| `Worker_Class__c` | v0.11 | Text(255) | Worker class extending `CursorBatchWorker` |
| `Chain_To_Job__c` | v0.11 | Text(255) | Job name to chain to after completion (simplest option) |
| `Chain_To_Class__c` | v0.11 | Text(255) | Class to chain to after completion (implements `Callable`) |
| `Chain_To_Method__c` | v0.11 | Text(255) | Method to call on chain class (default: `run`) |
| `Logger_Tag__c` | v0.11 | Text(255) | Tag to apply to all log entries |
| `State_Reducer_Class__c` | v0.15 | Text(255) | Class implementing `ICursorBatchStateReducer` for reducer-based shared state |
| `Processing_Type__c` | v0.21 | Text(10) | Data source type: `SOQL` or `CSV` |
| `Enable_State_Reducer__c` | v0.21 | Checkbox | Enables built-in `CursorBatchCounterReducer` without a custom reducer class |

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
