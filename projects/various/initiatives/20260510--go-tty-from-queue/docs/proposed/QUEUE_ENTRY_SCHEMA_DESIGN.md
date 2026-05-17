---
status: proposed
date: 2026-05-17
author: Architecture Review (Main Branch Protection incident)
---

# Improved Queue Entry Schema with User ID

## Proposal

Add `user_id` field to `Entry` struct to enable:
1. Y-post filtering on go-tty-from-queue side (defense in depth)
2. Complete audit trail (who posted what)
3. Future extensibility (bot filtering, duplicate detection, etc.)

## Proposed Schema

```go
type Entry struct {
    Channel   string `json:"channel"`      // Slack channel ID
    ThreadTS  string `json:"thread_ts"`    // Thread root timestamp
    MessageTS string `json:"message_ts"`   // Message timestamp
    Text      string `json:"text"`         // Post content
    Time      string `json:"time"`         // ISO 8601 format
    Status    string `json:"status"`       // "pending", "processing", "completed", "failed"
    AgentType string `json:"agent_type"`   // "claude" or "gemini"
    UserID    string `json:"user_id"`      // ← NEW: Slack user ID (e.g., "U123456")
}
```

## Rationale

### 1. Defense in Depth

**Before (single point of failure):**
```
GAS removes Y → Queue created → go-tty-from-queue processes all
↑ If GAS fails → infinite loop
```

**After (multiple defense layers):**
```
GAS removes Y → Queue created → go-tty-from-queue filters Y → Safe
      ↑ First line of defense
                                    ↑ Final defense (can't fail)
```

### 2. Data Completeness

With `user_id`, queue becomes an audit trail:
- "User U12345 posted 'Help' in #channel-X at 2026-05-17T10:00:00Z"
- Enables debugging: "Where did this message come from?"
- Enables compliance: "Who did what and when?"

### 3. Architectural Clarity

| Responsibility | Component |
|---|---|
| Provide complete message data to queue | GAS |
| Filter by Y | GAS (first defense) + go-tty-from-queue (final defense) |
| Process valid messages | go-tty-from-queue |
| Store audit trail | Queue (via user_id) |

Each component has clear, single responsibility.

### 4. Future Extensibility

Once `user_id` is present, easily add filtering rules:

```go
func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
    entries, err := p.source.Read()
    
    var messages []message.Message
    for _, entry := range entries {
        if entry.Status != "pending" {
            continue
        }
        
        // Filter Y posts
        if entry.UserID == "U_AGENT_Y" {
            continue
        }
        
        // Filter bots (extensible)
        if strings.HasPrefix(entry.UserID, "B_") {
            continue
        }
        
        // ... process valid message
    }
    return messages, nil
}
```

## Implementation Impact

### GAS Changes

```javascript
// Before
const entry = {
    channel: event.channel,
    thread_ts: event.thread_ts,
    message_ts: event.ts,
    text: event.text,
    time: new Date().toISOString(),
    status: "pending",
    agent_type: "claude"
};

// After
const entry = {
    channel: event.channel,
    thread_ts: event.thread_ts,
    message_ts: event.ts,
    text: event.text,
    time: new Date().toISOString(),
    status: "pending",
    agent_type: "claude",
    user_id: event.user  // ← Add this
};
```

### go-tty-from-queue Changes

```go
// internal/queue/entry.go
type Entry struct {
    // ... existing fields
    UserID string `json:"user_id"`  // ← Add this
}

// internal/platform/queue_platform.go
func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
    // ... existing code
    
    for _, entry := range entries {
        if entry.Status != "pending" {
            continue
        }
        
        // ← Add defensive filter
        if entry.UserID == "U_AGENT_Y" {
            continue
        }
        
        // ... convert to Message
    }
    
    return messages, nil
}
```

## Risk Assessment

### Minimal Risk
- Adding optional field to Entry struct (backward compatible with JSON)
- GAS already has access to `event.user`
- No breaking changes to existing interfaces
- Pure addition (no deletion of fields)

### Migration Path
1. Deploy go-tty-from-queue with Y-filtering code (even if user_id is empty)
2. Update GAS to include user_id in new queue entries
3. Old queue entries without user_id: go-tty-from-queue treats as non-Y
4. After GAS rollout, all entries have user_id

## Decision Required

| Aspect | Decision |
|--------|----------|
| Add user_id to Entry? | YES / NO |
| Add Y-filtering to go-tty-from-queue? | YES / NO |
| Timeline for GAS update? | TBD |

---

## Related Issues

- **Current Bug:** GAS-only filtering leaves go-tty-from-queue defenseless
- **Related Decision:** docs/resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md - System-wide Y-post handling

---

**Created:** 2026-05-17  
**Status:** Awaiting acceptance  
**Priority:** High (affects system correctness)
