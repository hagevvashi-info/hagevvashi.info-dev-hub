---
inclusion: always
---

# Rules - git-commands-guidelines（Gitコマンド使用指針）

- このファイルが読み込まれたら「git-commands-guidelines.mdcを読み込みました！」と作業着手前にユーザーに必ず伝えてください。

---

## 基本ルール

### 推奨するGitコマンド

Git 2.23以降で導入された新しいインターフェースを使用すること:

#### ブランチ操作

- **ブランチの切り替え**: `git switch <branch-name>`
  - 古いコマンド: ~~`git checkout <branch-name>`~~

- **新しいブランチの作成と切り替え**: `git switch -c <branch-name>`
  - 古いコマンド: ~~`git checkout -b <branch-name>`~~

- **リモートブランチの追跡**: `git switch -c <local-branch> origin/<remote-branch>`
  - 古いコマンド: ~~`git checkout -b <local-branch> origin/<remote-branch>`~~

#### ファイル操作

- **ファイルの復元**: `git restore <file>`
  - 古いコマンド: ~~`git checkout -- <file>`~~

- **ステージングの取り消し**: `git restore --staged <file>`
  - 古いコマンド: ~~`git reset HEAD <file>`~~

### 使い分け

| 操作 | 推奨コマンド | 旧コマンド（非推奨） |
|------|------------|-------------------|
| ブランチ切り替え | `git switch` | `git checkout` |
| 新ブランチ作成 | `git switch -c` | `git checkout -b` |
| ファイル復元 | `git restore` | `git checkout --` |
| ステージング取り消し | `git restore --staged` | `git reset HEAD` |

### 理由

- **明確性**: `switch` と `restore` は操作の意図が明確
- **安全性**: `checkout` は多機能すぎて誤操作のリスクがある
- **モダン**: Git 2.23以降のベストプラクティス

### 例外

以下の場合は古いコマンドの使用も許容:

- 特定のコミットやタグへの一時的な移動: `git checkout <commit-hash>`
- リモートブランチの一時的な確認: `git checkout origin/<branch>`

---

## コマンド実行時の注意事項

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
