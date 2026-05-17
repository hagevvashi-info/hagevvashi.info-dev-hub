# Documentation Index

## Overview

This directory contains design documents, architectural analyses, and decision records for the go-tty-from-queue project, organized by status.

---

## 📋 Document Categories

### ✅ Resolved
Completed analyses and decisions. These define the current system state.

- **[QUEUE_MESSAGE_FLOW_SPECIFICATION.md](./resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md)**
  - Specification of how messages flow from Slack → agents → back to Slack
  - Answers: Does Y's posts get processed? (Currently: GAS-only filtering, risky)
  - Status: Identifies design issue requiring user_id addition

- **[LOCK_RESPONSIBILITY_ANALYSIS.md](./resolved/LOCK_RESPONSIBILITY_ANALYSIS.md)**
  - Analysis of lock ownership and responsibility in session management
  - Confirms: Safe/Unsafe methods correctly implement lock semantics
  - Status: Design is sound, no changes needed

- **[ATOMICITY_AND_LOCK_OWNERSHIP.md](./resolved/ATOMICITY_AND_LOCK_OWNERSHIP.md)**
  - Deep dive into atomicity granularity and design tradeoffs
  - Explains: Why separate Lock/Unlock calls are intentional (minimize lock duration)
  - Status: Design rationale documented

- **[API_DESIGN_COMPLEXITY_ANALYSIS.md](./resolved/API_DESIGN_COMPLEXITY_ANALYSIS.md)**
  - Analysis of Manager interface complexity (Safe/Unsafe methods)
  - Trade-off: Simplicity vs Performance vs Control
  - Status: Complexity justified by performance gains

- **[COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md](./resolved/COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md)**
  - Measures complexity increase from hidden locks → explicit locks
  - Quantifies: 10x learning time cost, but justified by safety
  - Status: Trade-off accepted

---

### 🔄 Proposed
Design proposals under review. These suggest improvements or changes.

- **[QUEUE_ENTRY_SCHEMA_DESIGN.md](./proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md)**
  - **Proposal:** Add `user_id` field to Queue Entry struct
  - **Rationale:** Enable Y-filtering on go-tty-from-queue side (defense in depth)
  - **Impact:** GAS + go-tty-from-queue changes needed
  - **Status:** Awaiting acceptance
  - **Priority:** HIGH (fixes infinite loop risk)

---

### ⏳ Outdated
Documents describing deprecated or problematic designs. Kept for historical context.

- **[CURRENT_ENTRY_SCHEMA.md](./outdated/CURRENT_ENTRY_SCHEMA.md)**
  - Documents: Current Entry struct (missing user_id)
  - Issues: No user identification, single-point-of-failure filtering
  - Marked Outdated: 2026-05-17 (identified design gaps)
  - See: QUEUE_ENTRY_SCHEMA_DESIGN.md for improvement

---

### 📌 Accepted
Decisions that have been approved and are ready for implementation.

(Currently empty - awaiting acceptance of proposed changes)

---

## 🎯 Quick Navigation

### By Topic

**Session Management & Locks**
- Start with: [LOCK_RESPONSIBILITY_ANALYSIS.md](./resolved/LOCK_RESPONSIBILITY_ANALYSIS.md)
- Then: [ATOMICITY_AND_LOCK_OWNERSHIP.md](./resolved/ATOMICITY_AND_LOCK_OWNERSHIP.md)
- Deep dive: [API_DESIGN_COMPLEXITY_ANALYSIS.md](./resolved/API_DESIGN_COMPLEXITY_ANALYSIS.md)

**Message Flow & Architecture**
- Start with: [QUEUE_MESSAGE_FLOW_SPECIFICATION.md](./resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md)
- Proposed fix: [QUEUE_ENTRY_SCHEMA_DESIGN.md](./proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md)
- Outdated: [CURRENT_ENTRY_SCHEMA.md](./outdated/CURRENT_ENTRY_SCHEMA.md)

**Complexity & Maintainability**
- Overview: [COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md](./resolved/COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md)
- API details: [API_DESIGN_COMPLEXITY_ANALYSIS.md](./resolved/API_DESIGN_COMPLEXITY_ANALYSIS.md)

---

## 📊 Decision Status Summary

| Topic | Status | Action Required |
|---|---|---|
| Lock semantics | ✅ Resolved | None (design sound) |
| Session atomicity | ✅ Resolved | None (intentional design) |
| API complexity | ✅ Resolved | Document in README ✓ |
| Queue message flow | ✅ Resolved | Address Y-filtering risk |
| **Queue schema (user_id)** | 🔄 **PROPOSED** | **NEEDS DECISION** |

---

## 🔗 Related Information

- **Source Code:** internal/ directory structure corresponds to package boundaries
- **README:** [../../README.md](../../README.md) - Project overview and usage
- **Git History:** Review commits for implementation decisions

---

## 📝 Document Maintenance

- **Last Updated:** 2026-05-17
- **Review Cycle:** Before each major change
- **Owner:** Architecture review team
- **Update Process:** Add new docs to appropriate category (proposed/resolved/outdated/accepted)

---

## Questions?

Refer to specific documents for:
- **How does locking work?** → LOCK_RESPONSIBILITY_ANALYSIS.md
- **Why are methods Safe/Unsafe?** → API_DESIGN_COMPLEXITY_ANALYSIS.md
- **Does the system loop with Y posts?** → QUEUE_MESSAGE_FLOW_SPECIFICATION.md
- **How do we fix it?** → QUEUE_ENTRY_SCHEMA_DESIGN.md
