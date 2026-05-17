#!/usr/bin/env bash
# Prevents dangerous git operations per .claude/rules/002_git_guidelines.md
set -euo pipefail

# Get script directory in POSIX-compliant way
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Extract command from JSON input using jq
cmd=$(cat 2>/dev/null | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# POSIX-compliant empty check
[ -z "$cmd" ] && exit 0

current_branch=$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# RULE 1: Block push to upstream remote
if echo "$cmd" | grep -E '^\s*git push\s+upstream'; then
  cat >&2 << 'MSG'
❌ Cannot push to upstream - use fork workflow
Push to origin, then create PR to upstream
MSG
  exit 2
fi

# RULE 2: Block push from main branch (any destination)
if echo "$cmd" | grep -E '^\s*git push' && [ "$current_branch" = "main" ]; then
  cat >&2 << 'MSG'
❌ Cannot push from main branch
Create feature branch: git switch -c <name>
MSG
  exit 2
fi

# RULE 3: Block commit to main branch
if echo "$cmd" | grep -E '^\s*git commit' && [ "$current_branch" = "main" ]; then
  cat >&2 << 'MSG'
❌ Cannot commit to main branch
Create feature branch: git switch -c <name>
MSG
  exit 2
fi

exit 0
