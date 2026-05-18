# 自動レビューフック テスト計画

このドキュメントは、自動レビューフック機能（PostToolUse Hook）の検証方法を記載しています。

## テスト前提条件

- Redis サーバーが起動していること（セッション保存用）
- `claude` CLI が PATH に含まれていること
- `.claude/hooks/` ディレクトリに以下のファイルが存在すること：
  - `orchestrate_review.sh`
  - `run_review.sh`
  - `review_to_memory.sh`
- `.claude/settings.json` に PostToolUse フック設定が有効であること

## テストシナリオ 1: 通常の修正ファイルレビュー

**目的**: フックが正常に実行され、レビュー結果がメモリに保存されることを確認

**手順**:
1. テストファイルを作成
   ```bash
   echo "# Test file" > /tmp/test_review.md
   ```

2. Claude Code で Edit ツール経由でファイルを修正
   ```
   Edit /tmp/test_review.md
   ...（テキストを追加）
   ```

3. Edit 実行後、5 秒以内にメモリファイルが更新されたことを確認
   ```bash
   ls -la ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/auto_review_pending.md
   ```

4. メモリファイルの内容確認
   ```bash
   cat ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/auto_review_pending.md
   ```

**期待結果**:
- メモリファイル `auto_review_pending.md` が存在する
- ファイルが以下の構造を持つ：
  ```
  ---
  name: auto_review_pending
  description: Auto review result pending main agent action
  metadata:
    type: project
    timestamp: <timestamp>
  ---
  
  ## 自動レビュー結果（実行待ち）
  
  レビュー実行日時: <datetime>
  
  ### レビュー内容
  
  <review output>
  ```
- ファイルサイズが 1KB 以上（レビュー内容が実際に保存されている）

**失敗した場合の診断**:
```bash
# フックが実行されたか確認（settings.json が正しいか）
jq '.hooks.PostToolUse' ~/.claude/settings.json

# orchestrate_review.sh が実行可能か確認
ls -la ~/.claude/hooks/orchestrate_review.sh
file ~/.claude/hooks/orchestrate_review.sh

# スクリプトの構文エラーを確認
bash -n ~/.claude/hooks/orchestrate_review.sh
bash -n ~/.claude/hooks/run_review.sh
bash -n ~/.claude/hooks/review_to_memory.sh
```

---

## テストシナリオ 2: 危険なファイル名での安全性（セキュリティ検証）

**目的**: ファイル名にシェルメタ文字が含まれてもフックが安全に動作することを確認

**手順**:
1. 危険なファイル名でテストファイルを作成
   ```bash
   mkdir -p /tmp/test_special_chars
   touch "/tmp/test_special_chars/test_\$(whoami).txt"
   touch "/tmp/test_special_chars/test_\`date\`.txt"
   touch "/tmp/test_special_chars/test_\&more.txt"
   ```

2. Claude Code で Edit ツール経由でこれらのファイルを修正

3. エラーが発生せず、レビュー結果がメモリに保存されたことを確認
   ```bash
   grep "whoami" ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/auto_review_pending.md || echo "✅ No command injection detected"
   ```

**期待結果**:
- フックが正常に完了する（エラーが発生しない）
- ファイル名がレビューで正しく伝わる
- 任意のコマンドが実行されない（`whoami` などの結果が埋め込まれない）

**失敗した場合の診断**:
```bash
# ファイル名が正しくエスケープされているか確認
cat ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/auto_review_pending.md | grep "test_"

# run_review.sh の配列処理が正しいか確認
bash -x ~/.claude/hooks/run_review.sh /tmp/modified_files.txt /tmp/output.md
```

---

## テストシナリオ 3: Timeout 動作の確認

**目的**: レビュー実行が 30 秒以上かかった場合、タイムアウトして gracefully 続行することを確認

**手順**:
1. `run_review.sh` の timeout 値を低く設定してテスト（リバートは必須）
   ```bash
   # 一時的に REVIEW_TIMEOUT=2 に変更
   sed -i 's/readonly REVIEW_TIMEOUT=30/readonly REVIEW_TIMEOUT=2/' ~/.claude/hooks/run_review.sh
   ```

2. Claude Code で Edit を実行

3. メモリファイルに timeout メッセージが記録されたことを確認
   ```bash
   grep -i "timeout" ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/auto_review_pending.md
   ```

4. **必ず timeout 値を元に戻す**
   ```bash
   sed -i 's/readonly REVIEW_TIMEOUT=2/readonly REVIEW_TIMEOUT=30/' ~/.claude/hooks/run_review.sh
   ```

**期待結果**:
- Edit が完了する（timeout でブロックされない）
- メモリファイルに "⚠️  Review execution timed out (2s)" というメッセージが記録される
- リバート後、通常のレビューが実行される

**失敗した場合の診断**:
```bash
# timeout コマンドが存在するか確認
which timeout
timeout --version

# run_review.sh の timeout 行を確認
grep "timeout" ~/.claude/hooks/run_review.sh
```

---

## テストシナリオ 4: エラーハンドリングの確認

**目的**: 各段階でのエラーが適切にハンドルされることを確認

### 4-1: Review エージェント失敗時

**手順**:
1. `run_review.sh` を直接テスト（review エージェント呼び出しが失敗するシナリオ）
   ```bash
   # 一時的に claude CLI コマンドを無効化
   PATH_BACKUP="$PATH"
   export PATH="/tmp:$PATH"
   touch /tmp/claude && chmod +x /tmp/claude && echo "exit 1" > /tmp/claude
   
   bash ~/.claude/hooks/run_review.sh /tmp/modified_files.txt /tmp/output.md
   
   # 結果を確認
   cat /tmp/output.md
   
   # PATH を復元
   export PATH="$PATH_BACKUP"
   ```

**期待結果**:
- スクリプトが exit 1 で終了する（エラーを適切に報告）
- 出力ファイルに "⚠️  Review execution failed" というメッセージが含まれる

### 4-2: メモリ書き込み失敗時

**手順**:
1. メモリディレクトリへの書き込み権限を制限
   ```bash
   # テスト用ディレクトリを作成
   test_dir="/tmp/test_memory_readonly"
   mkdir -p "$test_dir"
   
   # review_to_memory.sh を実行（失敗が期待される）
   MEMORY_DIR="$test_dir" bash ~/.claude/hooks/review_to_memory.sh /tmp/modified.txt /tmp/output.md || echo "✅ Error handled"
   ```

**期待結果**:
- スクリプトが exit 1 で終了する
- エラーメッセージが stderr に出力される

---

## テストシナリオ 5: 無限再帰防止の確認

**目的**: review エージェントが修正を行った場合、無限ループが発生しないことを確認

**手順**:
1. メモリファイルの監視開始
   ```bash
   watch -n 1 'ls -la ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/ | grep auto_review'
   ```

2. Claude Code で Edit を実行

3. メモリファイルが複数回更新されないことを確認（1-2 回更新されたら終了）

4. watch コマンドを Ctrl+C で終了

**期待結果**:
- メモリファイルが 1 回だけ更新される
- タイムスタンプが単調増加する（複数回の実行がない）

**失敗した場合の診断**:
```bash
# メモリファイルの更新履歴を確認
stat ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory/auto_review_pending.md

# ホックのログを確認（设定に logging を追加している場合）
tail -f /tmp/claude_hook.log
```

---

## 回帰テスト（全機能）

すべてのテストを実行して、機能が保たれていることを確認します：

```bash
#!/bin/bash
set -euo pipefail

echo "🧪 Running Regression Tests..."

# テスト 1: スクリプト構文チェック
echo "[Test 1] Script syntax validation..."
bash -n ~/.claude/hooks/orchestrate_review.sh
bash -n ~/.claude/hooks/run_review.sh
bash -n ~/.claude/hooks/review_to_memory.sh
echo "✅ All scripts have valid syntax"

# テスト 2: 必須ファイル存在確認
echo "[Test 2] Required files existence..."
[ -f ~/.claude/settings.json ] && echo "✅ settings.json exists"
[ -f ~/.claude/hooks/orchestrate_review.sh ] && echo "✅ orchestrate_review.sh exists"
[ -f ~/.claude/hooks/run_review.sh ] && echo "✅ run_review.sh exists"
[ -f ~/.claude/hooks/review_to_memory.sh ] && echo "✅ review_to_memory.sh exists"

# テスト 3: JSON 設定の検証
echo "[Test 3] JSON settings validation..."
jq -e '.hooks.PostToolUse[0].matcher == "Edit|Write"' ~/.claude/settings.json && echo "✅ Hook matcher is correct"
jq -e '.hooks.PostToolUse[0].hooks[0].command | contains("orchestrate_review.sh")' ~/.claude/settings.json && echo "✅ Hook command references orchestrate_review.sh"

# テスト 4: メモリディレクトリ存在確認
echo "[Test 4] Memory directory..."
[ -d ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory ] && echo "✅ Memory directory exists"

echo ""
echo "✅ All regression tests passed!"
```

---

## トラブルシューティング

### フックが実行されない

**原因**: settings.json が無効な JSON または ReLoad されていない

```bash
# JSON 構文を確認
jq empty ~/.claude/settings.json && echo "✅ Valid JSON"

# 設定をリロード（Claude Code の /hooks メニューを使用）
# または設定ファイルを再度開く
```

### "Review output is empty" エラー

**原因**: claude CLI が出力を生成しなかった（認証エラーなど）

```bash
# claude CLI が動作するか確認
claude --version

# review エージェントが使用可能か確認
claude --agent review --print "test" 2>&1 | head -5
```

### メモリファイルが作成されない

**原因**: メモリディレクトリへの書き込み権限がない

```bash
# ディレクトリの権限を確認
ls -ld ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory

# 必要に応じて再作成
mkdir -p ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory
chmod 755 ~/.claude/projects/-home-hagevvashi-hagevvashi-info-dev-hub/memory
```

### タイムアウトが短すぎる

**原因**: レビュー実行に 30 秒以上かかっている

**対応**: `run_review.sh` の `REVIEW_TIMEOUT` を増やす

```bash
# タイムアウト値を 60 秒に変更
sed -i 's/readonly REVIEW_TIMEOUT=30/readonly REVIEW_TIMEOUT=60/' ~/.claude/hooks/run_review.sh
```

---

## テスト実行チェックリスト

- [ ] テストシナリオ 1: 通常のレビュー実行
- [ ] テストシナリオ 2: 危険なファイル名
- [ ] テストシナリオ 3: Timeout 動作
- [ ] テストシナリオ 4: エラーハンドリング
- [ ] テストシナリオ 5: 無限再帰防止
- [ ] 回帰テスト: 全スクリプト構文チェック

すべてのテストが完了したら ✅ を付けてください。
