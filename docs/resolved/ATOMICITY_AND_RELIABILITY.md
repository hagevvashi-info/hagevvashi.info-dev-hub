# Atomicity & Reliability Analysis

## Status

**RESOLVED** — Analysis complete and verified through testing and code review.

## Overview

This document analyzes the atomicity guarantees and reliability model of the go-tty-from-queue system, focusing on entry consistency and delivery semantics.

## Delivery Semantics: At-Least-Once

The queue implements **at-least-once delivery**:

### Guarantee
Every entry that is successfully enqueued (via `Put()`) will be processed **at least once** by a consumer (via `Next()` + `Ack()`).

### Model
```
Producer              Queue               Consumer
   │                    │                    │
   ├──→ Put(entry) ────→│                    │
   │                    │                    │
   │                    │← Next() ──────────→│ Agent retrieves
   │                    │                    │
   │                    │ ← Ack() ────────→ │ Agent completes
   │                    │                    │
   │       (if no Ack)  │                    │
   │       Re-delivery  │← Next() ──────────→│ Retry
   │                    │
```

### Implications

1. **Exactly-once not guaranteed**: If consumer crashes after processing but before Ack(), entry will be re-delivered.
2. **Consumer must be idempotent**: Processing the same entry twice should be safe.
3. **Acknowledgment is critical**: Ack() is the only way to mark an entry as fully processed.

## Atomicity Guarantees by Operation

### Put() Atomicity

**Operation**: Enqueue a new entry

**Atomic Actions**:
1. Append entry to the entries slice
2. Increment version counter
3. (Timestamp CreatedAt is set before Put() is called)

**Lock**: Held for both actions (mutex protects slice + version)

**Guarantee**: Entry is atomically visible to all consumers after Put() returns.

**Property**: Serializable — Put() calls are totally ordered by mutex lock acquisition.

### Next() Atomicity

**Operation**: Retrieve and reserve the next unacknowledged entry

**Atomic Actions**:
1. Scan entries for first unacknowledged
2. Increment retrieval count for that entry
3. Return entry to caller

**Lock**: Held for all actions

**Guarantee**: 
- Retrieval count is atomically incremented
- Entry state transitions from unacknowledged → reserved
- Concurrent Next() calls will not return the same entry with retrieval count = 1

**Property**: Multiple consumers can retrieve the same entry (retrieval count > 1) if consumer crashes, but lock prevents torn reads/writes.

### Ack() Atomicity

**Operation**: Mark an entry as acknowledged (processing complete)

**Atomic Actions**:
1. Find entry by SessionID
2. Verify not already acknowledged
3. Set AcknowledgedAt timestamp
4. Update entry status

**Lock**: Held for all actions

**Guarantee**:
- AcknowledgedAt timestamp is atomically set
- Idempotent: second Ack() on same entry fails (already acknowledged)
- Entry state transitions from reserved → acknowledged

**Property**: Ack() is safe to call multiple times; error on second attempt prevents double-acknowledgment.

## State Transition Diagram

```
┌──────────────────────────────────────────────────────────┐
│  Entry Lifecycle                                         │
└──────────────────────────────────────────────────────────┘

    ┌──────────────┐
    │  Enqueued    │  Put() was successful
    │              │  Retrieval count = 0
    └───────┬──────┘
            │
         Next()
            │
    ┌───────▼──────┐
    │  Retrieved   │  Next() incremented retrieval count
    │              │  Agent is processing
    │ Retrieval: 1 │
    └───────┬──────┘
            │
        Ack() or crash
            │
    ╔═══════╩═══════╗
    ║               ║
 Ack() OK      Agent crashes
    ║               ║
┌───▼────┐      ┌────▼────┐
│ Acked  │      │ Pending  │
│        │      │ (re-ack) │
│ Final  │      │          │  Next() returns again
└────────┘      └────┬─────┘
                     │
                  Next()
                     │
                ┌────▼────┐
                │Retrieved │  Retrieval count = 2
                │ (2nd)    │
                └────┬─────┘
                     │
                  Ack()
                     │
                ┌────▼────┐
                │ Acked   │
                │ (final) │
                └─────────┘
```

## Entry Consistency

### Initial State After Put()
```
Entry {
    SessionID: "xyz",
    CreatedAt: now,
    AcknowledgedAt: nil,        // Not acknowledged
    RetrievalCount: 0
}
```

### After First Next()
```
Entry {
    SessionID: "xyz",
    CreatedAt: now,
    AcknowledgedAt: nil,        // Still not acknowledged
    RetrievalCount: 1           // Incremented
}
```

### After Ack()
```
Entry {
    SessionID: "xyz",
    CreatedAt: now,
    AcknowledgedAt: <timestamp>,  // Now acknowledged
    RetrievalCount: 1
}
```

### Invariant Check
- `RetrievalCount >= 1` if `AcknowledgedAt != nil` (entry was retrieved before acknowledgment)
- `RetrievalCount >= 1` if entry was ever returned by Next()
- `AcknowledgedAt` is set only once (atomically)

## Failure Scenarios

### Scenario 1: Consumer Crashes After Next() But Before Ack()

**Initial**: Entry acknowledged by agent, but agent crashes mid-processing.

**Behavior**:
1. Entry remains in queue with `AcknowledgedAt = nil`
2. RetrievalCount = 1
3. Next Next() call returns the same entry again (RetrievalCount = 2)
4. New agent processes and calls Ack()

**Atomicity**: ✅ Maintained — entry is re-delivered without loss.

**Reliability**: ✅ Entry is not lost; at-least-once guaranteed.

### Scenario 2: Consumer Crashes After Ack()

**Initial**: Entry acknowledged, then agent crashes.

**Behavior**:
1. Entry marked with `AcknowledgedAt = <timestamp>`
2. Next Next() call returns the next unacknowledged entry (skips this one)
3. Entry remains in queue but is not re-delivered (no agent will call Next() for it)

**Atomicity**: ✅ Maintained — Ack() is durable.

**Reliability**: ✅ Entry is marked complete; no duplicate processing.

### Scenario 3: Queue Service Crashes

**Behavior**:
1. All in-memory state is lost
2. Entries currently being processed are lost
3. At-least-once semantics are **NOT** preserved across service restarts

**Mitigation**: Consider persistent storage (e.g., database, file-backed queue) for production systems requiring durability.

## Anomaly: Double-Ack

**Scenario**: Consumer calls Ack() twice on the same entry.

**Behavior**:
1. First Ack(): Finds entry, checks AcknowledgedAt (nil), sets AcknowledgedAt, returns success
2. Second Ack(): Finds entry, checks AcknowledgedAt (not nil), returns error "already acknowledged"

**Atomicity**: ✅ Maintained — error prevents double-acknowledgment.

**Safety**: ✅ Idempotent contract enforced; no duplicate completion markers.

## Performance Implications

### Best Case
- Queue has few unacknowledged entries
- Next() scans quickly
- Lock contention is low

### Worst Case
- Queue accumulates unacknowledged entries
- Next() must scan entire list (O(n))
- Lock contention increases with queue age
- Performance degrades over time

### Recommendation
- Monitor queue length and retrieval latency
- Implement automatic cleanup of acknowledged entries (if needed)
- Consider indexing strategy for large queues

## Conclusion

The go-tty-from-queue queue provides **correct at-least-once delivery semantics** with atomic state transitions under the mutex lock. However, **durability across service restarts is not guaranteed** (in-memory only).

### Strengths
- ✅ Atomic operations prevent partial state updates
- ✅ Idempotent Ack() prevents double-processing
- ✅ At-least-once guarantees ensure no entry loss (during service lifetime)
- ✅ Mutex lock eliminates race conditions

### Limitations
- ❌ Not durable across service crashes
- ❌ Performance scales poorly with queue age
- ❌ Exactly-once not supported
- ❌ No persistent storage

### Suitable For
- Short-lived sessions
- Low-throughput command queues
- Single-instance deployments
- Non-critical workloads

### Not Suitable For
- Mission-critical systems requiring durability
- High-throughput scenarios with many concurrent consumers
- Distributed multi-instance deployments
