# v10設計 ゴールデンテストケース

**作成日**: 2026-01-10
**ステータス**: ✅ 検証完了
**目的**: v10設計における各種実装の動作を保証する標準テストケース集

このドキュメントは、v10設計の重要な実装について、正しい動作を検証するためのゴールデンテストケース集です。新しい変更を加えた際や、環境を再構築した際には、必ずこれらのテストケースを実行してください。

**関連ドキュメント**:
- [14_詳細設計_ディレクトリ構成.v12.md](../initiatives/20251229--dev-hub-concept/decisions/14_詳細設計_ディレクトリ構成.v12.md) - v10設計の全体像

---

## 目次

1. [v10環境変数実装テスト](#1-v10環境変数実装テスト)
2. [bin/dcスマートラッパーテスト](#2-bindcスマートラッパーテスト)

---

## 1. v10環境変数実装テスト

### テストケース概要

| 項目 | 内容 |
|------|------|
| テスト対象 | v10環境変数実装（${UNAME}, ${MDC_REPO_ROOT}） |
| 検証範囲 | ビルド、起動、プロセス管理、環境変数展開、ログ出力 |
| 実行時間 | 約30-40分（ビルド時間含む） |
| 前提条件 | Docker、docker compose がインストール済み |

---

### 検証項目サマリー

| セクション | 項目数 | 所要時間 |
|-----------|--------|---------|
| 1-1. ビルドと起動 | 4 | 約15-20分 |
| 1-2. 基本動作確認 | 3 | 約5分 |
| 1-3. supervisord設定確認 | 4 | 約5分 |
| 1-4. process-compose設定確認 | 2 | 約3分 |
| 1-5. 環境変数展開の確認 | 4 | 約3分 |
| 1-6. ログ確認 | 3 | 約2分 |
| **合計** | **22** | **約30-40分** |

---

### 1-1. ビルドと起動

#### 1-1-1: コンテナ停止・削除

```bash
# リポジトリルートから実行
./bin/dc down
```

**期待結果**: エラーなくコンテナが停止・削除される

**確認項目**:
- [ ] コンテナが停止・削除される
- [ ] エラーメッセージが表示されない

---

### 1-2: セットアップスクリプトの実行

**重要**: ビルド前に必ず実行が必要です

```bash
# リポジトリルートから実行
.devcontainer/setup.sh
.devcontainer/generate-env.sh
```

**期待結果**:
- `setup.sh`: `.devcontainer/devcontainer.json` が生成される
- `generate-env.sh`: `.devcontainer/.env` が生成される

**確認項目**:
- [ ] `.devcontainer/devcontainer.json` が生成される
- [ ] `.devcontainer/.env` が生成される
- [ ] `.env` に `MDC_REPO_ROOT` が設定されている
- [ ] スクリプト実行時にエラーが発生しない

**生成ファイルの確認**:
```bash
# devcontainer.json の確認
cat .devcontainer/devcontainer.json | grep workspaceFolder
# 期待結果: "workspaceFolder": "/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>"

# .env の確認
cat .devcontainer/.env | grep MDC_REPO_ROOT
# 期待結果: MDC_REPO_ROOT="<MonolithicDevContainerレポジトリ名>"
```

---

### 1-3: Docker システムクリーンアップとキャッシュなしビルド

```bash
# 未使用リソースのクリーンアップ（オプション）
docker system prune -f

# キャッシュなしビルド
./bin/dc build --progress plain --no-cache
```

**期待結果**: エラーなくビルドが完了する

**確認項目**:
- [ ] Dockerfileのすべてのステップが成功
- [ ] s6-overlayのインストールが成功
- [ ] s6-rc サービス定義のコピーが成功
- [ ] run スクリプトに実行権限が付与される（`chmod +x`）
- [ ] ビルドエラーが発生しない

---

### 1-4: コンテナ起動

```bash
# コンテナを起動
./bin/dc up -d

# コンテナステータス確認
docker ps

# コンテナログで起動エラーがないか確認
docker logs devcontainer-dev-1 2>&1 | tail -30
```

**期待結果**:
- コンテナが起動し、STATUSが `Up` または `healthy` になる
- ログにs6-overlayの起動メッセージが確認できる
- 致命的なエラーがない

**確認項目**:
- [ ] コンテナが `Up` 状態になる
- [ ] s6-overlayが正常に起動している
- [ ] 起動ログに致命的なエラーがない

---

## 2. 基本動作確認

### 2-1: PID 1 確認

```bash
./bin/dc exec dev ps aux | head -n 10
```

**期待結果**:
```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0    428    96 ?        Ss   XX:XX   0:00 /package/admin/s6/command/s6-svscan -d4 -- /run/service
```

**確認項目**:
- [ ] PID 1が `s6-svscan` である
- [ ] USERが `root` である
- [ ] v10設計通りに動作している

---

### 2-2: 一般ユーザーログイン確認

```bash
./bin/dc exec dev /bin/bash
```

**コンテナ内で以下を確認**:

```bash
# ユーザー名確認
whoami
# 期待結果: 一般ユーザー名

# カレントディレクトリ確認
pwd
# 期待結果: /home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>

# 環境変数確認
echo $UNAME
# 期待結果: 一般ユーザー名

echo $MDC_REPO_ROOT
# 期待結果: <MonolithicDevContainerレポジトリ名>

# ログアウト
exit
```

**確認項目**:
- [ ] `whoami` が一般ユーザー名と一致
- [ ] `pwd` が `/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>` と一致
- [ ] 環境変数 `UNAME` と `MDC_REPO_ROOT` が正しく設定されている
- [ ] ログイン時にエラーがない

---

### 2-3: rootユーザーログイン確認

```bash
./bin/dc exec -u root dev /bin/bash
```

**コンテナ内で以下を確認**:

```bash
# ユーザー名確認
whoami
# 期待結果: root

# .bashrc の内容確認（Atuin無条件初期化行がないことを確認）
grep -n "atuin" /root/.bashrc
# 期待結果: 出力なし（または .bashrc_custom からの条件付き初期化のみ）

# ログアウト
exit
```

**期待結果**: Atuinエラー（`bash: /root/.atuin/bin/env: No such file or directory`）が出ない

**確認項目**:
- [ ] `whoami` が `root`
- [ ] Atuinエラーが出ない
- [ ] `/root/.bashrc` に無条件のAtuin初期化行がない

---

## 3. supervisord設定確認

### 3-1, 3-2: 構文チェック（スキップ推奨）

**注記**: `supervisord -c <config> -t` はテストプロセスを起動するため、プロセスが残留します。セクション3-3、3-4で動作確認を行うため、このセクションはスキップ推奨です。

---

### 3-3: code-server プロセス確認

```bash
./bin/dc exec dev ps aux | grep code-server
```

**期待結果**:
```
<一般ユーザー>  XXXX  ... /usr/lib/code-server/lib/node /usr/lib/code-server --bind-addr 0.0.0.0:4035
```

**確認項目**:
- [ ] USERが一般ユーザー名である
- [ ] code-serverが起動している
- [ ] ポート4035でリッスンしている

---

### 3-4: code-server 動作確認

```bash
curl -I http://localhost:4035
```

**期待結果**:
```
HTTP/1.1 302 Found
Location: ./login
```
または
```
HTTP/1.1 200 OK
```

**確認項目**:
- [ ] HTTPステータスコードが200または302
- [ ] code-serverが正常に応答している

---

## 4. process-compose設定確認

### 4-1: process-compose プロセス確認

```bash
./bin/dc exec dev ps aux | grep process-compose
```

**期待結果**:
```
root  XXXX  ... /usr/local/bin/process-compose -t=false -f /etc/process-compose/process-compose.yaml
```

**確認項目**:
- [ ] process-composeが起動している
- [ ] `-t=false` フラグが設定されている（TUI無効化）
- [ ] 設定ファイルパスが正しい

---

### 4-2: dummy-watcher プロセス確認

```bash
./bin/dc exec dev ps aux | grep "tail -f"
```

**期待結果**:
```
root  XXXX  ... tail -f /dev/null
```

**確認項目**:
- [ ] dummy-watcherプロセス（`tail -f /dev/null`）が起動している
- [ ] プロセスが正常に動作している

---

## 5. 環境変数展開の確認

### 5-1: seed.conf の確認

```bash
./bin/dc exec dev /bin/bash
cat /etc/supervisor/seed.conf | grep -E "user=|directory=|HOME="
exit
```

**期待結果**:
```
user=root                                    ; supervisord自体はrootで起動
user=%(ENV_UNAME)s                          ; code-serverは一般ユーザーで起動
environment=CODE_SERVER_PORT="4035",HOME="/home/%(ENV_UNAME)s"
```

**確認項目**:
- [ ] `user=%(ENV_UNAME)s` が確認できる
- [ ] `HOME="/home/%(ENV_UNAME)s"` が確認できる

---

### 5-2: project.conf の確認

**注記**: `/etc/supervisor/supervisord.conf` は `workloads/supervisord/project.conf` へのシンボリックリンクです。

```bash
./bin/dc exec dev /bin/bash
cat /etc/supervisor/supervisord.conf | grep -E "user=|directory=|HOME="
exit
```

**期待結果**:
```
user=%(ENV_UNAME)s
directory=/home/%(ENV_UNAME)s/%(ENV_MDC_REPO_ROOT)s
environment=CODE_SERVER_PORT="4035",HOME="/home/%(ENV_UNAME)s"
```

**確認項目**:
- [ ] `user=%(ENV_UNAME)s` が確認できる
- [ ] `directory=/home/%(ENV_UNAME)s/%(ENV_MDC_REPO_ROOT)s` が確認できる
- [ ] `HOME="/home/%(ENV_UNAME)s"` が確認できる

---

### 5-3: project.yaml の確認

**注記**: `/etc/process-compose/process-compose.yaml` は `workloads/process-compose/project.yaml` へのシンボリックリンクです。

```bash
./bin/dc exec dev /bin/bash
cat /etc/process-compose/process-compose.yaml | grep -E "working_dir:|HOME="
exit
```

**期待結果**:
```
    working_dir: "/home/${UNAME}/${MDC_REPO_ROOT}"
      - HOME=/home/${UNAME}
```

**確認項目**:
- [ ] `working_dir: "/home/${UNAME}/${MDC_REPO_ROOT}"` が確認できる
- [ ] `HOME=/home/${UNAME}` が確認できる

---

## 6. ログ確認

### 6-1: コンテナログ確認

```bash
docker logs devcontainer-dev-1 2>&1 | grep -i error
```

**期待結果**: 致命的なエラーがない

**許容されるメッセージ**:
- process-composeのデバッグメッセージ（`{"level":"debug","error":"could not locate process-compose...`）
  - これは設定ファイル探索のデバッグログで、`-f` フラグで明示的に指定しているため影響なし

**確認項目**:
- [ ] 致命的なエラーメッセージがない
- [ ] s6-overlayの起動ログが正常

---

### 6-2: supervisord ログ確認（code-server）

```bash
./bin/dc exec dev cat /var/log/supervisor/code-server.log
```

**期待結果**:
```
cat: /var/log/supervisor/code-server.log: No such file or directory
```

**これは正常です**。v10設計では、supervisordはstdout/stderrにログを出力し、`docker logs` で確認できるようになっています。

**確認項目**:
- [ ] ログファイルが存在しない（v10設計通り）
- [ ] code-serverの動作は既にセクション3-3、3-4で確認済み

---

### 6-3: supervisord ログ確認（process-compose）

```bash
./bin/dc exec dev cat /var/log/supervisor/process-compose.log
```

**期待結果**:
```
cat: /var/log/supervisor/process-compose.log: No such file or directory
```

**これは正常です**。v10設計では、process-composeはs6-overlayで直接管理されており、supervisordの管理下にはありません。

**確認項目**:
- [ ] ログファイルが存在しない（v10設計通り）
- [ ] process-composeの動作は既にセクション4-1、4-2で確認済み

---

## 7. 検証結果サマリー

### 検証項目チェックリスト

| セクション | 項目 | 実施 | 備考 |
| :--- | :--- | :---: | :--- |
| **1. ビルドと起動** | 1-1: コンテナ停止・削除 | ☐ | |
| | 1-2: キャッシュなしでビルド | ☐ | |
| | 1-3: コンテナ起動 | ☐ | |
| **2. 基本動作確認** | 2-1: PID 1 確認 | ☐ | |
| | 2-2: 一般ユーザーログイン確認 | ☐ | |
| | 2-3: root ユーザーログイン確認 | ☐ | |
| **3. supervisord 設定確認** | 3-1, 3-2: 構文チェック | ⏭️ | スキップ推奨 |
| | 3-3: code-server プロセス確認 | ☐ | |
| | 3-4: code-server 動作確認 | ☐ | |
| **4. process-compose 設定確認** | 4-1: process-compose プロセス確認 | ☐ | |
| | 4-2: dummy-watcher プロセス確認 | ☐ | |
| **5. 環境変数展開の確認** | 5-1: seed.conf の確認 | ☐ | |
| | 5-2: supervisord.conf の確認 | ☐ | |
| | 5-3: project.conf の確認 | ⏭️ | スキップ（v10に存在せず） |
| | 5-4: project.yaml の確認 | ☐ | |
| **6. ログ確認** | 6-1: コンテナログ確認 | ☐ | |
| | 6-2: supervisord ログ確認（code-server） | ☐ | |
| | 6-3: supervisord ログ確認（process-compose） | ☐ | |

### 検証完了時の記入事項

**検証実施日時**: ____年__月__日

**検証者**: ________________

**全体結果**: ☐ 合格 / ☐ 不合格

**備考**:
-
-
-

---

## 8. トラブルシューティング

### よくある問題と解決方法

#### 問題1: process-composeが起動しない

**症状**: `ps aux | grep process-compose` で s6-supervise のみ表示される

**原因**: runスクリプトに実行権限がない

**解決方法**:
1. [.devcontainer/Dockerfile:118](.devcontainer/Dockerfile#L118) 付近に以下が存在するか確認:
   ```dockerfile
   RUN find /etc/s6-overlay/s6-rc.d -type f -name 'run' -exec chmod +x {} \;
   ```
2. 存在しない場合は追加して再ビルド

#### 問題2: process-composeがTUIエラーで再起動ループ

**症状**: `docker logs` に `FTL TUI startup error error="open /dev/tty: no such device or address"` が繰り返し表示される

**原因**: TUIモードがs6-overlay環境で動作しない

**解決方法**:
1. [.devcontainer/s6-rc.d/process-compose/run](.devcontainer/s6-rc.d/process-compose/run) に `-t=false` フラグが設定されているか確認:
   ```bash
   exec /usr/local/bin/process-compose -t=false -f /etc/process-compose/process-compose.yaml
   ```
2. 設定されていない場合は追加して再ビルド

#### 問題3: Atuinエラーが発生する（rootログイン時）

**症状**: `bash: /root/.atuin/bin/env: No such file or directory`

**原因**: `/root/.bashrc` に無条件のAtuin初期化行が存在する

**解決方法**:
1. [.devcontainer/Dockerfile](.devcontainer/Dockerfile) で `/root/.bashrc` の置き換えが正しく行われているか確認
2. `.bashrc_custom` の条件付き初期化のみが使用されるようにする

---

---

## 2. bin/dcスマートラッパーテスト

### テストケース概要

| 項目 | 内容 |
|------|------|
| テスト対象 | bin/dcスマートラッパー（VSCodeコンテナ検出機能） |
| 検証範囲 | VSCodeコンテナ検出、エラーメッセージ表示、bin/dcコンテナ管理 |
| 実行時間 | 約10分 |
| 前提条件 | Docker、docker compose、VSCode DevContainers拡張 |

---

### 検証項目サマリー

| セクション | 項目数 | 所要時間 |
|-----------|--------|---------|
| 2-1. VSCodeコンテナ検出 | 2 | 約3分 |
| 2-2. bin/dcコンテナ管理 | 2 | 約3分 |
| 2-3. execコマンド動作 | 1 | 約2分 |
| **合計** | **5** | **約10分** |

---

### 2-1. VSCodeコンテナ検出

#### 2-1-1: VSCodeコンテナ起動とラベル確認

```bash
# 1. VSCodeでコンテナ起動
# VSCode → "Reopen in Container"

# 2. コンテナとラベルを確認
docker ps --filter "name=<docker-composeプロジェクト名>-dev" --format "{{.ID}}\t{{.Command}}"
docker inspect <docker-composeプロジェクト名>-dev-1 --format '{{index .Config.Labels "devcontainer.local_folder"}}'
```

**期待結果**:
- コンテナのCOMMAND: `/bin/sh -c 'echo Co…'`
- ラベル値: `/Users/<一般ユーザー>/repos/<MDCレポジトリ>`（リポジトリパス）

#### 2-1-2: VSCodeコンテナへのbin/dc up実行とエラー確認

```bash
# VSCodeコンテナが起動している状態で実行
./bin/dc up -d
```

**期待結果**:
```
❌ エラー: VSCodeで起動されたコンテナが既に存在します

VSCodeで起動したコンテナに対して './bin/dc up' を実行すると、
コンテナが再作成され、VSCodeの接続が切断されます。

以下のいずれかを選択してください:
  1. コンテナ内でコマンドを実行: ./bin/dc exec dev bash
  2. コンテナを削除して再起動: ./bin/dc down && ./bin/dc up -d
```

**確認項目**:
- ✅ エラーメッセージが表示される
- ✅ コンテナが再作成されない（コンテナIDが変わらない）
- ✅ VSCodeの接続が維持される

---

### 2-2. bin/dcコンテナ管理

#### 2-2-1: bin/dcでコンテナ起動

```bash
# 1. VSCodeコンテナを削除
./bin/dc down

# 2. bin/dcでコンテナ起動
./bin/dc up -d
```

**期待結果**:
- コンテナが正常に起動する
- コンテナのCOMMAND: `/init`

#### 2-2-2: bin/dcコンテナへの連続up実行

```bash
# bin/dcコンテナが起動している状態で実行
./bin/dc up -d
```

**期待結果**:
```
[+] Running 1/1
 ✔ Container <docker-composeプロジェクト名>-dev-1  Running
```

**確認項目**:
- ✅ エラーメッセージが表示されない
- ✅ コンテナが再作成されない
- ✅ "Running"と表示される

---

### 2-3. execコマンド動作

#### 2-3-1: VSCodeコンテナへのexec実行

```bash
# VSCodeコンテナが起動している状態で実行
./bin/dc exec dev bash -c "echo 'Hello from VSCode container'"
```

**期待結果**:
```
Hello from VSCode container
```

**確認項目**:
- ✅ execコマンドが正常に実行される
- ✅ エラーが発生しない

---

### 実装詳細

#### VSCodeコンテナ検出ロジック

bin/dcスクリプト（[bin/dc](../bin/dc)）は以下のロジックでVSCodeコンテナを検出します：

1. **動的プロジェクト名取得**:
   ```bash
   project_name=$(docker compose config --format json 2>/dev/null | grep -o '"name": "[^"]*"' | head -1 | cut -d'"' -f4)
   ```
   - `docker compose config --format json`でプロジェクト設定をJSON形式で取得
   - `compose-spec/compose-go`の`MarshalJSON()`実装により、`"name"`フィールドが最初に出力されることが保証される
   - 技術的根拠: [compose-spec/compose-go types/project.go#L648-L671](https://github.com/compose-spec/compose-go/blob/8c75dbf7f75b23d1fff41b56fbd80c6ad0916e4a/types/project.go#L648-L671)

2. **VSCodeラベル検出**:
   ```bash
   vscode_label=$(docker inspect "$container_id" --format='{{index .Config.Labels "devcontainer.local_folder"}}' 2>/dev/null)
   ```
   - VSCode DevContainerが自動的に付与する`devcontainer.local_folder`ラベルを確認
   - このラベルが存在する場合、VSCodeが起動したコンテナと判定

3. **コマンド前の検証**:
   ```bash
   case "${1:-}" in
       up|start|restart)
           if check_vscode_container; then
               # エラーメッセージを表示して終了
               exit 1
           fi
           ;;
   esac
   ```

#### POSIX準拠

- bash固有の`[[`や`=~`を使用せず、POSIX準拠の`case`文を使用
- 最大限の互換性を確保

**関連ドキュメント**:
- 仮説立案: [25_6_28_overridecommand_container_replacement_hypothesis.v2.md](../initiatives/20251229--dev-hub-concept/resolved/25_6_28_overridecommand_container_replacement_hypothesis.v2.md)
- 検証トラッカー: [25_6_29_overridecommand_verification_tracker.md](../initiatives/20251229--dev-hub-concept/resolved/25_6_29_overridecommand_verification_tracker.md)

---

## 9. 履歴

| 日付 | バージョン | 変更内容 |
|------|----------|---------|
| 2026-01-10 | 1.0 | 初版作成（検証手順から抽出してゴールデンテスト化） |
| 2026-01-11 | 1.1 | セットアップスクリプト実行手順追加、ファイルパス修正、`./bin/dc`ラッパー適用、関連ドキュメントパス修正 |
| 2026-01-13 | 2.0 | ファイル名変更（v10_design_golden_tests.md）、bin/dcスマートラッパーテストセクション追加 |

---

**最終更新**: 2026-01-13
**ステータス**: ✅ ゴールデンテストケースとして確立
