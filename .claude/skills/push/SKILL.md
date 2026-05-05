---
name: push
description: git_guidelines.md に従ってコミットメッセージ3候補を提示し、ユーザー確認後にコミット＆プッシュする。「コミットして」「pushして」「コミット＆プッシュ」などの指示で使用する。
disable-model-invocation: false
---

# Push Skill

`.claude/rules/002_git_guidelines.md` を遵守してコミット＆プッシュを行う。

## STEP 1: Pre-flight チェック

以下を**必ず**実行して現状を把握する。

```bash
git status
git remote -v
```

未コミットの変更がない場合はその旨をユーザーに伝えてスキルを終了する。

## STEP 2: 変更内容の把握

生の `git diff` は出力が大きくなるため禁止。以下で確認する。

```bash
git diff --stat
```

## STEP 3: ステージング

`git add -A` や `git add .` は機密ファイルを含む危険があるため原則禁止。
変更ファイルを `git status` で確認し、**ファイル名を指定して**ステージングする。

```bash
git add <file1> <file2> ...
```

ただしユーザーが明示的に全ファイル追加を指示した場合は `git add .` を使ってよい。

## STEP 4: コミットメッセージ候補の提示

`.claude/rules/002_git_guidelines.md` のコミットメッセージ作成指針に従い、**必ず3つの候補**を作成してユーザーに提示する。

### フォーマット（各候補）

```
候補N:
---
<prefix>: <title>

<body（変更の理由を含む。"Why:"書き出し禁止）>
---
メリット: ...
デメリット: ...
```

使用できる prefix: `feat` / `fix` / `docs` / `ci` / `chore` / `refactor` / `build` / `perf` / `style` / `test`

### 最適候補の推薦

3候補を提示した後、「候補Nが最適です。理由: ...」と日本語で明示して推薦する。
ユーザーの確認を取ってから次のステップに進む。

## STEP 5: コミット実行

ユーザーが選択・承認した候補でコミットする。

```bash
git commit -m "$(cat <<'EOF'
<prefix>: <title>

<body>
EOF
)"
```

## STEP 6: プッシュ前確認

プッシュはリモートに影響するため、**必ずユーザーに確認してから**実行する。

現在のブランチとリモートの状態を確認:
```bash
git status
git log --oneline -5
```

### リモート名の決定

STEP 1 の `git remote -v` 結果をもとに以下のルールでリモート名を決定する。

```bash
remote=$(git remote | grep -x origin || git remote | head -1)
```

- リモートが1つだけ → そのまま使用
- `origin` が存在する → `origin` を使用
- 複数あって `origin` がない → 一覧をユーザーに提示して選択を求める

### upstream へのプッシュ禁止

解決した `remote` が `upstream` の場合は**中断してユーザーに警告する**。

```
upstream への直接 push は禁止です。
fork workflow では origin に push し、upstream へは PR 経由で変更を送ってください。
```

### プッシュ実行

ユーザーの承認後:

```bash
# 初回プッシュ（リモート追跡ブランチが未設定の場合）
git push -u <remote> <branch-name>

# 2回目以降
git push
```

## 禁止事項

- `git checkout` の使用（hook でブロックされる）
- `git reset HEAD` の使用（hook でブロックされる）
- `git push --force` の使用（ユーザーが明示的に指示した場合のみ許容）
