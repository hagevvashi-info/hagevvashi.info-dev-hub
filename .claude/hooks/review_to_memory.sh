#!/bin/bash
set -euo pipefail

modified_files="$1"
output_file="$2"

# Review results
review_result=$(cat "$output_file" 2>/dev/null | head -300 || echo "Review generation in progress")

# Save to memory for main agent to pick up
memory_dir="${HOME}/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory"
mkdir -p "$memory_dir"

cat > "$memory_dir/auto_review_pending.md" << MEMORY_EOF
---
name: auto_review_pending
description: Auto review result pending main agent action
metadata:
  type: project
  timestamp: $(date +%s)
---

## 自動レビュー結果（実行待ち）

レビュー実行日時: $(date '+%Y-%m-%d %H:%M:%S')

### レビュー内容

$review_result

---

**メインエージェントへ：このレビュー結果に基づいて、判断・対応してユーザーに報告してください。**

MEMORY_EOF

echo "✅ Review result saved to memory"
