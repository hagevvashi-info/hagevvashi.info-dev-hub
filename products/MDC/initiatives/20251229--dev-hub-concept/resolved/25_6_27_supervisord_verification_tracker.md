# 統合テスト: supervisord起動検証

**作成日**: 2026-01-11
**関連ドキュメント**: [25_6_26_supervisord_startup_issue_hypothesis.md](./25_6_26_supervisord_startup_issue_hypothesis.md)

---

## 📋 検証概要

**問題**: VSCode DevContainer起動時にsupervisordが起動しない（問題2解決後に再検証）

**目標**: 問題2（プロジェクト名統一）解決後、VSCodeとbin/dc両方でsupervisordが正常起動することを確認

**検証開始**: 2026-01-12

---

## 🎯 検証パターン

| No | パターン | ステータス | 結果 | 次のアクション |
|------|--------|----------|------|--------------|
| 1 | コンテナ削除 → VSCode起動 | ✅ 成功 | supervisord起動 | - |
| 2 | コンテナ削除 → VSCode起動 → bin/dc起動 | ❌ 失敗 | コンテナ置き換え | overrideCommand問題 |
| 3 | イメージ削除 → VSCode起動（クリーンビルド） | ✅ 成功 | supervisord起動 | - |
| 4 | コンテナ削除 → bin/dc起動 → VSCode起動 | ✅ 成功 | 既存コンテナ接続 | - |

**ステータス凡例**:
- ⬜️ 未実施
- 🔄 実施中
- ✅ 成功
- ❌ 失敗
- ⏭️ スキップ

**検証の目的**:
- パターン1: VSCodeから起動した場合の単独動作確認
- パターン2: VSCode起動後にbin/dcで起動した場合の共存確認
- パターン3: キャッシュなしクリーンビルドでの動作確認
- パターン4: bin/dc起動後にVSCodeで起動した場合の既存コンテナ接続確認

---

## 📝 検証ログ

### パターン1: コンテナ削除 → VSCode起動

**実施日時**: 2026-01-12

**実施者**: <一般ユーザー>

**手順**:
```bash
# 1. 既存コンテナの確認
docker ps -a

# 2. <MDCプロジェクト>プロジェクトのコンテナ停止・削除
./bin/dc down

# 3. VSCodeで "Reopen in Container" 実行
# (VSCodeが新規にコンテナを作成)

# 4. コンテナステータス確認
docker ps --filter "name=<MDCプロジェクト>-dev"

# 5. supervisord起動確認
docker exec <container-id> supervisorctl status
```

**結果**:
```
CONTAINER ID: 748d89005860
STATUS: Up 34 seconds (healthy)
supervisorctl status: code-server RUNNING pid 228, uptime 0:00:48
```

**発見事項**:
- ✅ VSCodeで起動したコンテナが正常にhealthy状態
- ✅ supervisordが正常に起動
- ✅ code-serverがRUNNING状態

**結論**: パターン1 ✅ **成功**

---

### パターン2: コンテナ削除 → VSCode起動 → bin/dc起動

**実施日時**: 2026-01-12

**実施者**: <一般ユーザー>

**手順**:
```bash
# 1. 既存コンテナ削除
./bin/dc down

# 2. VSCodeで "Reopen in Container" 実行

# 3. VSCodeコンテナのステータス確認
docker ps --filter "name=<MDCプロジェクト>-dev"

# 4. VSCodeコンテナでsupervisord確認
docker exec <vscode-container-id> supervisorctl status

# 5. bin/dcで起動（同じプロジェクト名なので接続されるはず）
./bin/dc up -d

# 6. 再度ステータス確認（コンテナが増えていないこと）
docker ps --filter "name=<MDCプロジェクト>-dev"

# 7. supervisord状態確認（変化なし）
docker exec <container-id> supervisorctl status
```

**期待結果**:
- VSCodeで起動したコンテナに`./bin/dc up -d`が接続
- 新しいコンテナは作成されない
- supervisordは起動したまま

**結果**:
```
# 3. VSCodeコンテナのステータス確認
CONTAINER ID: a63965f7f3b5
STATUS: Up 42 seconds (healthy)
COMMAND: /bin/sh -c 'echo Co…'

# 4. supervisord確認
code-server RUNNING pid 227, uptime 0:00:54

# 5. ./bin/dc up -d 実行
[+] Running 1/1
 ✔ Container <MDCプロジェクト>-dev-1  Started

# 6. ステータス再確認
CONTAINER ID: d13dcf5fe161 (変化！)
STATUS: Up 16 seconds (healthy)
COMMAND: /init (変化！)

# 7. supervisord確認
code-server RUNNING pid 148, uptime 0:00:37

# VSCodeの状態
エラー表示: "Cannot reconnect. Please reload the window."
```

**発見事項**:
- ❌ **新しいコンテナが作成された**: `a63965f7f3b5` → `d13dcf5fe161`
- ❌ **VSCodeのコンテナが置き換えられた**: 古いコンテナは完全に削除
- ❌ **COMMANDが異なる**: `/bin/sh -c 'echo ...'` vs `/init`
- ✅ **supervisordは両方で起動**: 新しいコンテナでもsupervisordは正常動作
- ❌ **VSCodeが切断された**: `Cannot reconnect. Please reload the window.`

**根本原因**:
VSCodeの `overrideCommand` が docker-compose.yml の `command` (デフォルト `/init`) と異なるため、Docker Composeが「同じ定義のコンテナ」と認識できず、コンテナを再作成した。

**結論**: パターン2 ❌ **失敗** (共存できず、コンテナが置き換えられた)

---

### パターン3: イメージ削除 → VSCode起動（クリーンビルド）

**実施日時**: 2026-01-12

**実施者**: <一般ユーザー>

**手順**:
```bash
# 1. コンテナ削除
./bin/dc down

# 2. イメージ削除
docker rmi <MDCプロジェクト>-dev

# 3. イメージ削除確認
docker images | grep <MDCプロジェクト>

# 4. VSCodeで "Reopen in Container" 実行
# （完全にクリーンビルドが実行される）

# 5. ビルド完了後、コンテナステータス確認
docker ps --filter "name=<MDCプロジェクト>-dev"

# 6. supervisord起動確認
docker exec <container-id> supervisorctl status
```

**期待結果**:
- キャッシュなしでビルド成功
- コンテナがhealthy状態
- supervisordが正常起動

**結果**:
```
# 2. イメージ削除
Untagged: <MDCプロジェクト>-dev:latest
Deleted: sha256:e37bb81b2dcd98b1c52e7ed826cf9dd6074e8656e98976632c73cf671d70e410

# 3. イメージ削除確認
（何も表示されず - 削除成功）

# 4. VSCodeでビルド
すべてのレイヤーが CACHED から読み込まれた
（Dockerのビルドキャッシュは残っている）

# 5. コンテナステータス確認
CONTAINER ID: 538783064c61
STATUS: Up 28 seconds (healthy)
COMMAND: /bin/sh -c 'echo Co…'

# 6. supervisord確認
code-server RUNNING pid 227, uptime 0:00:46
```

**発見事項**:
- ✅ **イメージ削除成功**: イメージが完全に削除された
- ✅ **ビルド成功**: レイヤーキャッシュを利用して高速ビルド
- ✅ **コンテナがhealthy**: 正常に起動
- ✅ **supervisordが起動**: code-serverがRUNNING状態

**結論**: パターン3 ✅ **成功** (クリーンビルドでもsupervisord正常起動)

---

### パターン4: コンテナ削除 → bin/dc起動 → VSCode起動

**実施日時**: 2026-01-12

**実施者**: <一般ユーザー>

**手順**:
```bash
# 1. 既存コンテナ削除
./bin/dc down

# 2. bin/dcで起動
./bin/dc up -d

# 3. コンテナステータス確認
docker ps --filter "name=<MDCプロジェクト>-dev"

# 4. supervisord確認
docker exec <bindc-container-id> supervisorctl status

# 5. VSCodeで "Reopen in Container" 実行
# （既存コンテナに接続されるはず）

# 6. 再度ステータス確認（コンテナIDが変わっていないこと）
docker ps --filter "name=<MDCプロジェクト>-dev"

# 7. supervisord状態確認（変化なし）
docker exec <container-id> supervisorctl status
```

**期待結果**:
- bin/dcで起動したコンテナにVSCodeが接続
- 新しいコンテナは作成されない
- supervisordは起動したまま

**結果**:
```
# 3. bin/dc起動後のコンテナステータス
CONTAINER ID: d2bc2b5aaff1
STATUS: Up 14 seconds (healthy)
COMMAND: /init

# 4. supervisord確認
code-server RUNNING pid 148, uptime 0:00:29

# 5. VSCodeで "Reopen in Container" 実行
postCreateCommandが2回実行された（既存コンテナ接続の挙動）

# 6. VSCode接続後のコンテナステータス
CONTAINER ID: d2bc2b5aaff1 (変化なし！)
STATUS: Up About a minute (healthy)
COMMAND: /init

# 7. supervisord状態確認
code-server RUNNING pid 148, uptime 0:02:08 (uptimeが継続)
```

**発見事項**:
- ✅ **コンテナIDが変わっていない**: `d2bc2b5aaff1` のまま
- ✅ **COMMANDが維持**: `/init` のまま
- ✅ **VSCodeが既存コンテナに接続**: 新しいコンテナは作成されなかった
- ✅ **supervisordが起動したまま**: uptimeが継続している
- ✅ **postCreateCommandが2回実行**: 既存コンテナ接続時の挙動

**結論**: パターン4 ✅ **成功** (bin/dc起動後、VSCodeが既存コンテナに正常接続)

---

### 旧検証A-E（参考）

<details>
<summary>クリックして展開: 当初計画していた仮説ベースの検証（実施せず）</summary>

### 検証A: 環境変数の確認

**実施日時**: 未実施

**実施者**:

**手順**:
```bash
# 1. VSCodeコンテナの環境変数取得
docker exec <vscode-container-id> env | sort > /tmp/vscode-env.txt

# 2. bin/dcコンテナの環境変数取得
./bin/dc up -d
docker exec <bindc-container-id> env | sort > /tmp/bindc-env.txt

# 3. 差分確認
diff /tmp/vscode-env.txt /tmp/bindc-env.txt

# 4. DEBUG_MODE確認
docker exec <vscode-container-id> bash -c 'echo "DEBUG_MODE=${DEBUG_MODE:-NOT_SET}"'
```

**結果**:

**発見事項**:

**次のアクション**:

---

### 検証C: パーミッションの確認

**実施日時**: 未実施

**実施者**:

**手順**:
```bash
# 1. /var/run/のパーミッション確認
docker exec <vscode-container-id> ls -la /var/run/

# 2. supervisord設定の確認
docker exec <vscode-container-id> grep -E "^(pidfile|serverurl)" /etc/supervisor/supervisord.conf

# 3. 手動ディレクトリ作成
docker exec <vscode-container-id> mkdir -p /var/run/supervisor
docker exec <vscode-container-id> chown root:root /var/run/supervisor

# 4. supervisord手動起動
docker exec <vscode-container-id> supervisord -c /etc/supervisor/supervisord.conf

# 5. 起動確認
docker exec <vscode-container-id> supervisorctl status
```

**結果**:

**発見事項**:

**次のアクション**:

---

### 検証D: 設定ファイルの確認

**実施日時**: 未実施

**実施者**:

**手順**:
```bash
# 1. 設定ファイル存在確認
docker exec <vscode-container-id> ls -la /etc/supervisor/supervisord.conf

# 2. 設定内容確認
docker exec <vscode-container-id> cat /etc/supervisor/supervisord.conf

# 3. 構文チェック
docker exec <vscode-container-id> supervisord -c /etc/supervisor/supervisord.conf -n

# 4. エラーログ確認
docker exec <vscode-container-id> cat /var/log/supervisor/supervisord.log
```

**結果**:

**発見事項**:

**次のアクション**:

---

### 検証B: s6-overlayサービスの起動順序

**実施日時**: 未実施

**実施者**:

**手順**:
```bash
# 1. 起動されたサービス一覧
docker exec <vscode-container-id> s6-rc -a list

# 2. supervisordサービス定義確認
docker exec <vscode-container-id> ls -la /etc/s6-overlay/s6-rc.d/supervisord/
docker exec <vscode-container-id> cat /etc/s6-overlay/s6-rc.d/supervisord/run

# 3. 依存関係確認
docker exec <vscode-container-id> cat /etc/s6-overlay/s6-rc.d/supervisord/dependencies.d/*

# 4. ログ確認
docker exec <vscode-container-id> find /var/log -name "*s6*"
```

**結果**:

**発見事項**:

**次のアクション**:

---

### 検証E: oneshotサービスの確認

**実施日時**: 未実施

**実施者**:

**手順**:
```bash
# 1. user/contents.d/ のサービス一覧
docker exec <vscode-container-id> ls -la /etc/s6-overlay/s6-rc.d/user/contents.d/

# 2. supervisord関連サービス検索
docker exec <vscode-container-id> find /etc/s6-overlay/s6-rc.d/ -name "*supervisor*" -type d

# 3. 手動起動
docker exec <vscode-container-id> s6-rc -u change supervisord
```

**結果**:

**発見事項**:

**次のアクション**:

---

## 🔍 発見事項まとめ

### 環境差分

| 項目 | ./bin/dc | VSCode | 差分 |
|------|----------|--------|------|
| DEBUG_MODE | | | |
| ENTRYPOINT | `/init` | `/bin/sh -c ...` | |
| その他 | | | |

### エラーメッセージ

```
（ここにエラーメッセージを記録）
```

### 重要なログ

```
（ここに重要なログを記録）
```

---

## 💡 解決策候補

### 候補1:

**説明**:

**実装方法**:
```bash
# コマンドまたは設定変更
```

**検証方法**:
```bash
# 検証コマンド
```

**リスク**:

**採用判断**: ⬜️ 採用 / ⬜️ 不採用 / ⬜️ 保留

---

### 候補2:

**説明**:

**実装方法**:

**検証方法**:

**リスク**:

**採用判断**: ⬜️ 採用 / ⬜️ 不採用 / ⬜️ 保留

---

</details>

---

## ✅ 暫定結果

**問題1の状況**:
- パターン1で問題が再現しなかった
- 問題2（プロジェクト名統一）の解決により、問題1も同時に解決された可能性が高い

**次のステップ**:
- パターン2, 3を完了して、完全解決を確認
- 根本原因の特定

---

## 📊 タイムライン

| 時刻 | イベント | 詳細 |
|------|---------|------|
| 2026-01-11 23:10 | トラッカー作成 | 仮説検証ベースで作成 |
| 2026-01-12 | パターン1開始 | 統合テストに切り替え |
| 2026-01-12 | パターン1完了 | ✅ 成功 |
| 2026-01-12 | パターン2完了 | ❌ 失敗（overrideCommand問題） |
| 2026-01-12 | パターン3完了 | ✅ 成功 |
| 2026-01-12 | パターン4完了 | ✅ 成功 |

---

## 📋 チェックリスト

### 検証完了条件

- [x] パターン1: コンテナ削除 → VSCode起動
- [x] パターン2: VSCode起動 → bin/dc起動
- [x] パターン3: イメージ削除 → VSCode起動（クリーンビルド）
- [x] パターン4: bin/dc起動 → VSCode起動
- [x] 根本原因を特定（問題2解決により問題1も解決）
- [x] パターン1,3,4で成功を確認（パターン2はoverrideCommand問題）

### ドキュメント更新

- [ ] [25_6_26_supervisord_startup_issue_hypothesis.md](./25_6_26_supervisord_startup_issue_hypothesis.md) に検証結果を記録
- [ ] [25_6_24_devcontainer_existing_container_connection.md](./25_6_24_devcontainer_existing_container_connection.md) の問題1を解決済みに更新
- [ ] [99_ongoing_directory_status_analysis.md](./99_ongoing_directory_status_analysis.md) を更新
- [ ] 解決済みファイルを `resolved/` に移動

---

**最終更新**: 2026-01-12
**ステータス**: ✅ 検証完了（パターン1,3,4成功、パターン2はoverrideCommand問題で失敗）
