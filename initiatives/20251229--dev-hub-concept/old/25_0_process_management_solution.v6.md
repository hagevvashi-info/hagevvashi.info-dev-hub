# プロセス管理ツールの選定と実装（ハイブリッド構成）

**作成日**: 2026-01-02
**バージョン**: v6（supervisord + process-compose ハイブリッド）
**関連**: [00_Monolithic DevContainerの本質.v2.md](00_Monolithic%20DevContainerの本質.v2.md)

## １．課題（目標とのギャップ）

**現在の実装は「code-server専用コンテナ」であり、Monolithic DevContainerの本来の目的と矛盾している**

### 現状の問題

```dockerfile
# Dockerfile
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth password"]
```

**code-serverがPID 1として起動している状態**

### 具体的な問題点

1. **PID 1が特定のプロセスに専有されている**
2. **複数サービスを並行稼働できない**
3. **プロセスの状態が見えない**
4. **ログの確認・デバッグが困難**

---

## ２．本当に必要な要件

### 開発環境として必要な要件

1. **✅ PID 1問題の解決**
2. **✅ 複数プロセスの管理**
3. **✅ プロセスの状態可視化（Web/TUI）**
   - **Web UI**: ブラウザで確認（supervisord）
   - **TUI**: ターミナルで素早く確認（process-compose）
4. **✅ ログの確認・デバッグが容易**

### 不要な要件

- ❌ 本番環境との一致性 → 気にしない
- ❌ 軽量性・起動速度 → 気にしない
- ❌ プロセスの依存関係 → あったらいいかも程度
- ❌ 自動再起動 → エラーが見えなくなるので不要

---

## ３．採用する構成: ハイブリッドアプローチ

### 基本方針

**supervisord（基盤）+ process-compose（開発ツール）の2段構成**

```
┌─────────────────────────────────────┐
│  PID 1: supervisord                 │
│  - Web UI (http://localhost:9001)  │
│  - 安定したプロセス管理基盤         │
├─────────────────────────────────────┤
│  managed by supervisord:            │
│  ├─ docker-entrypoint (oneshot)    │
│  ├─ code-server                    │
│  └─ process-compose (optional)     │
│     - TUI (開発中の素早い確認)      │
│     - docker-composeライクなYAML   │
└─────────────────────────────────────┘
```

### それぞれの役割

| ツール | 役割 | 用途 |
|--------|------|------|
| **supervisord** | **プロセス管理基盤（PID 1）** | ・Web UIで全体管理<br>・安定稼働が必要なサービス（code-server等）<br>・常時起動 |
| **process-compose** | **開発ツール** | ・TUIで開発中のプロセス確認<br>・実験的なサービス起動<br>・必要なときだけ起動 |

### なぜハイブリッド？

1. **supervisordの強み**
   - ✅ Web UI標準搭載 → ブラウザで状態確認
   - ✅ 安定性が高い → PID 1として信頼できる
   - ✅ 実績豊富 → コンテナ環境での利用実績多数

2. **process-composeの強み**
   - ✅ TUI → ターミナルで素早く確認
   - ✅ YAML設定 → docker-composeライクで親しみやすい
   - ✅ 柔軟性 → 実験的なサービスをすぐ追加・削除

3. **両方使うメリット**
   - **選択肢**: Web UIとTUI、両方使える
   - **適材適所**: 安定稼働はsupervisord、実験はprocess-compose
   - **学習機会**: 両方のツールを体験できる

---

## ４．実装内容

### 4.1 Dockerfile

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

# supervisord設定をコピー
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# process-compose設定をコピー
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml

# supervisordをPID 1として起動
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

### 4.2 supervisord.conf

```ini
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[inet_http_server]
port=*:9001
username=admin
password=admin

[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/var/run/supervisord.pid

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

# ========================================
# 初期化処理
# ========================================

[program:docker-entrypoint]
command=/usr/local/bin/docker-entrypoint.sh
user=hagevvashi
autostart=true
autorestart=false
startsecs=0
priority=1
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# ========================================
# 安定稼働が必要なサービス
# ========================================

[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=hagevvashi
directory=/home/<一般ユーザー>/hagevvashi.info-dev-hub
autostart=true
autorestart=false
priority=10
environment=CODE_SERVER_PORT="4035",HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# ========================================
# 開発ツール（オプション）
# ========================================

# process-compose（TUIでプロセス管理）
# 必要なときだけ手動起動
[program:process-compose]
command=/usr/local/bin/process-compose -f /etc/process-compose/process-compose.yaml
user=hagevvashi
directory=/home/<一般ユーザー>/hagevvashi.info-dev-hub
autostart=false
autorestart=false
priority=20
environment=HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# difit（直接supervisordで管理する場合）
[program:difit]
command=/home/<一般ユーザー>/.asdf/shims/difit
user=hagevvashi
directory=/home/<一般ユーザー>/hagevvashi.info-dev-hub
autostart=false
autorestart=false
priority=20
environment=HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

### 4.3 process-compose.yaml

```yaml
version: "0.5"

# TUIの設定
log_location: /tmp/process-compose-${USER}.log
log_level: info

processes:
  # difit（開発支援ツール）
  difit:
    command: "difit"
    working_dir: "/home/<一般ユーザー>/hagevvashi.info-dev-hub"
    availability:
      restart: "no"  # エラーを見たいので自動再起動しない
    environment:
      - HOME=/home/hagevvashi

  # 実験的なサービスの例
  # vite-preview:
  #   command: "npm run preview"
  #   working_dir: "/home/<一般ユーザー>/repos/some-project"
  #   availability:
  #     restart: "no"
  #   depends_on:
  #     difit:
  #       condition: process_started

  # アプリケーションサーバーの例
  # app-server:
  #   command: "npm run dev"
  #   working_dir: "/home/<一般ユーザー>/repos/product-a"
  #   availability:
  #     restart: "no"
  #   environment:
  #     - HOME=/home/hagevvashi
  #     - PORT=8080
```

### 4.4 docker-compose.yml修正

```yaml
services:
  dev:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
      args:
        UID: ${UID:-1000}
        GID: ${GID:-1000}
        UNAME: ${UNAME:-vscode}
        GNAME: ${GNAME:-vscode}
    volumes:
      - type: bind
        source: ..
        target: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}
        consistency: cached
      - type: volume
        source: repos
        target: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}/repos
    working_dir: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}
    ports:
      - "4035:4035"  # code-server
      - "8035:8035"  # difit
      - "8036:8036"  # vite preview
      - "8037:8037"  # review-knowledge-rag-server
      - "8038:8038"  # kpi-workbench
      - "9001:9001"  # supervisord Web UI
      - "8080:8080"  # process-compose TUI/API (optional)
    user: "${UID:-1000}:${GID:-1000}"
    tty: true
    stdin_open: true  # process-compose TUI用

volumes:
  repos:
    external: true
```

---

## ５．使い分けガイド

### supervisord（基盤）

**こんなときに使う**:
- ✅ 常時稼働させたいサービス（code-server等）
- ✅ ブラウザでプロセス状態を確認したい
- ✅ 安定性が重要なサービス

**操作方法**:

**Web UI**:
```
http://localhost:9001
Username: admin
Password: admin
```

**CLI**:
```bash
# 状態確認
supervisorctl status

# サービス起動・停止
supervisorctl start difit
supervisorctl stop difit
supervisorctl restart code-server

# ログ確認
supervisorctl tail -f code-server
```

---

### process-compose（開発ツール）

**こんなときに使う**:
- ✅ 開発中に頻繁に起動・停止するサービス
- ✅ ターミナルでサッと確認したい
- ✅ 実験的なサービスを試したい
- ✅ docker-composeライクな設定で管理したい

**起動方法**:

**方法1: supervisord経由（推奨）**
```bash
# Web UIまたはCLIから起動
supervisorctl start process-compose

# TUIが表示される
# Ctrl+C で終了
```

**方法2: 直接起動**
```bash
# コンテナ内で
process-compose -f /etc/process-compose/process-compose.yaml

# または、カスタム設定で起動
process-compose -f ./my-services.yaml
```

**TUI操作**:
- `Tab`: プロセス一覧とログ表示を切り替え
- `↑/↓`: プロセス選択
- `s`: 選択したプロセスを起動
- `r`: 選択したプロセスを再起動
- `k`: 選択したプロセスを停止
- `q`: 終了

---

## ６．ユースケース例

### ケース1: 日常的な開発

```bash
# 1. コンテナ起動（supervisordが自動起動）
docker-compose up -d

# 2. code-serverが自動起動される（supervisord管理）
# http://localhost:4035 でアクセス

# 3. 必要に応じてdifitを起動（supervisord Web UI or CLI）
supervisorctl start difit

# 4. 状態確認
# Web UI: http://localhost:9001
# CLI: supervisorctl status
```

### ケース2: 複数プロダクトの並行開発

```bash
# 1. process-composeを起動（supervisord経由）
supervisorctl start process-compose

# 2. process-compose TUIで各サービスを起動
# - difit: 開発支援ツール
# - product-a dev server
# - product-b dev server

# 3. TUIでログ確認しながら開発

# 4. 終了時はCtrl+Cでprocess-composeを終了
```

### ケース3: 実験的なサービス追加

```bash
# 1. process-compose.yaml を編集
nano /etc/process-compose/process-compose.yaml

# 2. 新しいサービスを追加
processes:
  my-experiment:
    command: "npm run dev"
    working_dir: "/home/<一般ユーザー>/repos/experiment"

# 3. process-composeを再起動
supervisorctl restart process-compose

# 4. TUIで新サービスを起動・確認
```

---

## ７．メリット・デメリット

### メリット

1. **選択肢が豊富**
   - ✅ Web UI（supervisord）とTUI（process-compose）、両方使える
   - ✅ 用途に応じて使い分け可能

2. **適材適所**
   - ✅ 安定稼働はsupervisord、実験はprocess-compose
   - ✅ ブラウザ派もターミナル派も満足

3. **学習機会**
   - ✅ 両方のツールを体験できる
   - ✅ 将来的にどちらかに絞ることも可能

4. **柔軟性**
   - ✅ supervisord.confとprocess-compose.yaml、どちらでもサービス定義可能
   - ✅ サービスごとに適切なツールを選択

### デメリット

1. **複雑性の増加**
   - ⚠️ 2つのツールを管理する必要がある
   - ⚠️ どちらで管理すべきか判断が必要

2. **学習コスト**
   - ⚠️ 両方のツールの使い方を覚える必要がある

3. **リソース消費**
   - ⚠️ process-composeを起動するとリソースを消費（ただし微量）

### トレードオフの評価

**デメリットは許容可能**:
- 開発環境なので複雑性は問題ない
- 両方のツールを学べるのは逆にメリット
- process-composeは必要なときだけ起動すればOK

---

## ８．段階的な導入計画

### Phase 1: supervisord導入（必須）

**目的**: PID 1問題の解決、基本的なプロセス管理

1. Dockerfile修正（supervisordインストール）
2. supervisord.conf作成
3. docker-entrypoint.sh修正
4. docker-compose.yml修正
5. 動作確認

**成果**: Web UIでプロセス管理可能に

---

### Phase 2: process-compose導入（オプション）

**目的**: TUIでの開発効率向上

1. Dockerfile修正（process-composeインストール）
2. process-compose.yaml作成
3. supervisord.confにprocess-compose追加
4. 動作確認

**成果**: TUIでも管理可能に

---

### Phase 3: 運用・最適化

**目的**: 実際の開発で使いながら最適化

1. サービスの振り分け検討（supervisord or process-compose）
2. process-compose.yamlにサービス追加
3. ドキュメント整備

---

## ９．次のステップ

### 実装タスク

- [ ] Dockerfile修正（supervisord + process-composeインストール）
- [ ] `.devcontainer/supervisord/supervisord.conf` 作成
- [ ] `.devcontainer/process-compose/process-compose.yaml` 作成
- [ ] docker-entrypoint.sh修正
- [ ] docker-compose.yml修正（ポート9001, 8080追加）
- [ ] 動作確認
  - [ ] supervisord Web UI（http://localhost:9001）
  - [ ] process-compose TUI
- [ ] ドキュメント更新
  - [ ] `foundations/onboarding/` に使い方ガイド追加

---

## 参考資料

- [Supervisor Documentation](http://supervisord.org/)
- [process-compose GitHub](https://github.com/F1bonacc1/process-compose)
- [process-compose Documentation](https://f1bonacc1.github.io/process-compose/)

---

## 変更履歴

### v6 (2026-01-02)
- supervisord + process-compose のハイブリッド構成を提案
- 両方のツールのメリットを活かす設計
- 使い分けガイド、ユースケース例を追加
- 段階的な導入計画を追加
