# プロセス管理ツールの選定と実装

**作成日**: 2026-01-02
**関連**: [00_Monolithic DevContainerの本質.v2.md](00_Monolithic%20DevContainerの本質.v2.md)

## １．課題（目標とのギャップ）

**現在の実装は「code-server専用コンテナ」であり、Monolithic DevContainerの本来の目的と矛盾している**

### 現状の問題

```dockerfile
# Dockerfile
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth password"]
```

```yaml
# docker-compose.yml
command: code-server --bind-addr 0.0.0.0:4035 --auth password
```

**code-serverがPID 1として起動している状態**

### 具体的な問題点

1. **PID 1が特定のプロセスに専有されている**
   - code-serverは「開発環境の一部」であって「コンテナの主役」ではない
   - code-serverが落ちるとコンテナ全体が停止

2. **複数サービスを並行稼働できない**
   - difit、アプリケーションサーバー等を同時起動できない
   - バックグラウンドプロセスの管理が困難

3. **プロセスの状態が見えない**
   - どのプロセスが動いているのか分からない
   - ログの確認が困難
   - デバッグしづらい

---

## ２．本当に必要な要件

### 開発環境として必要な要件

1. **✅ PID 1問題の解決**
   - code-serverがPID 1を専有するのを避ける
   - プロセス管理ツールがPID 1であるべき

2. **✅ 複数プロセスの管理**
   - code-server、difit、アプリケーションサーバー等を管理
   - 個別に起動・停止できる

3. **✅ プロセスの状態可視化（Web/TUI）**
   - **WebまたはTUIでプロセスの状態を確認できる**
   - どのプロセスが動いているか一目で分かる
   - どのポートでリッスンしているか分かる

4. **✅ ログの確認・デバッグが容易**
   - エラーログが明確に見える
   - 各プロセスのログを個別に確認できる
   - デバッグしやすい

### 不要な要件（過剰設計）

1. **❌ 本番環境との一致性**
   - 本番環境（Kubernetes等）とは構造が異なる
   - 開発環境は開発環境として最適化すべき
   - **本番のことは気にしない**

2. **❌ 軽量性・起動速度**
   - 開発環境なので多少のオーバーヘッドは許容
   - **気にしなくてOK**

3. **❌ プロセスの依存関係管理**
   - 開発者が起動順序を理解すべき
   - 自動管理するとブラックボックス化
   - **あったらいいかもなー程度**

4. **❌ 自動再起動**
   - 開発環境ではエラーを見たい
   - 自動再起動するとエラーログが流れて見えない
   - **手動再起動の方が望ましい**

---

## ３．プロセス管理ツールの比較

### 比較表: 本当に必要な要件に基づく評価

| ツール | 複数プロセス | **Web/TUIモニタリング** | ログ見やすさ | 学習コスト | 実績 | 判定 |
|--------|------------|---------------------|------------|----------|------|------|
| **supervisord** | ✅ | ⭐⭐⭐ **Web UI標準** | ⭐⭐⭐ | ⭐⭐⭐ 易しい | ⭐⭐⭐ | **◎推奨** |
| **PM2** | ✅ | ⭐⭐ Web UI（PM2 Plus） | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ○候補 |
| **process-compose** | ✅ | ⭐⭐ TUI標準 | ⭐⭐⭐ | ⭐⭐ | ⭐ | ○候補 |
| **s6-overlay** | ✅ | ❌ なし | ⭐⭐ | ⭐ | ⭐⭐⭐ | △不適 |
| **systemd** | ✅ | ❌ なし | ⭐⭐⭐ | ⭐ | ⭐⭐⭐ | △過剰 |
| **tini + スクリプト** | ⚠️ 限定的 | ❌ なし | ⭐ | ⭐⭐⭐ | ⭐⭐⭐ | △不十分 |

### 各ツールの詳細

#### 1. supervisord（**推奨**）

**特徴**:
- Python製の定番プロセス管理ツール
- **Web UI標準搭載**
- INI形式の設定ファイル（シンプル）

**メリット**:
- ✅ **Web UIで可視化・操作**（http://localhost:9001）
  - プロセスの起動・停止・再起動をブラウザから操作
  - ログもWeb上で確認可能
- ✅ シンプルで理解しやすい（INI形式）
- ✅ 実績豊富（コンテナ環境での利用実績多数）
- ✅ `autorestart=false` で手動再起動可能（エラーが見える）
- ✅ 特権モード不要

**デメリット**:
- （特になし。今回の要件に完全合致）

**設定例**:
```ini
[inet_http_server]
port=*:9001
username=admin
password=admin

[program:code-server]
command=code-server --bind-addr 0.0.0.0:4035 --auth password
autostart=true
autorestart=false  # 手動再起動

[program:difit]
command=difit
autostart=false  # 手動起動
```

---

#### 2. PM2（Node.js環境なら候補）

**特徴**:
- Node.js製プロセス管理ツール
- Web UI（PM2 Plus）

**メリット**:
- ✅ Web UI（PM2 Plus）
- ✅ Node.js環境と親和性が高い
- ✅ 実績豊富

**デメリット**:
- ⚠️ PM2 Plusのセルフホストは少し手間

---

#### 3. process-compose（TUIで妥協するなら）

**特徴**:
- Go製
- docker-composeライクなYAML
- **TUI標準搭載**

**メリット**:
- ✅ TUI（ターミナルUI）
- ✅ YAML設定（親しみやすい）

**デメリット**:
- ⚠️ Web UIなし（APIのみ提供、UI自作が必要）
- ❌ 実績が少ない（新しいツール）

---

#### 4. s6-overlay（不適）

**理由**: Webモニタリングなし
- コンテナネイティブで軽量だが、今回の要件（Web/TUI可視化）を満たさない

---

#### 5. systemd（過剰）

**理由**: Webモニタリングなし、過剰設計
- 機能豊富だが、Webモニタリングがなく、今回の要件に合わない
- 特権モード必要、複雑

---

#### 6. tini + スクリプト（不十分）

**理由**: プロセス管理機能が弱い
- PID 1問題は解決できるが、プロセスの可視化・管理ができない

---

## ４．推奨: supervisord

### 推奨理由

1. **要件に完全合致**
   - ✅ PID 1問題を解決
   - ✅ 複数プロセス管理
   - ✅ **Web UIで可視化・操作**
   - ✅ ログ見やすい

2. **開発環境として適切**
   - ✅ `autorestart=false` で手動再起動（エラーが見える）
   - ✅ `autostart=false` で手動起動（必要なときだけ）
   - ✅ シンプルで理解しやすい

3. **実装コストが低い**
   - ✅ INI形式の設定（簡単）
   - ✅ 学習コスト低い
   - ✅ 実績豊富

---

## ５．実装内容

### Dockerfile

```dockerfile
# supervisordインストール
RUN apt-get update && \
    apt-get install -y supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ... 既存のツールインストール処理 ...

# supervisord設定をコピー
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# supervisordをPID 1として起動
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

### supervisord.conf

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

# docker-entrypoint.sh を最初に実行（初期化処理）
[program:docker-entrypoint]
command=/usr/local/bin/docker-entrypoint.sh
user=<一般ユーザー>
autostart=true
autorestart=false
startsecs=0
priority=1
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# code-server
[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>
autostart=true
autorestart=false
priority=10
environment=CODE_SERVER_PORT="4035",HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# difit（必要なときだけ起動）
[program:difit]
command=/home/<一般ユーザー>/.asdf/shims/difit
user=<一般ユーザー>
directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>
autostart=false
autorestart=false
priority=20
environment=HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

### docker-entrypoint.sh修正

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Running docker-entrypoint initialization..."

# 既存の初期化処理
# ... パーミッション修正、Docker Socket調整、Atuin初期化等 ...

echo "✅ Docker entrypoint initialization completed"

# supervisordのプログラムとして実行される場合は、ここで終了
# （バックグラウンドサービスではなく、一度だけ実行される初期化処理）
exit 0
```

### docker-compose.yml修正

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
    user: "${UID:-1000}:${GID:-1000}"
    tty: true
    # commandは削除（DockerfileのCMDを使う）

volumes:
  repos:
    external: true
```

---

## ６．利用方法

### Web UIでのプロセス管理

1. **ブラウザでアクセス**
   ```
   http://localhost:9001
   ```

2. **ログイン**
   - Username: `admin`
   - Password: `admin`

3. **できること**
   - プロセスの状態確認（動作中/停止中）
   - プロセスの起動・停止・再起動
   - ログの確認（Tail -f Log ボタン）

### CLIでの操作（オプション）

コンテナ内で以下のコマンドも使用可能:

```bash
# 状態確認
supervisorctl status

# difitを起動
supervisorctl start difit

# code-serverを再起動
supervisorctl restart code-server

# ログ確認
supervisorctl tail -f code-server
```

---

## ７．次のステップ

### 実装タスク

1. **Dockerfile修正**
   - supervisordインストール追加
   - CMD変更

2. **supervisord.conf作成**
   - `.devcontainer/supervisord/` ディレクトリ作成
   - 設定ファイル配置

3. **docker-entrypoint.sh修正**
   - 終了処理追加

4. **docker-compose.yml修正**
   - ポート9001追加
   - command削除

5. **動作確認**
   - コンテナ起動
   - Web UI（http://localhost:9001）でプロセス確認
   - ログの視認性確認

6. **ドキュメント更新**
   - `foundations/onboarding/` にsupervisord使い方ガイド追加

---

## 参考資料

- [Supervisor Documentation](http://supervisord.org/)
- [supervisord in Docker - Best Practices](https://docs.docker.com/config/containers/multi-service_container/)

---

## 変更履歴

### 2026-01-02
- 初版作成
- 25_2_systemd_vs_process_compose_analysis.md と 25_process_management_proposal.md を統合
- 不要な要件（本番一致性、軽量性、依存関係管理）を削除
- supervisordに一本化
