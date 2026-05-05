#!/bin/bash
# Blocks deprecated git commands per .claude/rules/002_git_guidelines.md
# Runs as a PreToolUse hook on Bash tool calls.

cmd=$(cat | jq -r '.tool_input.command // ""' 2>/dev/null)

if echo "$cmd" | grep -qE '\bgit checkout\b'; then
  # Allow exceptions: temporary navigation to a commit hash or remote branch ref
  if echo "$cmd" | grep -qE 'git checkout ([0-9a-f]{6,40}|origin/)'; then
    exit 0
  fi

  cat <<'EOF'
非推奨コマンド: git checkout

.claude/rules/002_git_guidelines.md に従い、以下を使用してください:
  ブランチ切替:       git switch <branch>
  新ブランチ作成:     git switch -c <branch>
  ファイル復元:       git restore <file>
  リモートブランチ追跡: git switch -c <local> origin/<remote>

例外（今回のコマンドが該当する場合は続行してください）:
  git checkout <commit-hash>   — 特定コミットへの一時的な移動
  git checkout origin/<branch> — リモートブランチの一時的な確認
EOF
  exit 2
fi

if echo "$cmd" | grep -qE '\bgit reset HEAD\b'; then
  echo "非推奨コマンド: git reset HEAD"
  echo "代わりに 'git restore --staged <file>' を使用してください。"
  exit 2
fi
