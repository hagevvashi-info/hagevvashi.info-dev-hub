---
status: outdated
date: 2026-05-17
reason: "Missing user_id field for Y-post filtering and audit trail"
---

# Current Queue Entry Schema (Outdated)

## Definition

```go
type Entry struct {
    Channel   string `json:"channel"`      // Slack channel ID
    ThreadTS  string `json:"thread_ts"`    // Thread root timestamp
    MessageTS string `json:"message_ts"`   // Message timestamp
    Text      string `json:"text"`         // Post content
    Time      string `json:"time"`         // ISO 8601 format
    Status    string `json:"status"`       // "pending", "processing", "completed", "failed"
    AgentType string `json:"agent_type"`   // "claude" or "gemini"
}
```

## Issues with Current Schema

### 1. Missing User Information

**Problem:** No user_id field means:
- go-tty-from-queue cannot identify Y's posts
- Audit trail is incomplete (cannot see who posted what)
- Cannot implement defensive filtering on go-tty-from-queue side

**Current Workaround:**
- GAS filters out Y posts when creating queue
- If GAS filter fails, infinite loop risk

### 2. Responsibility Ambiguity

| Component | Responsibility |
|-----------|---|
| GAS | Remove Y posts from queue |
| go-tty-from-queue | Process all pending messages |

**Problem:** No defense in depth. GAS failure = infinite loop.

### 3. Limited Future Extensibility

Cannot easily implement rules like:
- Filter bot posts
- Filter admin manual posts
- Filter duplicate posts
- Audit "who said what"

## Historical Context

- Created as minimal schema to reduce data transfer
- GAS was trusted to filter correctly
- No multi-level defense planned

## Superseded By

See `proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md` for the improved design.

---

**Created:** 2026-05-16  
**Marked Outdated:** 2026-05-17  
**Reason:** Identified design gaps requiring schema enhancement
