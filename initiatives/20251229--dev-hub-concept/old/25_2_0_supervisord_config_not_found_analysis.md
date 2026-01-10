# supervisord設定ファイル不在エラーの分析

**作成日**: 2026-01-03
**エラーログ**: `initiatives/20251229--dev-hub-concept/202601031002-error.log`
**関連**: [25_process_management_solution.v6.md](25_process_management_solution.v6.md), [24_scripts_separation_and_lifecycle.md](24_scripts_separation_and_lifecycle.md)

## 概要

コンテナが起動時にエラーで終了する問題を分析しました。原因は supervisord の設定ファイルが存在しないことです。

---

## エラー内容

### コンテナログ

```
Container started
Fixing permissions for mounted config volumes...
✅ Permissions fixed.
Docker socket GID: 0, Mode: 777
Docker socket permissions updated
Initializing Atuin configuration...
ℹ️  Atuin config already exists, using existing configuration
✅ Atuin initialization complete
Error: could not find config file /etc/supervisor/conf.d/supervisord.conf
For help, use /usr/bin/supervisord -h
```

### コンテナ状態

```bash
$ docker ps -a | grep devcontainer
f36bb424848a   hagevvashiinfo-dev-hub_devcontainer-dev   "/bin/sh -c 'echo Co…"   7 minutes ago   Exited (2) 7 minutes ago
```

**Exit code 2**: supervisord が設定ファイルを見つけられず異常終了

---

## 原因分析

### 1. 現在の Dockerfile の状態

**supervisord のインストール部分**（確認済み）:
```dockerfile
# Process management tools
supervisor \
```

✅ supervisor パッケージはインストール済み

**CMD の設定**（確認済み）:
```dockerfile
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

✅ supervisord を起動しようとしている

**設定ファイルの COPY**（確認したところ...）:
```dockerfile
# ❌ この処理が存在しない
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
```

❌ **設定ファイルをコピーする処理が実装されていない**

### 2. 設計との乖離

**設計ドキュメント（25_process_management_solution.v6.md）の記載**:

```dockerfile
# supervisordインストール
RUN apt-get update && \
    apt-get install -y supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# process-composeインストール（Go製バイナリ）
ARG PROCESS_COMPOSE_VERSION=1.39.2
RUN curl -L "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_Linux_x86_64.tar.gz" \
    -o /tmp/process-compose.tar.gz && \
    tar -xzf /tmp/process-compose.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/process-compose && \
    rm /tmp/process-compose.tar.gz

# ... 既存のツールインストール処理 ...

# supervisord設定をコピー ← ★この処理が設計されている
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# process-compose設定をコピー ← ★この処理が設計されている
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml

# supervisordをPID 1として起動
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

**問題**: 設計では COPY 処理が明記されているが、実装されていない

---

## 設定ファイルの配置方針

### 相談1: ファイル配置場所の適切性

**結論: 適切**

現在の配置:
```
.devcontainer/
├── supervisord/
│   └── supervisord.conf
└── process-compose/
    └── process-compose.yaml
```

**理由**:
1. 設計ドキュメント（25_process_management_solution.v6.md）で明確に定義済み
2. DevContainer関連ファイルを `.devcontainer/` 配下にまとめるのは慣例
3. ツール別にディレクトリを分けることで管理しやすい
4. バージョン管理に含めやすい

### 相談2: COPY vs バインドマウント

**結論: COPY 方式を採用（設計通り）**

#### COPY 方式（推奨）

**メリット**:
- ✅ イメージに含まれるので、常に存在が保証される
- ✅ コンテナ起動時に確実に利用可能
- ✅ イメージの再現性が高い
- ✅ 権限問題が発生しにくい

**デメリット**:
- ⚠️ 設定変更時にイメージの再ビルドが必要

**実装**:
```dockerfile
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml
```

#### バインドマウント方式（非推奨）

**メリット**:
- ✅ 設定変更時にイメージ再ビルド不要
- ✅ 開発中の設定調整が楽

**デメリット**:
- ❌ docker-compose.yml にマウント設定が必要で複雑
- ❌ ファイルが存在しない場合にエラー
- ❌ 権限問題が発生しやすい
- ❌ 起動時の安定性が低い

**実装例**（参考）:
```yaml
# docker-compose.yml
volumes:
  - type: bind
    source: .devcontainer/supervisord/supervisord.conf
    target: /etc/supervisor/conf.d/supervisord.conf
    read_only: true
```

### 採用方針の根拠

#### スクリプト棲み分けの原則（24_scripts_separation_and_lifecycle.md より）

| 変更頻度 | 配置方法 | 例 |
|---------|---------|---|
| **低** | イメージに焼き込む | `docker-entrypoint.sh`, `.devcontainer/shell/*`, **supervisord.conf** |
| **中〜高** | バインドマウント | `post-create.sh` |

**supervisord.conf / process-compose.yaml の特性**:
- ✅ **システム設定に近い**（プロセス管理の基盤）
- ✅ **変更頻度が低い**（頻繁に変更するものではない）
- ✅ **安定性が重要**（起動時に確実に存在すべき）

→ **イメージに焼き込む（COPY 方式）が適切**

#### post-create.sh との比較

| 観点 | supervisord.conf | post-create.sh |
|------|-----------------|---------------|
| **性質** | システム設定（プロセス管理基盤） | DevContainer固有のセットアップ |
| **変更頻度** | 低（稀） | 中〜高（開発中に変更される） |
| **重要性** | 高（起動に必須） | 中（1回実行されれば良い） |
| **配置方法** | イメージに焼き込む | バインドマウント |

**post-create.sh はバインドマウント方式を採用している理由**:
- 開発中に頻繁に変更される可能性がある
- デバッグ用の出力追加など、試行錯誤が必要
- 1回実行されれば良いので、起動の安定性への影響が小さい

**supervisord.conf は COPY 方式を採用すべき理由**:
- プロセス管理の基盤であり、安定性が最重要
- 変更頻度が低い（設定が固まったら変更しない）
- コンテナ起動時に必ず存在すべき

---

## 解決策

### 実装手順

#### 1. Dockerfile に COPY 処理を追加

**追加箇所**: supervisor インストール後、CMD 設定前

```dockerfile
# Process management tools のインストール（既存）
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      supervisor \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/*

# ... 既存の処理 ...

# ★★★ ここに追加 ★★★
# Supervisord設定ファイルをコピー
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Process Compose設定ファイルをコピー
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml

# ... 既存の処理 ...

# supervisordをPID 1として起動（既存）
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

#### 2. イメージ再ビルド

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

#### 3. コンテナ起動確認

```bash
docker compose -f .devcontainer/docker-compose.yml up -d
docker logs <container-id>
```

**期待される出力**:
```
Container started
Fixing permissions for mounted config volumes...
✅ Permissions fixed.
...
✅ Atuin initialization complete
# supervisord が正常起動（エラーなし）
```

#### 4. supervisord Web UI 確認

```
http://localhost:9001
Username: admin
Password: admin
```

---

## process-compose.yaml の配置について

### 配置先の検討

**設計では `/etc/process-compose/process-compose.yaml` としているが、要検討**

#### オプション1: `/etc/process-compose/` 配下（設計通り）

```dockerfile
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml
```

**メリット**:
- システム設定らしい配置
- supervisord.conf と同様の扱い

**デメリット**:
- `/etc/process-compose/` ディレクトリを事前作成する必要がある

**実装**:
```dockerfile
RUN mkdir -p /etc/process-compose
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml
```

#### オプション2: ホームディレクトリ配下

```dockerfile
COPY .devcontainer/process-compose/process-compose.yaml /home/<一般ユーザー>/.config/process-compose/process-compose.yaml
```

**メリット**:
- ユーザー設定として自然
- 権限問題が少ない

**デメリット**:
- イメージビルド時点でユーザーが存在している必要がある

**推奨**: オプション1（設計通り）を採用し、ディレクトリ作成を追加

---

## 設定ファイルの内容確認

### supervisord.conf

**配置**: `.devcontainer/supervisord/supervisord.conf`

**主要な設定**:
```ini
[inet_http_server]
port=*:9001  # Web UI

[supervisord]
nodaemon=true  # フォアグラウンド実行（コンテナ向け）

[program:docker-entrypoint]
command=/usr/local/bin/docker-entrypoint.sh
autostart=true
autorestart=false

[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
autostart=true
autorestart=false

[program:process-compose]
command=/usr/local/bin/process-compose -f /etc/process-compose/process-compose.yaml
autostart=false  # 手動起動

[program:difit]
command=/home/<一般ユーザー>/.asdf/shims/difit
autostart=false  # 手動起動
```

**確認済み**: ✅ ファイルは存在し、設定内容は妥当

### process-compose.yaml

**配置**: `.devcontainer/process-compose/process-compose.yaml`

**主要な設定**:
```yaml
version: "0.5"

processes:
  difit:
    command: "difit"
    working_dir: "/home/<一般ユーザー>/hagevvashi.info-dev-hub"
    availability:
      restart: "no"
```

**確認済み**: ✅ ファイルは存在し、設定内容は妥当

---

## 今回のエラーから得られた教訓

### 1. 設計と実装の乖離

**問題**: 設計ドキュメント（25_process_management_solution.v6.md）には COPY 処理が明記されていたが、実装されていなかった

**教訓**:
- 設計ドキュメントを作成したら、実装チェックリストを作成する
- 設計と実装の対応関係を明確にする
- 実装後に設計との差分を確認する

### 2. 段階的な実装の重要性

**問題**: supervisord のインストールと設定ファイルのコピーが別々のタイミングで実装された

**教訓**:
- パッケージインストールと設定ファイル配置は同時に実装する
- 動作確認を段階的に行う（ビルド → 起動 → 動作確認）

### 3. エラーログの読み方

**今回のエラー**:
```
Error: could not find config file /etc/supervisor/conf.d/supervisord.conf
```

**気づき**:
- エラーメッセージが明確だった（ファイルが見つからない）
- コンテナログを見ることで、どこまで正常に動作したかが分かった
- Exit code 2 から異常終了であることが判明

**教訓**:
- エラーメッセージを素直に読む
- コンテナログ全体を確認する
- Exit code を確認する

---

## 次のステップ

### 実装タスク

- [ ] Dockerfile に COPY 処理を追加
  - [ ] supervisord.conf のコピー
  - [ ] process-compose.yaml のコピー（ディレクトリ作成含む）
- [ ] イメージ再ビルド
- [ ] コンテナ起動確認
- [ ] supervisord Web UI 動作確認（http://localhost:9001）
- [ ] code-server 起動確認（http://localhost:4035）
- [ ] 動作確認後、エラー解決の記録を更新

### ドキュメント更新

- [ ] 今回のエラーと解決策を記録
- [ ] 設計と実装の対応チェックリストを作成
- [ ] `foundations/onboarding/` に supervisord の使い方ガイドを追加

---

## 参考資料

- [25_process_management_solution.v6.md](25_process_management_solution.v6.md): プロセス管理ツールの選定と実装（ハイブリッド構成）
- [24_scripts_separation_and_lifecycle.md](24_scripts_separation_and_lifecycle.md): DevContainerスクリプトの棲み分けとライフサイクル
- [Supervisor Documentation](http://supervisord.org/)
- [Dockerfile COPY instruction](https://docs.docker.com/engine/reference/builder/#copy)

---

## 変更履歴

### 2026-01-03
- 初版作成
- supervisord設定ファイル不在エラーの原因分析
- COPY vs バインドマウントの方針決定
- 解決策の実装手順を記載
