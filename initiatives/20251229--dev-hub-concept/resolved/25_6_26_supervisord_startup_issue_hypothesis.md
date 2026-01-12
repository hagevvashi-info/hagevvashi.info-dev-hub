# 仮説検証立案: VSCode起動時のsupervisord未起動問題

**作成日**: 2026-01-11
**関連ドキュメント**: [25_6_24_devcontainer_existing_container_connection.md](./25_6_24_devcontainer_existing_container_connection.md#問題1-supervisord-が起動しないvscode起動時)

---

## 1. 背景

### プロジェクト概要
- **プロジェクト**: Monolithic DevContainer (MDC) 開発環境
- **目標**: VSCode DevContainerと`./bin/dc`コマンドの両方でシームレスにコンテナを管理
- **実装済み機能**: DevContainer既存コンテナ接続機能

### これまでの成果
- ✅ `runServices: ["dev"]` - 既存コンテナの検出を有効化
- ✅ `shutdownAction: "none"` - VSCode終了時のコンテナ継続
- ✅ `overrideCommand: false` - s6-overlayエントリーポイントの保持
- ✅ 問題2（プロジェクト名の不一致）解決完了

### 検証状況（2026-01-11）
- ✅ **テスト1**: 既存コンテナへの接続 - 成功
- ✅ **テスト2**: VSCode終了時のコンテナ継続 - 成功
- ⚠️ **テスト3**: 新規コンテナ起動 - 部分成功（supervisord未起動）

---

## 2. 問題

### 問題の症状

```bash
# VSCodeが起動したコンテナ内
$ docker exec 7b835ebbf70f supervisorctl status
unix:///var/run/supervisor.sock no such file
Exit code: 4

# プロセス確認
$ docker exec 7b835ebbf70f ps aux
# 結果:
# - s6-overlay (PID 1) が起動
# - process-compose が起動
# - supervisord が未起動 ❌
# - /var/run/supervisor.sock が存在しない ❌
```

### 動作の違い

| 起動方法 | s6-overlay | process-compose | supervisord | code-server | ヘルスチェック |
|---------|-----------|----------------|-------------|-------------|--------------|
| `./bin/dc up -d` | ✅ 起動 | ✅ 起動 | ✅ 起動 | ✅ 起動 | ✅ healthy |
| VSCode DevContainer | ✅ 起動 | ✅ 起動 | ❌ 未起動 | ❌ 未起動 | ❌ unhealthy |

### 影響

1. **code-serverが起動しない**
   - Web UIでの開発ができない
   - ブラウザからのアクセスが不可

2. **ヘルスチェックが常にunhealthy**
   ```yaml
   # docker-compose.yml の healthcheck
   supervisorctl status code-server | grep -q RUNNING || exit 1
   ```
   - supervisordが起動していないため、常に失敗

3. **一部機能が使えない**
   - supervisord管理下のサービスが全て起動しない
   - コンテナは動作するが不完全な状態

### 環境差分

**./bin/dc up -d の場合**:
- カレントディレクトリ: `.devcontainer/`
- コマンド: `docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml up -d`
- ENTRYPOINT: `/init` (Dockerfileのデフォルト)

**VSCode DevContainer の場合**:
- ワークスペース: `/Users/<一般ユーザー>/repos/<MDCレポジトリ>`
- コマンド: VSCodeが自動生成
- ENTRYPOINT: `/bin/sh -c 'echo Co... /usr/local/share/docker-init.sh exec "$@" ...' - /init`
- `docker-from-docker` feature のラッパースクリプトが追加

---

## 3. 原因

### 根本原因の分析

**参考ドキュメント**:
- [VSCode DevContainers - Start a process when the container starts](https://code.visualstudio.com/remote/advancedcontainers/start-processes)
- [s6-overlay - User-provided files](https://github.com/just-containers/s6-overlay#user-provided-files)

### 仮説の根拠

#### 観察された事実

1. **s6-overlayは起動している**
   - PID 1 で s6-svscan が動作
   - s6-overlay の基本プロセスは正常

2. **process-composeは起動している**
   - s6-overlay配下のサービスとして動作
   - `/etc/s6-overlay/s6-rc.d/process-compose/run` が実行されている

3. **supervisordのみ起動していない**
   - `/var/run/supervisor.sock` が存在しない
   - supervisorctl が接続できない

4. **VSCodeのラッパースクリプトが追加されている**
   ```
   COMMAND: /bin/sh -c 'echo Container started\n trap "exit 0" 15\n /usr/local/share/docker-init.sh\n exec "$@"\n while sleep 1 & wait $!; do :; done' - /init
   ```

#### 考えられる原因

**原因候補A**: 環境変数の違い
- VSCodeが設定する環境変数が不足している
- s6-overlay のサービス起動条件に影響

**原因候補B**: 起動タイミングの問題
- `docker-init.sh` の実行がs6-overlayの初期化に影響
- supervisord起動前にVSCodeが何かをブロックしている

**原因候補C**: s6-overlayサービス定義の問題
- supervisord サービスの依存関係が正しく設定されていない
- `oneshot` サービスの実行が失敗している

**原因候補D**: ファイルシステムのパーミッション問題
- `/var/run/` ディレクトリの権限が不適切
- supervisordがソケットファイルを作成できない

---

## 4. 仮説

### 仮説A: 環境変数`DEBUG_MODE`の影響

**仮説内容**:
VSCodeが起動するコンテナで`DEBUG_MODE`環境変数が適切に設定されていないため、supervisordの起動ロジックが異なる動作をしている。

**根拠**:
- docker-compose.yml で `DEBUG_MODE=false` が設定されている
- ヘルスチェックで `DEBUG_MODE` の値を参照している
- VSCodeが環境変数を上書きまたは未設定にしている可能性

**検証方法**:
```bash
# VSCodeで起動したコンテナ内
docker exec <container-id> env | grep DEBUG_MODE
docker exec <container-id> echo $DEBUG_MODE

# ./bin/dc で起動したコンテナと比較
```

**期待される結果**:
- VSCodeコンテナで `DEBUG_MODE` が未設定または異なる値
- 環境変数を明示的に設定すれば解決

**リスク**:
- 環境変数だけでは解決しない可能性（中）

---

### 仮説B: s6-overlayサービスの起動順序問題

**仮説内容**:
supervisord サービスが他のサービスに依存しているが、VSCodeのラッパースクリプトがs6-overlayの初期化シーケンスを妨げている。

**根拠**:
- s6-overlay は依存関係に基づいてサービスを起動
- `docker-init.sh` がPID空間や初期化順序に影響する可能性
- process-compose は起動しているが supervisord は起動していない

**検証方法**:
```bash
# s6-overlayのログ確認
docker exec <container-id> s6-rc -a list
docker exec <container-id> cat /var/log/s6-overlay.log  # ログファイルがあれば

# supervisordサービスの状態確認
docker exec <container-id> ls -la /etc/s6-overlay/s6-rc.d/supervisord/
docker exec <container-id> cat /etc/s6-overlay/s6-rc.d/supervisord/run
```

**期待される結果**:
- supervisordサービスが依存関係で起動していない
- サービス定義を修正すれば解決

**リスク**:
- s6-overlayの内部動作に深く依存（高）

---

### 仮説C: `/var/run/supervisor/` ディレクトリのパーミッション問題

**仮説内容**:
VSCode起動時にユーザーやパーミッションが異なるため、supervisordが `/var/run/supervisor.sock` を作成できない。

**根拠**:
- `remoteUser: <一般ユーザー>` が設定されている
- supervisordは通常rootまたは特定ユーザーで起動
- ディレクトリのパーミッション不足の可能性

**検証方法**:
```bash
# パーミッション確認
docker exec <container-id> ls -la /var/run/ | grep supervisor
docker exec <container-id> stat /var/run/

# supervisordの起動ユーザー確認
docker exec <container-id> grep user /etc/supervisor/supervisord.conf

# 手動でsupervisordを起動
docker exec <container-id> supervisord -c /etc/supervisor/supervisord.conf
```

**期待される結果**:
- パーミッションエラーが発生
- ディレクトリの作成またはパーミッション変更で解決

**リスク**:
- パーミッション変更がセキュリティに影響（中）

---

### 仮説D: supervisord設定ファイルの読み込み失敗

**仮説内容**:
VSCode起動時に設定ファイルのパスが異なるか、設定ファイルが読み込めていない。

**根拠**:
- `/etc/supervisor/supervisord.conf` が存在するか不明
- VSCodeの環境でパスが異なる可能性

**検証方法**:
```bash
# 設定ファイルの存在確認
docker exec <container-id> ls -la /etc/supervisor/
docker exec <container-id> cat /etc/supervisor/supervisord.conf

# supervisordを直接起動してエラー確認
docker exec <container-id> supervisord -c /etc/supervisor/supervisord.conf -n
```

**期待される結果**:
- 設定ファイルが存在しない、または構文エラー
- 設定を修正すれば解決

**リスク**:
- 設定ファイルが正しい場合、原因が別にある（中）

---

### 仮説E: s6-overlay oneshotサービスの実行失敗

**仮説内容**:
supervisord起動前に実行されるべき `oneshot` サービスが失敗しているため、supervisordが起動しない。

**根拠**:
- s6-overlayは`oneshot`サービスで初期化タスクを実行
- 依存関係が正しく設定されていない可能性

**検証方法**:
```bash
# oneshotサービスの確認
docker exec <container-id> ls -la /etc/s6-overlay/s6-rc.d/user/contents.d/

# s6-rc で実際に起動されたサービスを確認
docker exec <container-id> s6-rc -a list

# supervisord関連のoneshotサービスを確認
docker exec <container-id> find /etc/s6-overlay/s6-rc.d/ -name "*supervisor*"
```

**期待される結果**:
- supervisord関連のoneshotサービスが実行されていない
- 依存関係を追加すれば解決

**リスク**:
- s6-overlayの設計に深く依存（高）

---

## 5. 検証方法

### 検証の優先順位

1. **仮説A** - 最もシンプル（環境変数の確認）
2. **仮説C** - 比較的簡単（パーミッション確認）
3. **仮説D** - 中程度（設定ファイル確認）
4. **仮説B** - 複雑（s6-overlay起動順序）
5. **仮説E** - 最も複雑（oneshotサービス）

### 検証A: 環境変数の確認

#### 前提条件
- VSCodeでDevContainerが起動している状態
- `./bin/dc up -d`で起動したコンテナと比較可能

#### 検証手順

```bash
# 1. VSCodeで起動したコンテナの環境変数確認
docker exec <vscode-container-id> env | sort > /tmp/vscode-env.txt

# 2. ./bin/dc で起動したコンテナの環境変数確認
./bin/dc up -d
docker exec <bindc-container-id> env | sort > /tmp/bindc-env.txt

# 3. 差分確認
diff /tmp/vscode-env.txt /tmp/bindc-env.txt

# 4. 特にDEBUG_MODEを確認
docker exec <vscode-container-id> bash -c 'echo "DEBUG_MODE=${DEBUG_MODE:-NOT_SET}"'
docker exec <bindc-container-id> bash -c 'echo "DEBUG_MODE=${DEBUG_MODE:-NOT_SET}"'
```

#### 成功基準
- ✅ 環境変数に明確な差分がある
- ✅ `DEBUG_MODE` または supervisord関連の環境変数が異なる

#### 失敗時の対応
- 環境変数に差分がない場合 → 仮説Cへ進む

---

### 検証C: パーミッションの確認

#### 検証手順

```bash
# 1. /var/run/ のパーミッション確認
docker exec <vscode-container-id> ls -la /var/run/

# 2. supervisordが使用するディレクトリを確認
docker exec <vscode-container-id> grep -E "^(pidfile|serverurl)" /etc/supervisor/supervisord.conf

# 3. 手動でディレクトリ作成
docker exec <vscode-container-id> mkdir -p /var/run/supervisor
docker exec <vscode-container-id> chown root:root /var/run/supervisor

# 4. supervisordを手動起動
docker exec <vscode-container-id> supervisord -c /etc/supervisor/supervisord.conf

# 5. 起動確認
docker exec <vscode-container-id> supervisorctl status
```

#### 成功基準
- ✅ パーミッションエラーが発生
- ✅ 手動でディレクトリ作成後、supervisordが起動

#### 失敗時の対応
- パーミッション問題でない場合 → 仮説Dへ進む

---

### 検証D: 設定ファイルの確認

#### 検証手順

```bash
# 1. supervisord設定ファイルの存在確認
docker exec <vscode-container-id> ls -la /etc/supervisor/supervisord.conf

# 2. 設定内容確認
docker exec <vscode-container-id> cat /etc/supervisor/supervisord.conf

# 3. 構文チェック
docker exec <vscode-container-id> supervisord -c /etc/supervisor/supervisord.conf -n

# 4. エラーログ確認
docker exec <vscode-container-id> cat /var/log/supervisor/supervisord.log
```

#### 成功基準
- ✅ 設定ファイルにエラーがある
- ✅ ログにエラーメッセージが記録されている

#### 失敗時の対応
- 設定ファイルが正常な場合 → 仮説Bへ進む

---

### 検証B: s6-overlayサービスの起動順序

#### 検証手順

```bash
# 1. s6-overlayで起動されたサービス一覧
docker exec <vscode-container-id> s6-rc -a list

# 2. supervisordサービスの定義確認
docker exec <vscode-container-id> ls -la /etc/s6-overlay/s6-rc.d/supervisord/
docker exec <vscode-container-id> cat /etc/s6-overlay/s6-rc.d/supervisord/type
docker exec <vscode-container-id> cat /etc/s6-overlay/s6-rc.d/supervisord/run

# 3. 依存関係確認
docker exec <vscode-container-id> cat /etc/s6-overlay/s6-rc.d/supervisord/dependencies.d/*

# 4. s6-overlayのログ確認（存在すれば）
docker exec <vscode-container-id> find /var/log -name "*s6*"
```

#### 成功基準
- ✅ supervisordサービスが定義されていない、または依存関係が不足
- ✅ s6-overlayがsupervisordを起動していない

#### 失敗時の対応
- 仮説Eへ進む

---

### 検証E: oneshotサービスの確認

#### 検証手順

```bash
# 1. user/contents.d/ のサービス一覧
docker exec <vscode-container-id> ls -la /etc/s6-overlay/s6-rc.d/user/contents.d/

# 2. supervisord関連のoneshotサービス検索
docker exec <vscode-container-id> find /etc/s6-overlay/s6-rc.d/ -name "*supervisor*" -type d

# 3. 各oneshotサービスの内容確認
docker exec <vscode-container-id> cat /etc/s6-overlay/s6-rc.d/user/contents.d/<service-name>

# 4. s6-rc でサービスを手動起動
docker exec <vscode-container-id> s6-rc -u change supervisord
```

#### 成功基準
- ✅ oneshotサービスが実行されていない
- ✅ 手動で起動すればsupervisordが起動

---

## 6. 検証後の判断基準

### 採用基準

各仮説の評価軸:

| 評価項目 | 重要度 | 仮説A | 仮説B | 仮説C | 仮説D | 仮説E |
|---------|-------|-------|-------|-------|-------|-------|
| **検証の容易さ** | 高 | ◎ | △ | ○ | ○ | △ |
| **解決の確実性** | 高 | ○ | △ | ○ | ○ | △ |
| **影響範囲** | 中 | ○ | △ | ○ | ○ | △ |
| **保守性** | 高 | ◎ | △ | ○ | ◎ | △ |

### 推奨順位

1. **仮説A** - 環境変数（最もシンプル、影響小）
2. **仮説C** - パーミッション（比較的簡単、よくある問題）
3. **仮説D** - 設定ファイル（中程度、明確な解決策）
4. **仮説B** - 起動順序（複雑、s6-overlay依存）
5. **仮説E** - oneshotサービス（最も複雑、根本的変更必要）

---

## 7. 次のステップ

### 検証実施後

1. **検証結果の記録**
   - 各仮説の結果を本ドキュメントに追記
   - スクリーンショットやログを保存

2. **ドキュメントの更新**
   - [25_6_24_devcontainer_existing_container_connection.md](./25_6_24_devcontainer_existing_container_connection.md)に解決策を追記
   - 問題1のステータスを「解決済み」に更新

3. **統合テストの実施**
   - テスト1: 既存コンテナへの接続（再確認）
   - テスト2: VSCode終了時のコンテナ継続（再確認）
   - テスト3: 新規コンテナ起動（完全成功を確認）

4. **resolved移動**
   - 問題1が解決したら、このドキュメントと25_6_24をresolvedへ移動

---

## 8. 参考情報

### s6-overlay関連

- [s6-overlay GitHub](https://github.com/just-containers/s6-overlay)
- [s6-overlay - User-provided files](https://github.com/just-containers/s6-overlay#user-provided-files)
- [s6-rc documentation](https://skarnet.org/software/s6-rc/)

### supervisord関連

- [Supervisor Documentation](http://supervisord.org/)
- [Supervisor Configuration File](http://supervisord.org/configuration.html)

### VSCode DevContainers関連

- [Start a process when the container starts](https://code.visualstudio.com/remote/advancedcontainers/start-processes)
- [Add a non-root user](https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user)

---

## 付録: 検証ログ

### 検証A: 実施日時・結果

**実施日時**: 未実施

**結果**:

**詳細**:

---

### 検証B: 実施日時・結果

**実施日時**: 未実施

**結果**:

**詳細**:

---

### 検証C: 実施日時・結果

**実施日時**: 未実施

**結果**:

**詳細**:

---

### 検証D: 実施日時・結果

**実施日時**: 未実施

**結果**:

**詳細**:

---

### 検証E: 実施日時・結果

**実施日時**: 未実施

**結果**:

**詳細**:
