# Documentation Index

## Status Categories

This documentation is organized by status to help readers understand the state of each design decision and specification.

### Resolved (Analysis Complete)
Completed analyses and specifications that have been verified and serve as reference material.

- **Lock Mechanism Analysis** (`resolved/LOCK_MECHANISM_ANALYSIS.md`)
  - Deep dive into mutex-based queue locking behavior
  - Concurrency safety analysis and edge cases

- **Atomicity & Reliability** (`resolved/ATOMICITY_AND_RELIABILITY.md`)
  - Analysis of at-least-once delivery semantics
  - Entry consumption and acknowledgment model

- **Queue Message Flow Specification** (`resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md`)
  - Detailed specification of message flow through queue
  - Processing stages and state transitions
  - Contract and error handling guarantees

### Proposed (Decision Pending)
Design proposals that require feedback and decision before implementation.

- **Queue Entry Schema Design** (`proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md`)
  - Proposal to add `user_id` field to queue entries
  - Rationale and implementation considerations
  - Impact on existing queue operations

### Outdated (Deprecated/Superseded)
Documentation reflecting earlier understanding or current implementation that is being evolved.

- **Current Entry Schema** (`outdated/CURRENT_ENTRY_SCHEMA.md`)
  - Documents existing queue entry structure
  - To be superseded by proposed schema changes

### Accepted (Consensus Reached)
Decisions that have been reviewed and approved for implementation.

*(To be populated as proposals graduate to accepted status)*

---

## How to Use This Index

1. **For current implementation details**: See **Resolved** section
2. **For pending design decisions**: Review **Proposed** section and provide feedback
3. **For historical context**: Refer to **Outdated** section
4. **For next steps**: Check **Accepted** section for decisions ready for implementation

## Contributing

When adding new documentation:
1. Determine the appropriate status category
2. Create the document in the corresponding subdirectory
3. Update this index with a brief description and link
4. Add the document to the appropriate section above
