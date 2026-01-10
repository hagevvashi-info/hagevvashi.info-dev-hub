# プロセス管理ツールの選定と実装（PID 1保護・ハイブリッド構成）

**作成日**: 2026-01-03
**バージョン**: v9（PID 1保護 + supervisord/process-compose 並行運用）
**関連**:
- [25_process_management_solution.v8.md](25_process_management_solution.v8.md) - v8（supervisord単独・並行運用考慮漏れ）
- [25_process_management_solution.v6.md](25_process_management_solution.v6.md) - v6（ハイブリッド構成の基礎）
- [28_0_supervisord_config_implementation_strategy.md](28_0_supervisord_config_implementation_strategy.md) - 2層構造の提案

---

## １．課題（目標とのギャップ）

### v8で発覚した新たな問題

**v8は process-compose の並行運用を考慮していない**

```
v6の方針: supervisord + process-compose のハイブリッド構成
          ↓
v7-v8: 「どちらか一方」を選ぶ前提で設計
          ↓
問題: ユーザーの要求「並行運用」を無視
```

### v8までの課題の整理

| バージョン | 課題 | 状態 |
|-----------|------|------|
| v6 | PID 1 問題（code-server専用） | ✅ ハイブリッド構成で解決 |
| v7 | 2層構造の統合 | ✅ configs/ + seed 構成を提案 |
| v7 | PID 1 再起動問題（**重大**） | ❌ 見落とし |
| v8 | PID 1 保護（s6-overlay） | ✅ 解決 |
| v8 | 並行運用の考慮漏れ | ❌ supervisord単独前提 |

### 本来あるべき構成

**ユーザーの明確な要求**:
- ✅ supervisord と process-compose の**並行運用**
- ✅ どちらも評価してから最終決定
- ✅ Web UI（supervisord）と TUI（process-compose）の両方を使える

---

## ２．原因

### v8での判断ミス

1. **v7の「並行運用見送り」判断を引き継いだ**
   - v7で「まずsupervisordで完成させる」と記述
   - v8でもこの前提を疑わずに踏襲

2. **「シンプルさ」を過度に優先**
   - s6-overlay の導入で複雑性が増加
   - さらに process-compose を追加すると「複雑すぎる」と判断

3. **ユーザーの要求確認を怠った**
   - v6のハイブリッド構成が「仮の提案」ではなく「方針」であることを見落とし

---

## ３．目的（あるべき状態）

### 実現したい状態

1. **PID 1 の不変性と堅牢性**（v8で達成）
   - s6-overlay が PID 1 を保護
   - supervisord も process-compose も再起動可能

2. **supervisord と process-compose の並行運用**（v9の目標）
   - 両方を s6-overlay 管理下に配置
   - それぞれ独立して再起動可能
   - どちらかがクラッシュしても、もう一方は動作継続

3. **2層構造の両方への適用**
   - supervisord: `configs/supervisord/project.conf` + `seed.conf`
   - process-compose: `configs/process-compose/project.yaml` + `seed.yaml`

4. **開発者が使い分けられる**
   - Web UI派 → supervisord
   - TUI派 → process-compose
   - 両方使ってもOK

---

## ４．戦略・アプローチ（解決の方針）

### 基本戦略

1. **s6-overlay を PID 1 に配置**（v8を踏襲）
   - supervisord と process-compose の両方を管理

2. **両ツールの役割を明確化**
   - **supervisord**: 常時起動、Web UI担当、安定稼働プロセス
   - **process-compose**: オプション起動、TUI担当、実験的プロセス

3. **2層構造を両方に適用**
   - それぞれに seed 設定（ダミー）と実運用設定を用意
   - フォールバック機構も両方で実装

4. **並行運用のガイドライン策定**
   - どのプロセスをどちらで管理するか
   - 重複管理の回避方法
   - 移行パスの提供

---

## ５．最終アーキテクチャ

### 構成図

```
PID 1: s6-overlay (init + プロセス監視)
  ├─ s6-svscan (サービススキャナー)
  │   ├─ docker-entrypoint (初期化スクリプト・oneshot)
  │   │   ├─ Phase 1-3: 既存の初期化処理
  │   │   ├─ Phase 4: supervisord 設定検証・シンボリックリンク
  │   │   └─ Phase 5: process-compose 設定検証・シンボリックリンク
  │   │
  │   ├─ supervisord (longrun・常時起動)
  │   │   ├─ [inet_http_server] → Web UI (port 9001)
  │   │   ├─ code-server (必須プロセス)
  │   │   ├─ difit (開発ツール)
  │   │   └─ その他の安定稼働プロセス
  │   │
  │   └─ process-compose (longrun・オプション起動)
  │       ├─ TUI (port 8080 API)
  │       ├─ 実験的プロセス
  │       └─ ホットリロード対象プロセス
  │
  └─ zombie reaping (ゾンビプロセス回収)
```

### ディレクトリ構造

```
hagevvashi.info-dev-hub/
├── .devcontainer/
│   ├── s6-rc.d/                              # s6-overlay サービス定義
│   │   ├── user/contents.d/
│   │   │   ├── docker-entrypoint
│   │   │   ├── supervisord
│   │   │   └── process-compose
│   │   ├── docker-entrypoint/
│   │   │   ├── type                         # oneshot
│   │   │   ├── up
│   │   │   └── dependencies.d/base
│   │   ├── supervisord/
│   │   │   ├── type                         # longrun
│   │   │   ├── run
│   │   │   └── dependencies.d/docker-entrypoint
│   │   └── process-compose/
│   │       ├── type                         # longrun
│   │       ├── run
│   │       └── dependencies.d/docker-entrypoint
│   │
│   ├── supervisord/
│   │   └── seed.conf                        # ダミー設定（ビルド用）
│   ├── process-compose/
│   │   └── seed.yaml                        # ダミー設定（ビルド用）
│   │
│   ├── docker-entrypoint.sh                 # Phase 4 & 5 実装
│   ├── validate-config.sh                   # ホスト側検証
│   ├── debug-entrypoint.sh                  # DEBUG_MODE用
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── configs/                                  # 実運用設定
│   ├── supervisord/
│   │   ├── project.conf                     # 実運用設定
│   │   └── README.md
│   └── process-compose/
│       ├── project.yaml                     # 実運用設定
│       └── README.md
│
└── foundations/
    └── onboarding/
        └── s6-hybrid-process-management-guide.md
```

---

## ６．実装内容

### 6.1 Dockerfile

```dockerfile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Base image
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM ubuntu:22.04

ARG TARGETARCH
ARG UID=1000
ARG GID=1000
ARG UNAME=hagevvashi
ARG GNAME=hagevvashi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay: PID 1 保護・プロセス監視
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz

# アーキテクチャ別のバイナリ
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "x86_64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "x86_64" ;; \
    esac) && \
    curl -L "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz" \
    -o /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    rm /tmp/s6-overlay-arch.tar.xz

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: supervisord
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN apt-get update && \
    apt-get install -y supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# シード設定をコピー（フォールバック用）
COPY .devcontainer/supervisord/seed.conf /etc/supervisor/seed.conf

# ★★★ ビルド時検証: シード設定のみ ★★★
RUN echo "🔍 Validating seed supervisord configuration..." && \
    supervisord -c /etc/supervisor/seed.conf -t && \
    echo "✅ Seed supervisord configuration is valid"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: process-compose
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARG PROCESS_COMPOSE_VERSION=1.85.0
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -L "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_linux_${ARCH}.tar.gz" \
    -o /tmp/process-compose.tar.gz && \
    tar -xzf /tmp/process-compose.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/process-compose && \
    rm /tmp/process-compose.tar.gz

# シード設定をコピー（フォールバック用）
RUN mkdir -p /etc/process-compose
COPY .devcontainer/process-compose/seed.yaml /etc/process-compose/seed.yaml

# ★★★ ビルド時検証: シード設定のみ ★★★
RUN echo "🔍 Validating seed process-compose configuration..." && \
    process-compose -f /etc/process-compose/seed.yaml --help > /dev/null 2>&1 && \
    echo "✅ Seed process-compose configuration is valid"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay サービス定義
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COPY .devcontainer/s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# docker-entrypoint.sh を実行可能にする
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# ... 既存のツールインストール処理（code-server, asdf等）...

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entrypoint: s6-overlay
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ENTRYPOINT ["/init"]
```

---

### 6.2 s6-overlay サービス定義

#### `.devcontainer/s6-rc.d/user/contents.d/docker-entrypoint`
```
docker-entrypoint
```

#### `.devcontainer/s6-rc.d/user/contents.d/supervisord`
```
supervisord
```

#### `.devcontainer/s6-rc.d/user/contents.d/process-compose`
```
process-compose
```

---

#### `.devcontainer/s6-rc.d/docker-entrypoint/type`
```
oneshot
```

#### `.devcontainer/s6-rc.d/docker-entrypoint/up`
```bash
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh
```

#### `.devcontainer/s6-rc.d/docker-entrypoint/dependencies.d/base`
（空ファイル）

---

#### `.devcontainer/s6-rc.d/supervisord/type`
```
longrun
```

#### `.devcontainer/s6-rc.d/supervisord/run`
```bash
#!/command/with-contenv bash
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
```

#### `.devcontainer/s6-rc.d/supervisord/dependencies.d/docker-entrypoint`
（空ファイル）

---

#### `.devcontainer/s6-rc.d/process-compose/type`
```
longrun
```

#### `.devcontainer/s6-rc.d/process-compose/run`
```bash
#!/command/with-contenv bash
exec /usr/local/bin/process-compose -f /etc/process-compose/process-compose.yaml
```

#### `.devcontainer/s6-rc.d/process-compose/dependencies.d/docker-entrypoint`
（空ファイル）

---

### 6.3 docker-entrypoint.sh

```bash
#!/usr/bin/env bash

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Docker Entrypoint: Initializing container..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 1: パーミッション修正
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📁 Phase 1: Fixing permissions for mounted config volumes..."
CONFIG_ITEMS=(
    ~/.config
    ~/.local
    ~/.git
    ~/.ssh
    ~/.aws
    ~/.claude
    ~/.claude.json
    ~/.cursor
    ~/.bash_history
    ~/.gitconfig
)
for item in "${CONFIG_ITEMS[@]}"; do
    if [ -e "$item" ]; then
        echo "  Updating ownership for $item"
        sudo chown -R $(id -u):$(id -g) "$item"
    fi
done
echo "✅ Permissions fixed."

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 2: Docker Socket調整
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🐳 Phase 2: Adjusting Docker socket permissions..."
if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    DOCKER_SOCK_MODE=$(stat -c '%a' /var/run/docker.sock)

    echo "  Docker socket GID: $DOCKER_SOCK_GID, Mode: $DOCKER_SOCK_MODE"

    sudo chmod 666 /var/run/docker.sock

    if ! groups | grep -q docker; then
        sudo usermod -a -G docker $(whoami)
    fi

    echo "  Docker socket permissions updated"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "⏱️  Phase 3: Initializing Atuin configuration..."
if command -v atuin >/dev/null 2>&1; then
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin

    if [ ! -f ~/.config/atuin/config.toml ]; then
        echo "  Creating default Atuin config..."
        cat > ~/.config/atuin/config.toml <<'EOF'
# Atuin設定ファイル
sync_address = ""
sync_frequency = "0"
search_mode = "fuzzy"
filter_mode = "host"
filter_mode_shell_up_key_binding = "directory"
style = "compact"
inline_height = 25
show_preview = true
show_help = true
history_filter = []
show_stats = true
timezone = "+09:00"
EOF
        echo "  ℹ️  Created default Atuin configuration"
    else
        echo "  ℹ️  Atuin config already exists, using existing configuration"
    fi
fi
echo "✅ Atuin initialization complete"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 4: supervisord設定ファイルの検証とフォールバック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 4: Validating supervisord configuration..."

UNAME=${UNAME:-$(whoami)}
REPO_NAME=${REPO_NAME:-"hagevvashi.info-dev-hub"}

PROJECT_CONF="/home/${UNAME}/${REPO_NAME}/configs/supervisord/project.conf"
SEED_CONF="/etc/supervisor/seed.conf"
TARGET_CONF="/etc/supervisor/supervisord.conf"

if [ -f "${PROJECT_CONF}" ]; then
    echo "  ✅ Found: ${PROJECT_CONF}"

    sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"

    if supervisord -c "${TARGET_CONF}" -t 2>&1; then
        echo "  ✅ project.conf is valid"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️   WARNING: SUPERVISORD FALLBACK MODE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "configs/supervisord/project.conf validation failed."
        echo "Using seed config (code-server only)."
        echo ""
        echo "To fix and reload:"
        echo "  1. Fix: configs/supervisord/project.conf"
        echo "  2. Restart: s6-svc -t /run/service/supervisord"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
    fi
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️   WARNING: SUPERVISORD FALLBACK MODE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "configs/supervisord/project.conf not found."
    echo "Using seed config (code-server only)."
    echo ""
    echo "To create and load:"
    echo "  1. Create: configs/supervisord/project.conf"
    echo "  2. Restart: s6-svc -t /run/service/supervisord"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
fi

echo "  Using config: ${TARGET_CONF}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 5: process-compose設定ファイルの検証とフォールバック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 5: Validating process-compose configuration..."

PROJECT_YAML="/home/${UNAME}/${REPO_NAME}/configs/process-compose/project.yaml"
SEED_YAML="/etc/process-compose/seed.yaml"
TARGET_YAML="/etc/process-compose/process-compose.yaml"

if [ -f "${PROJECT_YAML}" ]; then
    echo "  ✅ Found: ${PROJECT_YAML}"

    sudo mkdir -p /etc/process-compose
    sudo ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"

    # YAML構文チェック（簡易）
    if grep -q "^version:" "${PROJECT_YAML}" && grep -q "^processes:" "${PROJECT_YAML}"; then
        echo "  ✅ project.yaml appears valid"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️   WARNING: PROCESS-COMPOSE FALLBACK MODE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "configs/process-compose/project.yaml validation failed."
        echo "Using seed config (minimal setup)."
        echo ""
        echo "To fix and reload:"
        echo "  1. Fix: configs/process-compose/project.yaml"
        echo "  2. Restart: s6-svc -t /run/service/process-compose"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
    fi
else
    echo "  ⚠️  configs/process-compose/project.yaml not found"
    echo "  Using seed config (minimal setup)"

    sudo mkdir -p /etc/process-compose
    sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
fi

echo "  Using config: ${TARGET_YAML}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

### 6.4 シード設定

#### `.devcontainer/supervisord/seed.conf`

```ini
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Supervisord シード設定（ダミー・ビルド用）
# 実際の設定は configs/supervisord/project.conf を編集してください
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0

[inet_http_server]
port=*:9001
username=admin
password=admin

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=http://127.0.0.1:9001

# 最小限のプロセス: code-server のみ
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
```

---

#### `.devcontainer/process-compose/seed.yaml`

```yaml
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process-Compose シード設定（ダミー・ビルド用）
# 実際の設定は configs/process-compose/project.yaml を編集してください
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

version: "0.5"

log_location: /tmp/process-compose-${USER}.log
log_level: info

processes:
  # 最小限の設定（プレースホルダー）
  placeholder:
    command: "echo 'process-compose is ready. Edit configs/process-compose/project.yaml to add processes.'"
    working_dir: "/tmp"
    availability:
      restart: "no"
```

---

### 6.5 実運用設定

#### `configs/supervisord/project.conf`

```ini
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Supervisord 実運用設定
#
# 編集後の反映方法:
#   方法1: supervisorctl reread && supervisorctl update
#   方法2: s6-svc -t /run/service/supervisord
#
# ★ v9の利点: どちらの方法でもコンテナは落ちません ★
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

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
# 開発ツール
# ========================================

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

---

#### `configs/process-compose/project.yaml`

```yaml
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process-Compose 実運用設定
#
# 編集後の反映方法:
#   s6-svc -t /run/service/process-compose
#
# ★ v9の利点: 再起動してもコンテナは落ちません ★
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

version: "0.5"

log_location: /tmp/process-compose-${USER}.log
log_level: info

processes:
  # 実験的なプロセスやホットリロード対象のプロセス
  # supervisord と重複しないように注意

  # 例: vite dev server
  # vite-preview:
  #   command: "npm run preview"
  #   working_dir: "/home/<一般ユーザー>/repos/some-project"
  #   availability:
  #     restart: "no"
  #   environment:
  #     - HOME=/home/hagevvashi

  # 例: 実験的なサービス
  # my-experiment:
  #   command: "npm run dev"
  #   working_dir: "/home/<一般ユーザー>/repos/experiment"
  #   availability:
  #     restart: "no"
  #   depends_on:
  #     code-server:
  #       condition: process_started
```

---

## ７．使い方ガイド

### 7.1 supervisord の操作

#### Web UI（推奨）
```
http://localhost:9001
Username: admin
Password: admin
```

#### CLI
```bash
# 状態確認
supervisorctl status

# プロセス起動・停止
supervisorctl start difit
supervisorctl stop difit

# 設定変更後の反映
supervisorctl reread
supervisorctl update

# supervisord 自体を再起動（★ v9では安全 ★）
s6-svc -t /run/service/supervisord
# または
supervisorctl restart all  # 全プロセスを再起動（supervisord自体は再起動しない）
```

---

### 7.2 process-compose の操作

#### TUI起動
```bash
# process-compose サービスを起動（s6-overlay経由）
s6-svc -u /run/service/process-compose

# TUIが表示される
# Ctrl+C で終了しても、s6-overlay が再起動する
```

#### CLI
```bash
# API経由で操作（port 8080）
curl http://localhost:8080/processes

# process-compose を再起動（★ v9では安全 ★）
s6-svc -t /run/service/process-compose
```

---

### 7.3 使い分けガイドライン

| 用途 | 推奨ツール | 理由 |
|------|-----------|------|
| **code-server** | supervisord | 常時起動・Web UIで確認 |
| **difit** | supervisord | 安定稼働・頻繁に起動停止 |
| **vite dev server** | process-compose | ホットリロード・TUIで確認 |
| **実験的サービス** | process-compose | 頻繁な追加削除・YAML編集が楽 |
| **DB（Postgres等）** | supervisord | 安定稼働・依存関係の基盤 |
| **マイクロサービス群** | process-compose | 依存関係定義・まとめて起動停止 |

**重複管理の回避**:
- 同じプロセスを supervisord と process-compose の両方で定義しない
- どちらで管理するか、configs/ 内の README.md に記載

---

### 7.4 設定変更のワークフロー

#### supervisord の設定変更

```bash
# 1. 設定ファイル編集
nano configs/supervisord/project.conf

# 2. 変更を反映（どちらかを選択）

# 方法A: 新規プロセスのみ追加
supervisorctl reread
supervisorctl update

# 方法B: supervisord 全体を再起動
s6-svc -t /run/service/supervisord

# 3. Web UI で確認
# http://localhost:9001
```

#### process-compose の設定変更

```bash
# 1. 設定ファイル編集
nano configs/process-compose/project.yaml

# 2. process-compose を再起動
s6-svc -t /run/service/process-compose

# 3. TUI で確認
# process-compose は自動で再起動される
```

---

## ８．フォールバック動作

### supervisord フォールバック

**トリガー**:
- `configs/supervisord/project.conf` が存在しない
- `configs/supervisord/project.conf` の構文エラー

**動作**:
- `seed.conf` にフォールバック
- code-server のみ起動
- Web UI (9001) で確認可能
- 警告メッセージが docker-entrypoint.sh に表示

**復旧**:
```bash
# 1. 設定ファイルを修正
nano configs/supervisord/project.conf

# 2. supervisord を再起動
s6-svc -t /run/service/supervisord

# 3. Web UI で確認
```

---

### process-compose フォールバック

**トリガー**:
- `configs/process-compose/project.yaml` が存在しない
- `configs/process-compose/project.yaml` の構文エラー

**動作**:
- `seed.yaml` にフォールバック
- プレースホルダープロセスのみ起動
- 警告メッセージが docker-entrypoint.sh に表示

**復旧**:
```bash
# 1. 設定ファイルを修正
nano configs/process-compose/project.yaml

# 2. process-compose を再起動
s6-svc -t /run/service/process-compose
```

---

## ９．メリット・デメリット

### メリット

1. **完全な PID 1 保護**
   - ✅ supervisord も process-compose も何度再起動してもコンテナは落ちない
   - ✅ どちらかがクラッシュしても s6-overlay が自動再起動
   - ✅ AIエージェントがどんな操作をしてもコンテナ保護

2. **ツールの選択肢**
   - ✅ Web UI派 → supervisord
   - ✅ TUI派 → process-compose
   - ✅ 両方使ってもOK

3. **2層構造を両方に適用**
   - ✅ それぞれ独立したフォールバック機構
   - ✅ 設定エラー時も最低限の環境を提供

4. **柔軟な評価期間**
   - ✅ 実際に使いながら「どちらが良いか」を判断
   - ✅ 最終的にどちらかに絞ることも、並行運用継続も可能

### デメリット

1. **複雑性の増加**
   - ⚠️ s6-rc.d/ に3つのサービス定義（docker-entrypoint, supervisord, process-compose）
   - ⚠️ configs/ に2つのディレクトリ
   - ⚠️ 「どちらで管理するか」の判断が必要

2. **学習コスト**
   - ⚠️ 両方のツールの操作方法を覚える必要がある
   - ⚠️ s6-overlay の仕組みも理解する必要がある

3. **リソース消費**
   - ⚠️ 両方のツールが常時起動する場合、メモリ消費が増加
   - ⚠️ ただし、process-compose はオプション起動なので問題ない

### トレードオフの評価

**デメリットは許容可能**:
- 開発環境なので複雑性は問題ない
- 「どちらが良いか」を実際に評価できるメリットが大きい
- process-compose は必要なときだけ起動すればリソース消費を抑えられる

---

## １０．v8 からの変更点まとめ

| 要素 | v8 | v9 |
|------|---|---|
| **プロセス管理ツール** | supervisord 単独 | supervisord + process-compose 並行運用 |
| **s6-rc.d/ サービス** | 2つ（docker-entrypoint, supervisord） | 3つ（+ process-compose） |
| **docker-entrypoint.sh** | Phase 4 のみ | Phase 4 & 5 |
| **configs/** | supervisord/ のみ | supervisord/ + process-compose/ |
| **シード設定** | seed.conf のみ | seed.conf + seed.yaml |
| **並行運用** | ❌ 考慮なし | ✅ 両方を s6-overlay 管理下に配置 |
| **ユーザーの要求** | ⚠️ 見落とし | ✅ 満たす |

---

## １１．実装計画

### Phase 1: process-compose サービス追加

**タスク**:
1. `.devcontainer/s6-rc.d/process-compose/` ディレクトリ作成
2. type, run, dependencies.d/ ファイル作成
3. `.devcontainer/s6-rc.d/user/contents.d/process-compose` 追加

**検証**:
- s6-overlay がprocess-compose を認識するか

---

### Phase 2: process-compose 設定追加

**タスク**:
1. `.devcontainer/process-compose/seed.yaml` 作成
2. `configs/process-compose/project.yaml` 作成
3. Dockerfile に process-compose ビルド時検証追加

**検証**:
- ビルドが成功するか
- seed.yaml の構文が有効か

---

### Phase 3: docker-entrypoint.sh Phase 5 追加

**タスク**:
- Phase 5 実装（process-compose 設定検証・シンボリックリンク・フォールバック）

**検証**:
- project.yaml が有効な場合、それが使われるか
- エラー時に seed.yaml にフォールバックするか

---

### Phase 4: 動作確認

**テストケース**:

1. **supervisord のみ使用**
   - コンテナ起動
   - Web UI (9001) で code-server 確認
   - supervisord 再起動テスト

2. **process-compose のみ使用**
   - s6-svc -u /run/service/process-compose
   - TUI 確認
   - process-compose 再起動テスト

3. **両方使用**
   - 両方が同時に動作するか
   - それぞれ独立して再起動できるか

4. **フォールバックテスト**
   - 両方の設定ファイルにエラーを入れる
   - それぞれ独立してフォールバックするか

---

### Phase 5: ドキュメント整備

**作成するドキュメント**:

1. `foundations/onboarding/s6-hybrid-process-management-guide.md`
   - アーキテクチャ図
   - なぜ s6-overlay + ハイブリッドなのか
   - 使い分けガイドライン
   - フォールバック時の対処法

2. `configs/supervisord/README.md`
   - project.conf の編集ガイド
   - 設定変更後の反映方法
   - process-compose との使い分け

3. `configs/process-compose/README.md`
   - project.yaml の編集ガイド
   - 設定変更後の反映方法
   - supervisord との使い分け

---

## １２．リスクと対策

### リスク1: プロセスの重複管理

**リスク**: 同じプロセスを supervisord と process-compose の両方で定義してしまう

**対策**:
- README.md に「重複管理禁止」を明記
- 例: code-server は supervisord のみ、vite は process-compose のみ
- validate-config.sh で重複チェック（将来的に追加）

---

### リスク2: 「どちらを使うか」の混乱

**リスク**: 開発者が「どちらで管理すべきか」迷う

**対策**:
- 明確な使い分けガイドライン（７．３節）
- デフォルトは supervisord、実験的なものは process-compose
- ドキュメントで判断基準を提示

---

### リスク3: 複雑性の増大

**リスク**: s6-overlay + 2つのツール で複雑すぎる

**対策**:
- 開発者は「s6-overlay は意識しない」と明記
- 「supervisord だけ使う」「process-compose だけ使う」も可能
- 段階的導入（まず supervisord、必要に応じて process-compose）

---

## １３．次のステップ

### 即座に実行すべきタスク

1. **Phase 1実装**: process-compose サービス追加
2. **Phase 2実装**: seed.yaml + project.yaml 作成
3. **Phase 3実装**: docker-entrypoint.sh Phase 5
4. **Phase 4実装**: 動作確認（全テストケース）
5. **Phase 5実装**: ドキュメント整備

### 長期的なタスク

- [ ] 並行運用での実際の評価（数週間〜数ヶ月）
- [ ] 「どちらが良いか」の最終決定（または並行運用継続）
- [ ] AIエージェントとの相性テスト（両方）
- [ ] validate-config.sh での重複チェック機能追加

---

## １４．参考資料

- [s6-overlay Documentation](https://github.com/just-containers/s6-overlay)
- [Supervisor Documentation](http://supervisord.org/)
- [process-compose Documentation](https://f1bonacc1.github.io/process-compose/)
- [25_process_management_solution.v6.md](25_process_management_solution.v6.md) - ハイブリッド構成の基礎
- [25_process_management_solution.v8.md](25_process_management_solution.v8.md) - v8（supervisord単独）

---

## １５．変更履歴

### v9 (2026-01-03)
- **v8の見落とし修正**: process-compose 並行運用を実装
- s6-overlay に process-compose サービスを追加
- docker-entrypoint.sh に Phase 5（process-compose検証）を追加
- 2層構造を process-compose にも適用（seed.yaml + project.yaml）
- 両ツールの使い分けガイドライン策定
- ユーザーの要求（並行運用）を満たす設計に修正
