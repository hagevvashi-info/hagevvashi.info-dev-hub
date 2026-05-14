#!/bin/bash
# Blocks deprecated git commands per .claude/rules/002_git_guidelines.md
# Runs as a PreToolUse hook on Bash tool calls.

cmd=$(cat | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception as e:
    print('', file=sys.stderr)
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

# Prevent direct commit and push to main branch
current_branch=$(cd /home/hagevvashi/hagevvashi.info-dev-hub 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)

# Prevent accidental commit to main
if echo "$cmd" | grep -qE '^\s*git commit\b'; then
  if [ "$current_branch" = "main" ]; then
    cat <<'EOF'
❌ エラー: main ブランチへの直接コミットは禁止されています

main ブランチで作業をしないでください。必ず新しいブランチを作成して作業してください。

以下の手順を実行してください:

1. 新しいブランチを作成:
   git switch -c <branch-name>

2. 既にコミット済みの場合、コミットを移動:
   git reset HEAD~1                  # 最後のコミットを取り消す
   git switch -c <branch-name>        # 新しいブランチを作成
   git commit -m "..."               # 改めてコミット

3. push を実行:
   git push origin <branch-name>
EOF
    exit 2
  fi
fi

# Prevent accidental push to upstream/main
if echo "$cmd" | grep -qE '^\s*git push\s*$'; then
  if [ "$current_branch" = "main" ]; then
    cat <<'EOF'
❌ エラー: main ブランチからの push は禁止されています

main ブランチで作業をしないでください。必ず新しいブランチを作成して作業してください。

以下の手順を実行してください:

1. 新しいブランチを作成:
   git switch -c <branch-name>

2. コミットを移動（既にコミット済みの場合）:
   git reset HEAD~1                  # 最後のコミットを取り消す
   git switch -c <branch-name>        # 新しいブランチを作成
   git commit -m "..."               # 改めてコミット

3. push を実行:
   git push origin <branch-name>
EOF
    exit 2
  fi
fi

exit 0
