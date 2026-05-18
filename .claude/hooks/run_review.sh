#!/usr/bin/env bash
# Review Hook Script - Execute code review agent with safety guardrails
# Usage: run_review.sh <modified_files_path> <output_path>

set -euo pipefail

# Ensure HOME is set for hook execution environment
if [ -z "${HOME:-}" ]; then
  HOME=$(getent passwd "$USER" | cut -d: -f6)
fi

readonly MODIFIED_FILES_PATH="${1:-}"
readonly OUTPUT_PATH="${2:-$(mktemp --suffix=.md)}"
readonly REVIEW_TIMEOUT=30

# Validate inputs
if [ -z "${MODIFIED_FILES_PATH}" ] || [ ! -f "${MODIFIED_FILES_PATH}" ]; then
  echo "ERROR: Modified files path not provided or file not found: ${MODIFIED_FILES_PATH}" >&2
  exit 1
fi

if [ -z "${OUTPUT_PATH}" ]; then
  echo "ERROR: Output path is empty" >&2
  exit 1
fi

# Read modified files into array (safe against special characters)
declare -a FILES_ARRAY
while IFS= read -r line; do
  if [ -n "$line" ] && [ "$line" != "=== Files Modified ===" ]; then
    FILES_ARRAY+=("$line")
  fi
done < "$MODIFIED_FILES_PATH"

# Build files list for display (safe concatenation)
if [ ${#FILES_ARRAY[@]} -eq 0 ]; then
  FILES_DISPLAY="(no files detected)"
else
  FILES_DISPLAY=$(printf '%s\n' "${FILES_ARRAY[@]}" | paste -sd ',' - | sed 's/,/, /g')
fi

# Run review agent with timeout (30 seconds max)
# Capture output, timeout gracefully
REVIEW_OUTPUT=""
if ! REVIEW_OUTPUT=$(timeout $REVIEW_TIMEOUT claude --agent review --print "Code review for: ${FILES_DISPLAY}. Provide detailed analysis of code quality, bugs, improvements." 2>&1); then
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 124 ]; then
    REVIEW_OUTPUT="⚠️  Review execution timed out (${REVIEW_TIMEOUT}s). Review may be incomplete."
  else
    REVIEW_OUTPUT="⚠️  Review execution failed with exit code ${EXIT_CODE}."
  fi
fi

# Validate review output is not empty
if [ -z "${REVIEW_OUTPUT}" ]; then
  REVIEW_OUTPUT="⚠️  Review output is empty. Agent may have failed silently."
fi

# Write review output to file with error handling
if ! echo "${REVIEW_OUTPUT}" > "${OUTPUT_PATH}"; then
  echo "ERROR: Failed to write review output to ${OUTPUT_PATH}" >&2
  exit 1
fi

# Verify file was written
if [ ! -s "${OUTPUT_PATH}" ]; then
  echo "ERROR: Output file is empty or was not created: ${OUTPUT_PATH}" >&2
  exit 1
fi

# Report success
OUTPUT_SIZE=$(wc -c < "${OUTPUT_PATH}") || {
  echo "ERROR: Failed to get output file size" >&2
  exit 1
}

echo "✅ Review completed: ${OUTPUT_PATH} (${OUTPUT_SIZE} bytes)"
exit 0
