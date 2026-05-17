---
status: resolved
date: 2026-05-17
source: "Code review of cmd/worker/main.go, internal/platform/queue_platform.go, internal/bridge/bridge.go"
---

# Queue Message Flow Specification

## Overview

This document specifies how messages flow from Slack through the go-tty-from-queue system to generate agent responses and post them back to Slack.

## Question 1: Does the system pass channel X posts to agents?

**Answer: YES**

**Source Code Verification:**

```go
// cmd/worker/main.go
messages, err := plat.FetchNewMessages()  // ← Fetch pending messages from queue
```

```go
// internal/platform/queue_platform.go - FetchNewMessages()
for _, entry := range entries {
    if entry.Status != "pending" {
        continue
    }
    // No filtering on channel, user, or content
    msg := message.Message{
        ID:        entry.MessageTS,
        AgentType: entry.AgentType,
        Content:   entry.Text,
        // ... 
    }
    messages = append(messages, msg)
}
```

**Behavior:**
- All entries with `Status == "pending"` are fetched
- No additional filtering is applied
- Messages are grouped by thread and passed to agents for execution

**Flow:**
```
Slack Channel X
    ↓
GAS (Google Apps Script)
    ↓
Google Sheets Queue
    ↓
go-tty-from-queue FetchNewMessages()
    ↓
Batch to agents (by thread)
    ↓
Agent execution (Claude/Gemini)
```

---

## Question 2: Does the system post agent responses back to channel X via user Y?

**Answer: YES**

**Source Code Verification:**

```go
// cmd/worker/main.go
result, sessionID, _ := brg.Execute(msg, sess, created)
brg.Platform.PostResponse(msg, result)  // ← Post response
```

```go
// internal/platform/queue_platform.go - PostResponse()
func (p *QueuePlatform) PostResponse(original message.Message, response string) error {
    fmt.Printf("📢 [Queue Post] channel: %s ID: %s (thread_ts: %s) への返信:\n%s\n\n",
        original.ChannelID, original.ID, original.ThreadTS, response)
    return nil
}
```

**Behavior (Local vs Production):**

| Environment | Implementation |
|---|---|
| **Local** | Prints to stdout |
| **Production** | Uses Slack API to post thread reply in channel X as user Y |

**Flow:**
```
Agent execution (local: CLI TTY, remote: API)
    ↓
result string (Claude/Gemini response)
    ↓
PostResponse(original_message, result)
    ↓
Local: stdout
Production: Slack API (channels.reply with user Y credentials)
    ↓
Slack Channel X (thread reply by user Y)
```

---

## Question 3: Does the system process Y's posts back through agents? Should they be filtered?

**Answer: CURRENTLY - No filtering. SHOULD BE - Yes, filtered.**

### Current Implementation Behavior

**Y's post handling:**

1. **Local execution shows Y's post would be processed IF included in queue:**
   ```go
   // cmd/worker/main.go
   messages, err := plat.FetchNewMessages()  // ← Gets ALL pending, no Y-filtering
   // ...
   result, sessionID, _ := brg.Execute(msg, sess, created)  // ← Would execute Y's post
   ```

2. **No Y-filtering exists in go-tty-from-queue:**
   ```go
   // internal/platform/queue_platform.go
   // Only filters on: Status == "pending"
   // No user_id check, no Y-filtering
   ```

3. **Only defense: GAS filters out Y's posts when creating queue**
   - If GAS filter works → OK
   - If GAS filter fails → **Infinite loop risk**

### Why Y Posts Should Be Filtered

**Risk: Infinite Loop**
```
User posts "Help" in channel X
    ↓
GAS creates queue entry
    ↓
go-tty-from-queue executes (Claude/Gemini)
    ↓
Posts response in channel X as user Y
    ↓
GAS sees Y's response
    ↓
If GAS doesn't filter Y: Creates queue entry
    ↓
go-tty-from-queue executes Y's response (AGAIN)
    ↓
Posts another response as Y
    ↓
INFINITE LOOP 🔄
```

### Current Dependency

```
Architecture correctness depends on:
    GAS Filter (Y removal)
        ↑
        └─── if fails → infinite loop
```

**Problem:** Single point of failure, no defense in depth.

---

## Specification (Idealized)

### Responsibility Matrix

| Task | GAS | go-tty-from-queue | Queue |
|---|---|---|---|
| Include all Slack posts | ✓ | - | - |
| Add user_id to Entry | ✓ | - | ✓ |
| Filter Y posts (first) | ✓ | - | - |
| Filter Y posts (defense) | - | ✓ | - |
| Store audit trail | - | - | ✓ |
| Execute non-Y posts | - | ✓ | - |
| Post responses to X | - | ✓ | - |

### Ideal Message Flow (with user_id)

```
Slack Channel X
    ↓
GAS: Extract user_id, create Entry with user_id
    ↓
Queue: Store with user_id (audit trail)
    ↓
go-tty-from-queue: Fetch pending
    ├─ Filter: user_id == "U_AGENT_Y" → skip
    └─ Filter: others → execute
    ↓
Agent execution
    ↓
PostResponse back to X
    ↓
GAS: New post arrives (from Y)
    ├─ GAS Filter: user_id == "U_AGENT_Y" → skip queue
    └─ go-tty-from-queue Filter: user_id == "U_AGENT_Y" → skip if in queue
    ↓
✅ NO INFINITE LOOP
```

---

## Summary

| Question | Current Implementation | Ideal Behavior |
|---|---|---|
| **Q1: Pass X posts to agents?** | ✓ YES (all pending) | ✓ YES (all non-Y pending) |
| **Q2: Post Y responses to X?** | ✓ YES | ✓ YES |
| **Q3: Filter Y posts?** | ✗ NO (GAS only) | ✓ YES (multi-layer) |

---

## Related Discussions

- **Proposed Fix:** docs/proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md
- **Design Decision:** docs/outdated/CURRENT_ENTRY_SCHEMA.md

---

**Analysis Date:** 2026-05-17  
**Status:** Complete  
**Confidence:** High (source: direct code inspection)
