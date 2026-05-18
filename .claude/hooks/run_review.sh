#!/usr/bin/env bash
# Review Hook Script
# Usage: run_review.sh <modified_files_path> <output_path>

set -euo pipefail

MODIFIED_FILES_PATH="${1:-}"
OUTPUT_PATH="${2:-$(mktemp --suffix=.md)}"

if [ -z "${MODIFIED_FILES_PATH}" ] || [ ! -f "${MODIFIED_FILES_PATH}" ]; then
  echo "Modified files path not provided or file not found"
  exit 1
fi

# Read modified files (skip header)
MODIFIED_FILES=$(tail -n +2 "${MODIFIED_FILES_PATH}" 2>/dev/null | tr '\n' ' ')

if [ -z "${MODIFIED_FILES}" ]; then
  MODIFIED_FILES="(no files detected)"
fi

# Output path to be available for review agent
export REVIEW_OUTPUT_PATH="${OUTPUT_PATH}"

# Invoke review agent via claude CLI with file paths
# The agent prompt receives the modified files list and output path
export MODIFIED_FILES
export REVIEW_OUTPUT_PATH

# Run review agent and capture output
REVIEW_OUTPUT=$(claude --agent review --print "Code review for: ${MODIFIED_FILES}. Provide detailed analysis of code quality, bugs, improvements." 2>&1)

# Write captured output to file
echo "${REVIEW_OUTPUT}" > "${OUTPUT_PATH}"

# Confirm
echo "Review saved to: ${OUTPUT_PATH} ($(wc -c < "${OUTPUT_PATH}") bytes)"

exit 0
