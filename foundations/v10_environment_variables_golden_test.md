# v10環境変数実装 ゴールデンテストケース

**作成日**: 2026-01-10
**ステータス**: ✅ 検証完了
**目的**: v10設計における環境変数実装（${UNAME}, ${REPO_NAME}）の動作を保証する標準テストケース

このドキュメントは、v10環境変数実装の正しい動作を検証するためのゴールデンテストケースです。新しい変更を加えた際や、環境を再構築した際には、必ずこのテストケースを実行してください。

**関連ドキュメント**:
- [14_詳細設計_ディレクトリ構成.v12.md](../initiatives/20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v12.md) - v10設計の全体像

---

## テストケース概要

| 項目 | 内容 |
|------|------|
| テスト対象 | v10環境変数実装（${UNAME}, ${REPO_NAME}） |
| 検証範囲 | ビルド、起動、プロセス管理、環境変数展開、ログ出力 |
| 実行時間 | 約30-40分（ビルド時間含む） |
| 前提条件 | Docker、docker compose がインストール済み |

---

## 検証項目サマリー

| セクション | 項目数 | 所要時間 |
|-----------|--------|---------|
| 1. ビルドと起動 | 3 | 約15-20分 |
| 2. 基本動作確認 | 3 | 約5分 |
| 3. supervisord設定確認 | 4 | 約5分 |
| 4. process-compose設定確認 | 2 | 約3分 |
| 5. 環境変数展開の確認 | 4 | 約3分 |
| 6. ログ確認 | 3 | 約2分 |
| **合計** | **21** | **約30-40分** |

---

## 1. ビルドと起動

### 1-1: コンテナ停止・削除

```bash
# リポジトリルートから実行
cd .devcontainer
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml down
cd ..
```

**期待結果**: エラーなくコンテナが停止・削除される

**確認項目**:
- [ ] コンテナが停止・削除される
- [ ] エラーメッセージが表示されない

---

### 1-2: Docker システムクリーンアップとキャッシュなしビルド

```bash
# 未使用リソースのクリーンアップ（オプション）
docker system prune -f

# .devcontainer ディレクトリに移動してビルド
cd .devcontainer
docker compose --progress plain -f docker-compose.yml -f docker-compose.dev-vm.yml build --no-cache
cd ..
```

**期待結果**: エラーなくビルドが完了する

**確認項目**:
- [ ] Dockerfileのすべてのステップが成功
- [ ] s6-overlayのインストールが成功
- [ ] s6-rc サービス定義のコピーが成功
- [ ] run スクリプトに実行権限が付与される（`chmod +x`）
- [ ] ビルドエラーが発生しない

---

### 1-3: コンテナ起動

```bash
# コンテナを起動
cd .devcontainer
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml up -d
cd ..

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
docker exec devcontainer-dev-1 ps aux | head -n 10
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

echo $REPO_NAME
# 期待結果: <MonolithicDevContainerレポジトリ名>

# ログアウト
exit
```

**確認項目**:
- [ ] `whoami` が一般ユーザー名と一致
- [ ] `pwd` が `/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>` と一致
- [ ] 環境変数 `UNAME` と `REPO_NAME` が正しく設定されている
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
docker exec devcontainer-dev-1 ps aux | grep code-server
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
docker exec devcontainer-dev-1 ps aux | grep process-compose
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
docker exec devcontainer-dev-1 ps aux | grep "tail -f"
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
cat /etc/supervisor/conf.d/seed.conf | grep -E "user=|HOME="
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

### 5-2: supervisord.conf の確認

```bash
./bin/dc exec dev /bin/bash
cat /etc/supervisor/supervisord.conf | grep -E "user=|HOME="
exit
```

**期待結果**:
```
user=%(ENV_UNAME)s
environment=HOME="/home/%(ENV_UNAME)s"
user=%(ENV_UNAME)s
environment=HOME="/home/%(ENV_UNAME)s"
```

**確認項目**:
- [ ] `user=%(ENV_UNAME)s` が確認できる（2箇所）
- [ ] `HOME="/home/%(ENV_UNAME)s"` が確認できる（2箇所）

---

### 5-3: project.conf の確認（スキップ）

**注記**: v10実装では `project.conf` は存在しません。プロジェクト固有のプロセス管理には process-compose を使用します。このセクションはスキップしてください。

---

### 5-4: project.yaml の確認

```bash
./bin/dc exec dev /bin/bash
cat /etc/process-compose/project.yaml | grep -E "working_dir:|HOME="
exit
```

**期待結果**:
```
    working_dir: "/home/${UNAME}/${REPO_NAME}"
      - HOME=/home/${UNAME}
```

**確認項目**:
- [ ] `working_dir: "/home/${UNAME}/${REPO_NAME}"` が確認できる
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
docker exec devcontainer-dev-1 cat /var/log/supervisor/code-server.log
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
docker exec devcontainer-dev-1 cat /var/log/supervisor/process-compose.log
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

## 9. 履歴

| 日付 | バージョン | 変更内容 |
|------|----------|---------|
| 2026-01-10 | 1.0 | 初版作成（検証手順から抽出してゴールデンテスト化） |

---

**最終更新**: 2026-01-10
**ステータス**: ✅ ゴールデンテストケースとして確立
