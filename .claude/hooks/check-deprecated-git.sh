#!/bin/bash
# Blocks deprecated git commands per .claude/rules/002_git_guidelines.md
# Runs as a PreToolUse hook on Bash tool calls.

cmd=$(cat | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

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

# Prevent accidental push to upstream/main
if echo "$cmd" | grep -qE '^\s*git push\s*$'; then
  current_branch=$(cd /home/hagevvashi/hagevvashi.info-dev-hub 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$current_branch" = "main" ]; then
    cat <<'EOF'
❌ エラー: upstream/main への誤送信を防止しています

git push 単発での main ブランチからの push は禁止されています。
upstream/main への push を避けるため、以下のいずれかを使用してください:

  origin に push:      git push origin main
  upstream に push:    git push upstream main (明示的に指定)
  別ブランチに push:   git push origin <branch-name>

リモート/ブランチを明示的に指定したコマンドを使用してください。
EOF
    exit 2
  fi
fi

exit 0
