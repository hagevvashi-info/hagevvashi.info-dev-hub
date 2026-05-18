#!/usr/bin/env bash
# Save review results to memory system - safe variable expansion
# Usage: review_to_memory.sh <modified_files_path> <output_file_path>

set -euo pipefail

readonly MODIFIED_FILES_PATH="${1:-}"
readonly OUTPUT_FILE="${2:-}"

# Determine home directory reliably
if [ -z "${HOME:-}" ]; then
  HOME=$(getent passwd "$USER" | cut -d: -f6)
fi

readonly MEMORY_DIR="${HOME}/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory"
readonly MEMORY_FILE="${MEMORY_DIR}/auto_review_pending.md"

# Validate inputs
if [ -z "${OUTPUT_FILE}" ] || [ ! -f "${OUTPUT_FILE}" ]; then
  echo "ERROR: Output file not found: ${OUTPUT_FILE}" >&2
  exit 1
fi

# Create memory directory if not exists
if ! mkdir -p "$MEMORY_DIR"; then
  echo "ERROR: Failed to create memory directory: ${MEMORY_DIR}" >&2
  exit 1
fi

# Read review results (limit to 500 lines to prevent memory bloat)
review_result=$(head -500 "$OUTPUT_FILE" 2>/dev/null || echo "⚠️  Failed to read review output")

# Get timestamp for metadata
timestamp=$(date +%s)
datetime=$(date '+%Y-%m-%d %H:%M:%S')

# Create memory file with safe variable expansion
# Use single-quoted MEMORY_EOF to prevent shell expansion in template
cat > "${MEMORY_FILE}.tmp" << 'MEMORY_EOF'
---
name: auto_review_pending
description: Auto review result pending main agent action
metadata:
  type: project
MEMORY_EOF

# Append dynamic timestamp (safe)
echo "  timestamp: $timestamp" >> "${MEMORY_FILE}.tmp"

# Append static content
cat >> "${MEMORY_FILE}.tmp" << 'MEMORY_EOF'
---

## 自動レビュー結果（実行待ち）

レビュー実行日時: DATETIME_PLACEHOLDER

### レビュー内容

REVIEW_RESULT_PLACEHOLDER

---

**メインエージェントへ：このレビュー結果に基づいて、判断・対応してユーザーに報告してください。**
MEMORY_EOF

# Replace placeholders safely using sed (proper escaping)
sed -i "s|DATETIME_PLACEHOLDER|${datetime}|g" "${MEMORY_FILE}.tmp" || {
  echo "ERROR: Failed to update datetime in memory file" >&2
  rm -f "${MEMORY_FILE}.tmp"
  exit 1
}

# Replace review results safely (handle special characters in sed)
# Escape special characters in review_result for sed
escaped_review=$(printf '%s\n' "$review_result" | sed -e 's/[\/&]/\\&/g')
sed -i "s|REVIEW_RESULT_PLACEHOLDER|${escaped_review}|g" "${MEMORY_FILE}.tmp" || {
  echo "ERROR: Failed to insert review results in memory file" >&2
  rm -f "${MEMORY_FILE}.tmp"
  exit 1
}

# Atomic rename (prevents partial writes)
if ! mv "${MEMORY_FILE}.tmp" "${MEMORY_FILE}"; then
  echo "ERROR: Failed to finalize memory file" >&2
  exit 1
fi

# Verify file was created successfully
if [ ! -s "${MEMORY_FILE}" ]; then
  echo "ERROR: Memory file is empty or was not created" >&2
  exit 1
fi

echo "✅ Review result saved to memory: ${MEMORY_FILE}"
exit 0
