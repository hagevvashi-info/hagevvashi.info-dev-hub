#!/usr/bin/env bash
# Orchestrate automatic code review workflow
# This script coordinates: git diff → run_review → save to memory
# Set -euo pipefail for safety: error on undefined var, pipe fail, unset var

set -euo pipefail

# Calculate repo root from script location (resilient to environment)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly HOOKS_DIR="$REPO_ROOT/.claude/hooks"

# Create temp files for modified files list and review output
modified_files=$(mktemp --suffix=.txt)
output_file=$(mktemp --suffix=.md)

# Cleanup on exit
trap "rm -f '$modified_files' '$output_file'" EXIT

# Step 1: Get modified files from git diff
echo "=== Files Modified ===" > "$modified_files"
git diff --name-only 2>/dev/null >> "$modified_files" || echo "No changes" >> "$modified_files"

if grep -q "^[^=]" "$modified_files" 2>/dev/null; then
  # Step 2: Run review agent and capture output
  if ! bash "$HOOKS_DIR/run_review.sh" "$modified_files" "$output_file" 2>&1; then
    echo "⚠️  Review execution failed. Continuing without review results."
    # Create empty output file so review_to_memory doesn't fail
    touch "$output_file"
  fi

  # Step 3: Save review results to memory
  if ! bash "$HOOKS_DIR/review_to_memory.sh" "$modified_files" "$output_file" 2>&1; then
    echo "⚠️  Failed to save review to memory."
  fi
else
  echo "No files modified. Skipping review."
fi

exit 0
