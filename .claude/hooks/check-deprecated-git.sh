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

# RULE 4: Require git-expert for write operations (delegation enforcement)
# Allow read-only operations
if echo "$cmd" | grep -E '^\s*git (status|log|diff|show|remote|branch -v)'; then
  exit 0
fi

# Allow write operations if GIT_EXPERT_OPERATION is explicitly set in hook environment
if [ "${GIT_EXPERT_OPERATION:-}" = "1" ]; then
  exit 0
fi

# Check if this is a chained command with export (e.g., "export GIT_EXPERT_OPERATION=1 && git commit...")
# This allows users to explicitly authorize the operation in the same shell session
if echo "$cmd" | grep -E 'export\s+GIT_EXPERT_OPERATION\s*=\s*1\s*&&\s*git'; then
  exit 0
fi

# Block all other git operations - require git-expert delegation
if echo "$cmd" | grep -E '^\s*git (commit|push|switch|restore|rebase|merge|reset|revert|tag|stash)'; then
  cat >&2 << 'MSG'
❌ Direct git operation not allowed - Use git-expert agent instead

This git operation requires:
  - Commit message crafting
  - Test execution & validation
  - Branch/remote state verification
  - Conflict resolution support

👉 How to proceed:
   Option 1 - Delegate to git-expert agent:
     Invoke: /git-expert
     Or: Agent(subagent_type: "git-expert", prompt: "...")

   Option 2 - Direct authorization in same shell:
     export GIT_EXPERT_OPERATION=1
     git commit ...

Allowed direct operations (read-only):
  - git status, git log, git diff, git show, git remote -v, git branch -v
MSG
  exit 2
fi

exit 0
