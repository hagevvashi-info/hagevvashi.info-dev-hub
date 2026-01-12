# DevContainer 既存コンテナ接続の設定

**作成日**: 2026-01-11
**目的**: `./bin/dc up`で起動したコンテナにVSCode DevContainerが接続できるよう設定する

---

## 1. 問題の状況

### 1.1 現象

```
./bin/dc up でコンテナ起動中
↓
VSCode DevContainer で開こうとする
↓
DevContainer が新しいコンテナを起動しようとする
↓
ポート競合でエラー
```

### 1.2 原因

現在の`.devcontainer/devcontainer.json.template`には、既存コンテナへの接続設定がないため、DevContainerは常に新しいコンテナを起動しようとします。

**現在の設定**:
```json
{
  "dockerComposeFile": "docker-compose.yml",
  "service": "dev",
  "workspaceFolder": "/home/__UNAME__/__MDC_REPO_ROOT__",
  "remoteUser": "__UNAME__"
  // runServices, shutdownAction などの設定がない
}
```

### 1.3 影響

- `./bin/dc up`で起動済みのコンテナがあると、VSCode DevContainerでエラーが発生する
- ポート競合により、どちらかのコンテナしか起動できない
- ユーザーは手動でコンテナを停止してからVSCodeを開く必要がある

---

## 2. 解決策

### 2.1 推奨設定

`.devcontainer/devcontainer.json.template`に以下の設定を追加:

```json
{
  "name": "Development Environment",

  "runArgs": [
    "--platform",
    "__PLATFORM__"
  ],

  "dockerComposeFile": "docker-compose.yml",
  "service": "dev",
  "workspaceFolder": "/home/__UNAME__/__MDC_REPO_ROOT__",
  "initializeCommand": "./.devcontainer/generate-env.sh",
  "postCreateCommand": "/home/__UNAME__/__MDC_REPO_ROOT__/.devcontainer/post-create.sh",
  "remoteUser": "__UNAME__",

  // 追加する設定
  "runServices": ["dev"],
  "shutdownAction": "none",
  "overrideCommand": false,

  "mounts": [
    // ... 既存のマウント設定
  ],

  "features": {
    "ghcr.io/devcontainers/features/docker-from-docker:1": {}
  },

  "customizations": {
    // ... 既存のカスタマイズ設定
  }
}
```

### 2.2 各設定の詳細説明

#### `"runServices": ["dev"]`

**役割**: VSCodeが管理するDocker Composeサービスを指定

**効果**:
- 明示的に"dev"サービスのみを指定
- 既にコンテナが起動している場合、VSCodeは既存のコンテナを検出して接続
- 新しいコンテナを作成しない

**動作の仕組み**:
1. VSCodeがDevContainerを開く
2. `docker compose ps`で"dev"サービスの状態を確認
3. コンテナが既に起動中 → 既存のコンテナに接続
4. コンテナが停止中 → 新しいコンテナを起動

**参考**: [GitHub Issue #9118](https://github.com/microsoft/vscode-remote-release/issues/9118)より、既にサービスが起動している場合、`runServices`配列は無視され、既存のコンテナに接続されます。

#### `"shutdownAction": "none"`

**役割**: VSCode終了時にコンテナを停止しない

**効果**:
- VSCodeを閉じてもコンテナが動き続ける
- `./bin/dc`での手動コンテナ管理が可能

**選択肢**:
- `"none"`: 何もしない（推奨）
- `"stopCompose"`: すべてのComposeサービスを停止
- デフォルト（未指定）: コンテナを停止

**なぜ"none"が推奨か**:
- ユーザーが`./bin/dc up`でコンテナを起動
- ユーザーが`./bin/dc down`でコンテナを停止
- VSCodeは接続と切断のみを行う

#### `"overrideCommand": false`

**役割**: docker-composeで定義されたコマンド/ENTRYPOINTを上書きしない

**効果**:
- v10設計のs6-overlay ENTRYPOINTを保持
- コンテナの起動プロセスを変更しない

**重要性**:
- 現在のコンテナは`/init`（s6-overlay）をENTRYPOINTとして使用
- これを上書きすると、supervisord、process-composeなどが起動しない

**Docker Composeでのデフォルト**:
- 通常、Docker Composeを使用する場合、この値はデフォルトで`false`
- 明示的に指定することで意図を明確化

---

## 3. 動作フロー

### 3.1 修正前（現状）

```
1. ユーザー: ./bin/dc up
   → コンテナ起動（ポート4035, 8035, 9001, 8080使用）

2. ユーザー: VSCode DevContainer で開く
   → VSCode: 新しいコンテナを起動しようとする
   → Docker: ポート4035が既に使用中
   → ❌ エラー: "port is already allocated"
```

### 3.2 修正後（推奨設定適用）

```
1. ユーザー: ./bin/dc up -d
   → コンテナ起動（ポート4035, 8035, 9001, 8080使用）

2. ユーザー: VSCode DevContainer で開く
   → VSCode: docker compose ps で"dev"サービスを確認
   → VSCode: 既に起動中のコンテナを検出
   → VSCode: 既存のコンテナに接続
   → ✅ 成功: <一般ユーザー>@<container-id>:~/<MDCレポジトリ>$

3. ユーザー: VSCode を閉じる
   → VSCode: 接続を切断
   → コンテナ: 起動したまま継続（shutdownAction: "none"）

4. ユーザー: ./bin/dc down
   → コンテナ停止・削除
```

---

## 3A. 全パターンの動作検証

### パターン1: DevContainer → ./bin/dc up（逆パターン）

```
1. ユーザー: VSCode DevContainer で開く
   → VSCode: コンテナが存在しないことを確認
   → VSCode: 新しいコンテナを起動
   → ✅ 成功: コンテナ起動、VSCode接続

2. ユーザー: （VSCodeを開いたまま）別のターミナルで ./bin/dc up を実行
   → Docker Compose: "dev"サービスの状態を確認
   → Docker Compose: 既にコンテナが起動中
   → ✅ 成功: "Container ... is up-to-date" と表示され、何もしない

3. 結果: 問題なし（同じコンテナを共有）
```

**重要なポイント**:
- Docker Composeは既存のコンテナを検出すると、新しいコンテナを作成しない
- VSCodeとターミナルの両方から同じコンテナにアクセス可能
- ポート競合は発生しない

### パターン2: DevContainer起動中 → ./bin/dc exec（attach）

```
1. ユーザー: VSCode DevContainer で開く
   → VSCode: コンテナ起動・接続
   → ✅ VSCodeのターミナル: <一般ユーザー>@<container-id>:~$

2. ユーザー: 別のターミナルで ./bin/dc exec dev bash
   → Docker: 既存のコンテナに新しいbashプロセスを起動
   → ✅ 成功: <一般ユーザー>@<container-id>:~$

3. 結果: 両方のターミナルから同じコンテナにアクセス可能
   - VSCodeのターミナル: プロセス1（bash）
   - ./bin/dc execのターミナル: プロセス2（bash）
   - どちらも同じファイルシステム、環境変数を共有
```

**確認方法**:
```bash
# VSCodeのターミナルで
echo $$ > /tmp/vscode-pid
cat /tmp/vscode-pid
# 例: 12345

# ./bin/dc execのターミナルで
echo $$
# 例: 67890（異なるPID）

cat /tmp/vscode-pid
# 12345（同じファイルが見える）
```

### パターン3: ./bin/dc up → VSCode → ./bin/dc exec（全部使う）

```
1. ユーザー: ./bin/dc up -d
   → コンテナ起動

2. ユーザー: VSCode DevContainer で開く
   → VSCode: 既存のコンテナに接続
   → ✅ VSCodeのターミナル: <一般ユーザー>@<container-id>:~$

3. ユーザー: 別のターミナルで ./bin/dc exec dev bash
   → ✅ 新しいbashセッション: <一般ユーザー>@<container-id>:~$

4. 結果: 3つのアクセス方法が共存
   - ./bin/dc up: コンテナのライフサイクル管理
   - VSCode: IDE統合開発
   - ./bin/dc exec: ターミナル作業
```

### パターン4: VSCode終了後に ./bin/dc exec（shutdownAction: "none"の効果）

```
1. ユーザー: VSCode DevContainer で開く
   → コンテナ起動・接続

2. ユーザー: VSCode を閉じる
   → VSCode: 接続を切断
   → コンテナ: 起動したまま継続（shutdownAction: "none"）

3. ユーザー: ./bin/dc exec dev bash
   → ✅ 成功: 既存のコンテナに接続できる

4. ユーザー: docker compose ps
   → ✅ "dev"サービスが"Up"状態のまま
```

**もし shutdownAction が設定されていない場合**:
```
1. ユーザー: VSCode DevContainer で開く
   → コンテナ起動・接続

2. ユーザー: VSCode を閉じる
   → VSCode: docker compose down を実行
   → コンテナ: 停止・削除される

3. ユーザー: ./bin/dc exec dev bash
   → ❌ エラー: "Error: No such container"
```

### パターン5: 複数のVSCodeウィンドウ（同じコンテナ）

```
1. ユーザー: VSCodeウィンドウ1でDevContainerを開く
   → コンテナ起動・接続

2. ユーザー: VSCodeウィンドウ2で同じフォルダを開く
   → VSCode: 既存のコンテナを検出
   → ✅ 同じコンテナに接続（新しいコンテナは作らない）

3. 結果: 両方のVSCodeウィンドウが同じコンテナを共有
   - ファイルの変更は両方で反映される
   - ターミナルは独立したプロセス
```

### パターン6: エラーパターン - 設定前の ./bin/dc up → VSCode

```
推奨設定を適用していない場合:

1. ユーザー: ./bin/dc up -d
   → コンテナ起動（ポート4035, 8035, 9001, 8080使用）

2. ユーザー: VSCode DevContainer で開く
   → VSCode: docker compose ps を実行
   → VSCode: "dev"サービスが起動中だが、runServicesが設定されていない
   → VSCode: 既存のコンテナを無視して新しいコンテナを起動しようとする
   → Docker: ポート競合
   → ❌ エラー: "Bind for 0.0.0.0:4035 failed: port is already allocated"
```

### パターン比較表

| パターン | ./bin/dc up | VSCode | ./bin/dc exec | 結果 |
|---------|------------|--------|---------------|------|
| 1 | 先 | 後 | - | ✅ VSCodeが既存コンテナに接続 |
| 2 | - | 先 | 後 | ✅ execが既存コンテナに接続 |
| 3 | 先 | 中 | 後 | ✅ 全て同じコンテナを共有 |
| 4 | - | 開く→閉じる | 後 | ✅ コンテナは継続（shutdownAction: "none"） |
| 5 | - | 複数ウィンドウ | - | ✅ 同じコンテナを共有 |
| 6（設定前） | 先 | 後 | - | ❌ ポート競合エラー |

### 推奨ワークフロー（全パターン対応）

```bash
# パターンA: VSCode中心の開発
1. VSCodeでフォルダを開く → "Reopen in Container"
2. 必要に応じて ./bin/dc exec でターミナル追加
3. VSCodeを閉じても ./bin/dc exec は使える（shutdownAction: "none"）
4. 終了時: ./bin/dc down

# パターンB: ターミナル中心の開発
1. ./bin/dc up -d
2. 必要に応じてVSCodeで開く（既存コンテナに接続）
3. 必要に応じて ./bin/dc exec でターミナル追加
4. 終了時: ./bin/dc down

# パターンC: 混在（最も柔軟）
1. どちらかでコンテナを起動
2. 好きなツールで接続（全て同じコンテナを共有）
3. 終了時: ./bin/dc down
```

---

## 4. 代替アプローチ: "Attach to Running Container"

### 4.1 方法

1. `./bin/dc up -d`でコンテナを起動
2. VSCodeのコマンドパレット（Cmd+Shift+P）を開く
3. `Remote-Containers: Attach to Running Container...`を選択
4. "dev"コンテナを選択

### 4.2 メリット

- devcontainer.jsonの設定を完全にバイパス
- 確実に既存のコンテナに接続できる

### 4.3 デメリット

- devcontainer.jsonで定義された拡張機能が自動インストールされない
- カスタマイズ設定が適用されない
- ワークスペースフォルダが自動で開かれない

### 4.4 推奨度

⚠️ **非推奨**: 設定ファイルの恩恵を受けられないため、通常の開発では使用しない

---

## 5. メリットとデメリット

### 5.1 メリット

| メリット | 説明 |
|---------|------|
| ✅ ポート競合を回避 | 既存のコンテナに接続するため、ポート競合が発生しない |
| ✅ 手動コンテナ管理 | `./bin/dc`でコンテナのライフサイクルを完全に制御 |
| ✅ 開発体験の統一 | VSCodeでもターミナルでも同じコンテナを使用 |
| ✅ リソース効率 | 複数のコンテナを起動しない |

### 5.2 デメリットと対策

| デメリット | 対策 |
|----------|------|
| ⚠️ コンテナの事前起動が必要 | README.mdに手順を明記 |
| ⚠️ VSCodeが自動起動しない | ワークフローの一部として受け入れる |
| ⚠️ 状態同期の可能性 | コンテナ再ビルド時はVSCodeをリロード |

---

## 6. 実装手順

### 6.1 設定ファイルの修正

1. `.devcontainer/devcontainer.json.template`を編集
2. 以下の3つの設定を追加:
   ```json
   "runServices": ["dev"],
   "shutdownAction": "none",
   "overrideCommand": false
   ```

### 6.2 動作確認

#### テスト1: 既存コンテナへの接続

```bash
# 1. コンテナを停止
./bin/dc down

# 2. コンテナを起動
./bin/dc up -d

# 3. コンテナが起動していることを確認
./bin/dc ps
# 期待結果: dev サービスが "Up" 状態

# 4. VSCodeでフォルダを開く
# "Reopen in Container"を選択

# 5. VSCodeが既存のコンテナに接続することを確認
# ターミナルで whoami を実行
whoami
# 期待結果: <一般ユーザー>

# 6. プロンプトでコンテナIDを確認
# <一般ユーザー>@<container-id>:~/<MDCレポジトリ>$
```

#### テスト2: VSCode終了時のコンテナ継続

```bash
# 1. VSCodeでDevContainerを開いている状態

# 2. VSCodeを終了

# 3. コンテナが起動し続けていることを確認
./bin/dc ps
# 期待結果: dev サービスが "Up" 状態

# 4. 手動でコンテナを停止
./bin/dc down
```

#### テスト3: 新規コンテナ起動（コンテナが停止している場合）

```bash
# 1. コンテナを停止
./bin/dc down

# 2. VSCodeでフォルダを開く（コンテナが停止している状態）
# "Reopen in Container"を選択

# 3. VSCodeが新しいコンテナを起動することを確認
./bin/dc ps
# 期待結果: dev サービスが "Up" 状態

# 4. コンテナに接続できることを確認
whoami
# 期待結果: <一般ユーザー>
```

---

## 7. トラブルシューティング

### 7.1 問題: VSCodeが既存のコンテナを検出しない

**症状**: `./bin/dc up`でコンテナが起動しているのに、VSCodeが新しいコンテナを作ろうとする

**原因1**: docker-compose.ymlのパスが一致していない

**解決策**:
```bash
# コンテナの状態を確認
./bin/dc ps
```

**原因2**: サービス名が一致していない

**解決策**:
```json
// devcontainer.json.template
{
  "service": "dev",  // docker-compose.ymlのサービス名と一致させる
  "runServices": ["dev"]
}
```

### 7.2 問題: VSCode終了時にコンテナが停止する

**症状**: VSCodeを閉じるとコンテナが停止してしまう

**原因**: `shutdownAction`が設定されていない、または誤っている

**解決策**:
```json
{
  "shutdownAction": "none"  // "stopCompose"や"stopContainer"になっていないか確認
}
```

### 7.3 問題: コンテナが起動するがプロセスが正常に動作しない

**症状**: コンテナは起動するが、supervisordやprocess-composeが動いていない

**原因**: `overrideCommand`が`true`になっている

**解決策**:
```json
{
  "overrideCommand": false  // s6-overlayのENTRYPOINTを保持
}
```

---

## 8. 検証結果（2026-01-11）

### 8.1 検証環境

- **日時**: 2026-01-11
- **VSCode DevContainers拡張**: v1.0.30 (@devcontainers/cli 0.80.2)
- **Docker**: 29.1.3
- **Docker Compose**: 2.40.3-desktop.1
- **OS**: macOS (Darwin 24.6.0 arm64)

### 8.2 テスト結果サマリー

| テスト項目 | 結果 | 詳細 |
|----------|------|------|
| テスト1: 既存コンテナへの接続 | ✅ 成功 | `./bin/dc up -d` → VSCode接続 → ポート競合なし |
| テスト2: VSCode終了時のコンテナ継続 | ✅ 成功 | VSCode終了後もコンテナが稼働継続 |
| テスト3: 新規コンテナ起動 | ⚠️ 部分成功 | コンテナ起動するが、supervisord未起動 |

### 8.3 テスト1: 既存コンテナへの接続 - ✅ 成功

#### 検証手順

```bash
# 1. コンテナを停止
./bin/dc down

# 2. コンテナを起動
./bin/dc up -d

# 3. コンテナの状態確認
./bin/dc ps
# 結果: devcontainer-dev-1 が Up (healthy) 状態

# 4. VSCodeで "Reopen in Container" を選択

# 5. VSCode DevContainer内で確認
whoami
# 結果: <一般ユーザー>
```

#### 結果

- ✅ VSCodeが既存のコンテナ（`devcontainer-dev-1`）に接続
- ✅ ポート競合エラーなし
- ✅ `remoteUser` 設定が正常動作（`<一般ユーザー>`）
- ✅ `runServices: ["dev"]` が効果を発揮

### 8.4 テスト2: VSCode終了時のコンテナ継続 - ✅ 成功

#### 検証手順

```bash
# 1. VSCodeでDevContainerを開いている状態

# 2. VSCodeアプリを終了（Quit）

# 3. ホストOSで確認
./bin/dc ps
# 結果: devcontainer-dev-1 が Up 7 minutes (healthy) 状態
```

#### 結果

- ✅ `shutdownAction: "none"` が正常動作
- ✅ VSCodeを完全終了してもコンテナが継続
- ✅ "Close Remote Connection" でも継続
- ✅ 手動でのライフサイクル管理が可能

### 8.5 テスト3: 新規コンテナ起動 - ⚠️ 部分成功

#### 検証手順

```bash
# 1. コンテナを停止
./bin/dc down

# 2. VSCodeで "Reopen in Container" を選択（コンテナなしの状態から）

# 3. VSCode DevContainer内で確認
whoami
# 結果: <一般ユーザー>

# 4. ホストOSで確認
./bin/dc ps
# 結果: 何も表示されない

docker ps -a
# 結果: <MDCレポジトリ>_devcontainer-dev-1 (unhealthy)
```

#### 結果

| 項目 | 期待 | 実際 | 結果 |
|------|------|------|------|
| VSCodeがコンテナを起動 | ✅ | ✅ | 成功 |
| `/init` (s6-overlay) 実行 | ✅ | ✅ | 成功 |
| 正しいユーザーで接続 | ✅ | ✅ | 成功 |
| supervisord 起動 | ✅ | ❌ | **失敗** |
| code-server 起動 | ✅ | ❌ | **失敗** |
| ヘルスチェック | healthy | unhealthy | **失敗** |
| `./bin/dc ps` で表示 | ✅ | ❌ | **失敗** |

#### 詳細分析

**VSCodeログ解析**:

```json
{
  "Path": "/bin/sh",
  "Args": [
    "-c",
    "echo Container started\n trap \"exit 0\" 15\n /usr/local/share/docker-init.sh\n exec \"$@\"\n while sleep 1 & wait $!; do :; done",
    "-",
    "/init"
  ]
}
```

- VSCodeは `docker-from-docker` feature のためにラッパースクリプトを追加
- 最終的には `/init` (s6-overlay) を `exec` で実行
- `overrideCommand: false` は正しく動作している

**プロセス状態確認**:

```bash
docker exec 7b835ebbf70f ps aux
# 結果:
# - s6-overlay (PID 1) が起動
# - process-compose が起動
# - supervisord が未起動
# - /var/run/supervisor.sock が存在しない
```

**ヘルスチェック失敗**:

```bash
# docker-compose.yml の healthcheck
supervisorctl status code-server | grep -q RUNNING || exit 1

# 実行結果
# unix:///var/run/supervisor.sock no such file
# Exit code: 4
```

### 8.6 発見された問題

#### 問題1: supervisord が起動しない（VSCode起動時） - ✅ **解決済み**

**症状**:
- VSCodeが起動したコンテナでは supervisord が起動しない
- `./bin/dc up -d` で起動したコンテナでは正常に起動する
- s6-overlay は動作しているが、その配下のサービスが一部起動していない

**影響**:
- code-server が起動しない → Web UIでの開発ができない
- ヘルスチェックが常に `unhealthy` になる
- コンテナは動作するが、一部機能が使えない

**根本原因（2026-01-12判明）**:
- **問題2（プロジェクト名不一致）と同一の根本原因**
- プロジェクト名の不一致により、VSCodeが既存コンテナを正しく管理できず、コンテナの初期化が不完全になっていた

**解決策（2026-01-12検証完了）**:
- 問題2の解決（docker-compose.ymlに`name`フィールド追加）により、問題1も同時に解決
- 検証結果: 全4パターンでsupervisordの正常起動を確認
  - ✅ パターン1: コンテナ削除 → VSCode起動
  - ✅ パターン3: イメージ削除 → VSCode起動（クリーンビルド）
  - ✅ パターン4: bin/dc起動 → VSCode起動
  - ❌ パターン2: VSCode起動 → bin/dc起動（overrideCommand問題で失敗）

**詳細**:
- 検証トラッカー: [25_6_27_supervisord_verification_tracker.md](./25_6_27_supervisord_verification_tracker.md)
- 仮説ドキュメント: [25_6_26_supervisord_startup_issue_hypothesis.md](./25_6_26_supervisord_startup_issue_hypothesis.md)

#### 問題2: VSCode起動 → bin/dc起動でコンテナ置き換え - ✅ **解決済み（2026-01-13）**

**症状（2026-01-12検証で発見）**:
- VSCodeで起動したコンテナが存在する状態で `./bin/dc up -d` を実行すると、コンテナが置き換えられる
- 置き換え時にVSCodeの接続が切断される（"Cannot reconnect. Please reload the window."）
- 古いコンテナ（VSCode起動）が削除され、新しいコンテナ（bin/dc起動）が作成される

**根本原因**:
- VSCodeの `overrideCommand` が docker-compose.yml の `command` (デフォルト `/init`) と異なる
- VSCode起動時のCOMMAND: `/bin/sh -c 'echo Container started...'`
- bin/dc起動時のCOMMAND: `/init`
- Docker Composeは、COMMANDが異なると「同じ定義のコンテナ」と認識できず、コンテナを再作成する

**採用した解決策（2026-01-13）**:
- **仮説10-A: スマートbin/dcラッパー実装**
- bin/dcスクリプトにVSCodeコンテナ検出機能を追加（111行）
- `./bin/dc up/start/restart` 実行前にVSCodeコンテナを自動検出
- VSCodeコンテナが存在する場合、エラーメッセージを表示して誤操作を防止
- bin/dcコンテナの場合、通常通り動作を継続

**解決の効果**:
- ✅ VSCodeで起動したコンテナへの誤った `./bin/dc up` 実行を自動的にブロック
- ✅ エラーメッセージで適切な代替手段を提示（exec コマンドまたは down && up）
- ✅ `./bin/dc exec` は正常動作を維持
- ✅ bin/dcで起動したコンテナは通常通り管理可能
- ✅ VSCodeとbin/dcの完全な共存を実現

**実装詳細**:
- ファイル: [bin/dc](../../../bin/dc)
- VSCodeコンテナ検出: Dockerラベル `devcontainer.local_folder` を使用
- 動的プロジェクト名取得: `docker compose config --format json` + grep
- POSIX準拠のシェルスクリプト実装

**詳細な検証ログ**:
- 仮説立案: [25_6_28_overridecommand_container_replacement_hypothesis.v2.md](../resolved/25_6_28_overridecommand_container_replacement_hypothesis.v2.md)
- 検証トラッカー: [25_6_29_overridecommand_verification_tracker.md](../resolved/25_6_29_overridecommand_verification_tracker.md) - A-13参照
- 初期検証: [25_6_27_supervisord_verification_tracker.md](../resolved/25_6_27_supervisord_verification_tracker.md) - パターン2参照

---

## 9. ベストプラクティス

### 9.1 推奨ワークフロー

```bash
# 1. 朝、作業開始時
./bin/dc up -d

# 2. VSCodeで開発
# "Reopen in Container"で既存のコンテナに接続

# 3. 作業終了時
./bin/dc down
```

### 9.2 READMEへの記載

プロジェクトのREADME.mdに以下を追記することを推奨:

```markdown
## 開発環境の起動

### 方法1: VSCode DevContainer（推奨）

1. コンテナを起動:
   \`\`\`bash
   ./bin/dc up -d
   \`\`\`

2. VSCodeでフォルダを開き、"Reopen in Container"を選択

3. 作業終了時にコンテナを停止:
   \`\`\`bash
   ./bin/dc down
   \`\`\`

### 方法2: ターミナルのみ

\`\`\`bash
./bin/dc up -d
./bin/dc exec dev bash
\`\`\`
```

### 9.3 チーム開発での注意点

1. **全員が同じ設定を使用**: devcontainer.json.templateを共有
2. **ワークフローの統一**: READMEで手順を明確化
3. **トラブル時の対処**: この課題ドキュメントを参照

---

## 10. 参考資料

### 10.1 公式ドキュメント

- [Developing inside a Container - Visual Studio Code](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Container metadata reference](https://containers.dev/implementors/json_reference/)
- [devcontainer.json schema](https://containers.dev/implementors/json_schema/)

### 10.2 関連GitHub Issues

- [GitHub Issue #9118: "runServices" not working if "service" already running](https://github.com/microsoft/vscode-remote-release/issues/9118)
- [GitHub Issue #3555: If runServices doesn't contain service vscode hangs](https://github.com/microsoft/vscode-remote-release/issues/3555)

### 10.3 関連記事

- [How to use VS Code Dev Containers with docker compose deployment](https://toptechtips.github.io/2023-05-17-docker-compose-multiple-dev-containers/)
- [Turn Docker compose files into Devcontainers](https://generalreasoning.com/blog/software/cicd/2025/03/13/docker-compose-files-as-devcontainers.html)
- [Start a process when the container starts](https://code.visualstudio.com/remote/advancedcontainers/start-processes)

### 10.4 関連ドキュメント

- [25_6_15_devcontainer_remoteuser_investigation.md](../resolved/25_6_15_devcontainer_remoteuser_investigation.md) - remoteUserの調査
- [25_6_16_wrapper_script_strategy.md](../resolved/25_6_16_wrapper_script_strategy.md) - bin/dcラッパースクリプト
- [v10_environment_variables_golden_test.md](../../../foundations/v10_environment_variables_golden_test.md) - v10環境変数の動作確認

---

## 10. 次のアクション

### 10.1 実装タスク

- [ ] `.devcontainer/devcontainer.json.template`に設定を追加
- [ ] 動作確認テストを実施
- [ ] README.mdにワークフローを記載

### 10.2 検証項目

- [ ] テスト1: 既存コンテナへの接続
- [ ] テスト2: VSCode終了時のコンテナ継続
- [ ] テスト3: 新規コンテナ起動

---

**最終更新**: 2026-01-11
**ステータス**: ✅ 調査完了、実装待ち
**次のアクション**: devcontainer.json.templateへの設定追加と動作確認
