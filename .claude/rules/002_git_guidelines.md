---
description: this file explains best practices. please always refer to this file.
---

# Git操作ガイドライン

- このファイルが読み込まれたら「git_guidelines.mdを読み込みました！」と作業着手前にユーザーに必ず伝えてください。

---

# AIアシスタントへの指示

- 既存リポジトリでの操作時は、必ず`git status`や`git remote -v`で状態確認を行うこと
- `git init`コマンドの使用は、新規リポジトリ作成時のみに制限すること
- 既存リポジトリでの操作は、現状を維持した上で必要な変更のみを行うこと 

---

# Git コマンドに関する基本ルール

## 推奨するGitコマンド

Git 2.23以降で導入された新しいインターフェースを使用すること:

### ブランチ操作

- **ブランチの切り替え**: `git switch <branch-name>`
  - 古いコマンド: ~~`git checkout <branch-name>`~~

- **新しいブランチの作成と切り替え**: `git switch -c <branch-name>`
  - 古いコマンド: ~~`git checkout -b <branch-name>`~~

- **リモートブランチの追跡**: `git switch -c <local-branch> origin/<remote-branch>`
  - 古いコマンド: ~~`git checkout -b <local-branch> origin/<remote-branch>`~~

### ファイル操作

- **ファイルの復元**: `git restore <file>`
  - 古いコマンド: ~~`git checkout -- <file>`~~

- **ステージングの取り消し**: `git restore --staged <file>`
  - 古いコマンド: ~~`git reset HEAD <file>`~~

## 使い分け

| 操作 | 推奨コマンド | 旧コマンド（非推奨） |
|------|------------|-------------------|
| ブランチ切り替え | `git switch` | `git checkout` |
| 新ブランチ作成 | `git switch -c` | `git checkout -b` |
| ファイル復元 | `git restore` | `git checkout --` |
| ステージング取り消し | `git restore --staged` | `git reset HEAD` |

## 理由

- **明確性**: `switch` と `restore` は操作の意図が明確
- **安全性**: `checkout` は多機能すぎて誤操作のリスクがある
- **モダン**: Git 2.23以降のベストプラクティス

## 例外

以下の場合は古いコマンドの使用も許容:

- 特定のコミットやタグへの一時的な移動: `git checkout <commit-hash>`
- リモートブランチの一時的な確認: `git checkout origin/<branch>`

---

# コマンド実行時の注意事項

1. **ブランチ名の命名規則**
   - `feat/`: 新機能追加
   - `fix/`: バグ修正
   - `refactor/`: リファクタリング
   - `docs/`: ドキュメント更新
   - `chore/`: 雑務

2. **確認後の実行**
   - ブランチ切り替え前に `git status` で作業ツリーの状態を確認
   - 未コミットの変更がある場合は警告

3. **エラー対処**
   - `git switch` でエラーが出た場合、Gitのバージョンを確認（2.23以降が必要）

---

# git diffの使用について

1. **大きな出力の回避**
   - `git diff`は大きな出力で中断される可能性があるため、以下の方法を使用する：
   ```bash
   # 変更ファイルの一覧を確認
   git status
   
   # 特定のファイルの変更を確認（必要な場合）
   git diff --stat
   
   # 変更をステージングして確認
   git add .
   git status
   ```

2. **変更の確認方法**
   - 大きな変更の場合は`git diff`を直接使用せず、以下の手順で確認：
     1. `git status`で変更ファイルを確認
     2. `git add`で変更をステージング
     3. `git status`で最終確認
     4. 必要に応じて`git restore --staged`で取り消し

---

# コミットメッセージ作成指針

## 基本ルール
- prefixをつけること
- prefixは以下から選ぶこと:
  - `docs`: ドキュメントの変更
  - `ci`: CI関連の変更
  - `chore`: 雑務的な変更
  - `feat`: 新機能の追加
  - `refactor`: リファクタリング
  - `build`: ビルドシステムの変更
  - `perf`: パフォーマンス改善
  - `style`: コードスタイルの変更
  - `test`: テストの追加・修正
- コミットメッセージは英語で作成すること
- 必ず3つの候補を作成し、各候補にメリット・デメリットを日本語で添えること
- その候補の中から最適なものを選んでコミットメッセージとすること
- なぜそれが最適化をしっかりとユーザーに伝えること

## メッセージフォーマット
```
${prefix}: ${title}

${body}
```

### フォーマット詳細
- シンプルなプレーンテキストであること
- 1行目: `${prefix}: ${title}`形式でタイトルを記述
- 2行目: 必ず空行とする
- 3行目以降: 本文を記述
  - 変更の理由（Why）を必ず含める
  - ただし、"Why:"という書き出しは使用しない

## 候補作成例

変更内容：AIアシスタントの行動指針を追加した場合

候補1:
```
docs: add AI assistant behavioral guidelines

Define core principles and specific guidelines for AI assistant behavior.
This helps maintain consistency in AI responses and prevents common mistakes
in command execution, especially for Docker operations.
```
メリット：
- 変更の目的と効果が明確
- ドキュメントの性質を正確に表現
デメリット：
- 技術的な詳細が少ない

候補2:
```
feat: implement AI assistant guidelines system

Create .ai directory with guidelines.md to establish systematic approach
for AI assistant behavior. This provides a reusable framework for
maintaining consistent AI responses across different operations.
```
メリット：
- システムとしての側面を強調
- 構造的な変更であることが分かる
デメリット：
- 機能追加というよりドキュメント追加の性質が強い

候補3:
```
chore: set up AI assistant documentation structure

Establish .ai directory and initial guidelines document to standardize
AI assistant behavior patterns. This creates a foundation for future
additions to AI behavioral rules.
```
メリット：
- 将来の拡張性を示唆
- セットアップ作業の性質を表現
デメリット：
- 重要度が低く見える可能性がある 
