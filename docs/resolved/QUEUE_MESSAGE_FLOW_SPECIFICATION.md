# Queue Message Flow Specification

## Overview

This document specifies the complete message flow through the go-tty-from-queue system, from entry submission to final acknowledgment.

## Entry Lifecycle States

```
┌─────────────────┐
│   Enqueued      │  Entry received and stored in queue
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Processing     │  Agent retrieved entry via Next()
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Acknowledging  │  Agent calls Ack() to confirm completion
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Acknowledged   │  Entry marked complete, ready for removal
└─────────────────┘
```

## Message Flow Details

### 1. Enqueue Phase

**Participant**: Client / Producer
**Operation**: `Put(entry Entry) error`

```
Client → Queue.Put(entry)
         ├─ Lock acquisition (mutex)
         ├─ Append to entries list
         ├─ Increment version counter
         └─ Lock release
         └─ Return nil (on success) or error
```

**Guarantees**:
- Entry is atomically added to the queue
- Order is preserved (FIFO)
- Version counter is incremented exactly once per entry

### 2. Retrieval Phase

**Participant**: Agent / Consumer
**Operation**: `Next() (Entry, error)`

```
Agent → Queue.Next()
        ├─ Lock acquisition (mutex)
        ├─ Search for first unacknowledged entry
        │   ├─ If found: remember its index
        │   └─ If not found: return nil, error
        ├─ Increment retrieval counter for entry
        ├─ Lock release
        └─ Return entry to caller
```

**Guarantees**:
- Returns entries in FIFO order
- Each call returns distinct entry or nil
- Retrieval counter prevents duplicate processing

### 3. Acknowledgment Phase

**Participant**: Agent / Consumer
**Operation**: `Ack(sessionID) error`

```
Agent → Queue.Ack(sessionID)
        ├─ Lock acquisition (mutex)
        ├─ Find entry by session ID
        │   ├─ If not found: return error
        │   ├─ Verify not already acknowledged
        │   └─ If acknowledged: return error
        ├─ Mark entry as acknowledged
        ├─ Lock release
        └─ Return nil (on success) or error
```

**Guarantees**:
- Acknowledgment is idempotent for first call
- Duplicate acknowledgment is rejected
- Entry status is atomically updated

## Error Handling Contract

### Put() Errors
- **Invalid Entry**: Entry validation fails (e.g., missing required fields)
- **Queue Full**: Queue capacity exceeded (if applicable)
- **System Error**: Unexpected internal state error

### Next() Errors
- **No Entries**: Queue is empty or all entries acknowledged
- **Concurrent Access Error**: Lock acquisition timeout (if applicable)

### Ack() Errors
- **Session Not Found**: Entry with given session ID not in queue
- **Already Acknowledged**: Entry already marked as acknowledged
- **Not Retrieved**: Attempted to acknowledge unretrieved entry

## Concurrency Model

All operations are protected by a single reader-writer lock:
- **Multiple readers** (simultaneous `Next()` calls): Not explicitly supported; use process synchronization
- **Exclusive writer**: Ensured by mutex lock during `Put()`, `Ack()`
- **Lock scope**: Minimal; held only during data structure modification

## Delivery Semantics

This queue implements **at-least-once delivery**:

1. Entry submitted with `Put()`
2. Agent calls `Next()` to retrieve
3. Agent processes entry and calls `Ack()`
4. Entry remains in queue until explicit cleanup

**Implication**: If an agent crashes after `Next()` but before `Ack()`, the entry will be re-delivered to the next agent calling `Next()`.

## Version Management

A version counter increments with each `Put()` operation. This provides:
- Detection of queue modifications during iteration
- Validation of entry validity
- Ordering information for entries

## Conclusion

This specification establishes the contract between producers and consumers. Adherence to this flow ensures reliable message delivery and proper acknowledgment tracking.
