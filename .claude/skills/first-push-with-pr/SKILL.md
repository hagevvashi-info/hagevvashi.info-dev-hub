---
name: first-push-with-pr
description: push スキルを活用してコミット＆プッシュまで完了させてからPRを作成する。「PRを作って」「プルリクを出して」などの指示で使用する。
disable-model-invocation: false
---

# Git Create PR Skill

## STEP 0: 現状確認とリモート設定の特定

```bash
git status
git remote -v

# fork workflow か単純なリポジトリかを判定
if git remote | grep -qx upstream; then
  base_remote=upstream
  push_remote=origin
else
  base_remote=$(git remote | grep -x origin || git remote | head -1)
  push_remote=$base_remote
fi
# -n でネットワークアクセスなし（キャッシュ参照）
base=$(git remote show -n "$base_remote" | grep "HEAD branch" | awk '{print $NF}')
```

| ケース | `push_remote` | `base_remote` |
|---|---|---|
| `upstream` あり（fork） | `origin` | `upstream` |
| `upstream` なし・`origin` あり | `origin` | `origin` |
| 複数あって判定不能 | ユーザーに選択を求める | ユーザーに選択を求める |

## STEP 1: ブランチ命名とブランチ作成

新しいブランチを作成する。命名規則は `.claude/rules/002_git_guidelines.md` のプレフィックスに従う。

```bash
# ブランチ名を決定（例：feat/xxx, fix/xxx, docs/xxx, refactor/xxx）
branch_name="<prefix>/<description>"

# 新ブランチを作成してチェックアウト
git switch -c "$branch_name"
```

**例**:
- `docs/remote-llm-bridge-design`
- `feat/new-auth-system`
- `fix/login-bug`

## STEP 2: コミット＆プッシュ

- **未コミットの変更がある場合** → `push` スキルを呼び出してコミット＆プッシュを完了させてから STEP 3 へ進む
- **コミット済みだがプッシュ未完了の場合** → `push` スキルを呼び出してプッシュのみ行ってから STEP 3 へ進む
- **プッシュ済みの場合** → そのまま STEP 3 へ進む

## STEP 3: PR内容の把握

STEP 0 で特定した `base_remote` / `base` を使って差分を確認する。3-dot diff で共通祖先からの変更を確認。

```bash
git log --oneline "$base_remote/$base"..."HEAD"
git diff --stat "$base_remote/$base"..."HEAD"
```

**3-dot diff の意味**: 共通祖先からの変更を表示。fork workflow で正確に「この PR が何を追加するか」を示す。

## STEP 3: PR タイトル・本文の作成

### タイトル

- 70文字以内
- 変更の本質を一言で表す（詳細は本文に書く）

### 本文の各セクションに埋める内容

STEP 4 のコマンド内テンプレートを正本として使用する。各セクションの記述指針：

- **Goal**: 課題が解決された状態を1〜2文で記述する
- **Strategy**: 解決のアプローチ・仮説を記述する
- **Why**: 選択肢を比較テーブルで示す。比較項目には品質特性・非機能要件を選び、重みを付ける（高／中／低）。評価は ◎／○／△／× で記入し、採用行で意思決定を明示する
- **What**: 作るモノを具体的に列挙する（例: ○○ Jenkins Job、○○シナリオ、○○マニフェスト）
- **Test**: Goal と Why が達成されたことを確認できる MECE なチェックツリー。変更の複雑さに応じて階層を増減する。確認済みは ✅、未確認は `- [ ]`

## STEP 4: PR作成

heredoc を Bash tool 内で使うと PreToolUse hook と干渉するため、
**必ず Write ツール + `--body-file` の2ステップで実行すること**。

### 4-1: 一時ファイルパスの生成

```bash
tmpfile=$(mktemp /tmp/pr-body-XXXXXX.md)
echo "$tmpfile"
```

### 4-2: Write ツールで本文を書き出す

Bash tool は使わず **Write ツール**で `$tmpfile` のパスに以下を書き出す。

```markdown
## Goal
<課題が解決された状態>

## Strategy
<解決のアプローチ・仮説>

## Why

| 比較項目 | 重み | 選択肢1: ... | 選択肢2: ... | 選択肢3: ... |
|---------|------|------------|------------|------------|
| a. ...  | 高   |            |            |            |
| b. ...  | 中   |            |            |            |
| c. ...  | 低   |            |            |            |
| **採用** |      | **✅**      |            |            |

## What
-

## Test
- [ ]
  - [ ]
  - [ ]

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 4-3: PR 作成と一時ファイルの削除

`--base` には STEP 1 で特定した `base` を指定する。
fork workflow（`base_remote=upstream`）の場合は `gh` がリポジトリを自動検出するが、
検出できない場合は `--repo <upstream_owner>/<repo>` を追加する。

```bash
gh pr create --base "$base" --title "<title>" --body-file "$tmpfile" && rm -f "$tmpfile"
```

## STEP 5: PR URL をユーザーに提示

作成完了後、PR の URL を必ずユーザーに伝える。

## 禁止事項

- コミットやプッシュが完了していない状態での PR 作成
- `git checkout` / `git reset HEAD` の使用（hook でブロックされる）
