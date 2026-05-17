# Queue Entry Schema Design Proposal

## Status

**PROPOSED** — Awaiting decision and review before implementation

## Motivation

The current `Entry` schema in the queue lacks user/session context beyond the session ID. This proposal adds explicit `user_id` field to enable better traceability, audit trails, and fine-grained access control.

## Current Schema

```go
type Entry struct {
    SessionID   string    // Unique session identifier
    Command     string    // Command to execute
    Arguments   []string  // Command arguments
    Environment map[string]string // Environment variables
    CreatedAt   time.Time // Creation timestamp
    AcknowledgedAt *time.Time // Acknowledgment timestamp
}
```

## Proposed Schema

```go
type Entry struct {
    SessionID       string              // Unique session identifier
    UserID          string              // New: User who created this entry
    Command         string              // Command to execute
    Arguments       []string            // Command arguments
    Environment     map[string]string   // Environment variables
    CreatedAt       time.Time           // Creation timestamp
    CreatedBy       string              // User who created (may differ from UserID in delegation scenarios)
    AcknowledgedAt  *time.Time          // Acknowledgment timestamp
    AcknowledgedBy  *string             // New: User who acknowledged (optional)
}
```

## Key Changes

### Addition of `user_id` Field
- **Type**: `string`
- **Required**: `true`
- **Semantics**: Identifies the user whose context the command executes under
- **Default**: Extracted from authenticated session context during `Put()`

### Addition of `created_by` Field
- **Type**: `string`
- **Required**: `true`
- **Semantics**: Identifies the user who submitted the entry (audit trail)
- **Use Case**: Distinguishes between user-submitted vs. delegated submissions

### Addition of `acknowledged_by` Field
- **Type**: `*string` (optional pointer)
- **Required**: `false`
- **Semantics**: Identifies the agent/user who acknowledged the entry
- **Use Case**: Complete audit trail from creation to completion

## Implementation Considerations

### Backward Compatibility
- **Old entries**: Will lack `user_id`, `created_by`, `acknowledged_by` fields
- **Migration strategy**: 
  - Add optional fields with zero-value defaults
  - Implement version or schema tag for detection
  - Provide migration utility for existing queue data

### Client Changes Required
- **Put() call site**: Must provide `UserID` and `CreatedBy`
  - Can extract from authentication context
  - Provide sensible defaults for unauthenticated scenarios
- **Ack() call site**: Should populate `AcknowledgedBy` if available

### Storage Impact
- **Memory**: +2 strings per entry (~64 bytes per entry in typical cases)
- **Serialization**: Minimal overhead; fields serialize to standard JSON/protobuf

### Query/Filtering Impact
- Enables new queries:
  - "Show all entries for user X"
  - "Show all entries acknowledged by agent Y"
  - "Audit trail for entry Z"

## Trade-offs

| Aspect | Benefit | Cost |
|--------|---------|------|
| **Traceability** | Complete audit trail from creation to ack | Slight memory overhead per entry |
| **Access Control** | Enable per-user command filtering | Requires auth context at Put time |
| **Compatibility** | Optional fields allow gradual migration | Need version/schema detection logic |
| **Implementation Complexity** | Simple field additions | Migration tooling required |

## Decision Criteria

This proposal requires positive feedback on:
1. Do we need user-level traceability in the queue?
2. Is the field naming (`user_id` vs. `user_context` vs. `principal_id`) appropriate?
3. Should `acknowledged_by` be required or optional?
4. What is the acceptable migration path for existing data?

## Next Steps

1. **Review**: Gather feedback from team on proposed schema
2. **Decide**: Determine if changes should proceed
3. **Design Migration**: If approved, design backward-compatibility approach
4. **Implement**: Add schema changes to Entry struct and validation
5. **Test**: Write tests for new fields and backward-compatibility scenarios

## References

- Current Entry schema: `agent.go:Entry`
- Queue implementation: `queue.go`
- Usage examples: integration tests
