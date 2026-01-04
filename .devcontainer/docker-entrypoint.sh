#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Docker Entrypoint: Initializing container..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 1: パーミッション修正
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📁 Phase 1: Fixing permissions for mounted config volumes..."
# List of common config files and directories to fix ownership on
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
    # Check if the file or directory exists before changing ownership
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
    # Docker Socket の現在の所有者とパーミッションを確認
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    DOCKER_SOCK_MODE=$(stat -c '%a' /var/run/docker.sock)

    echo "  Docker socket GID: $DOCKER_SOCK_GID, Mode: $DOCKER_SOCK_MODE"

    # Docker Socket に書き込み権限を付与
    sudo chmod 666 /var/run/docker.sock

    # ユーザーのグループにdockerグループを追加（必要に応じて）
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
    # Atuin設定ディレクトリの作成
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin

    # 設定ファイルが存在しない場合のみデフォルト設定を作成
    if [ ! -f ~/.config/atuin/config.toml ]; then
        echo "  Creating default Atuin config..."
        cat > ~/.config/atuin/config.toml <<'EOF'
# Atuin設定ファイル
# 同期を無効化（必要に応じて有効化）
sync_address = ""
sync_frequency = "0"

# 検索設定
search_mode = "fuzzy"
filter_mode = "host"
filter_mode_shell_up_key_binding = "directory"

# UIカスタマイズ
style = "compact"
inline_height = 25
show_preview = true
show_help = true

# 履歴の設定
history_filter = []
# secrets_filter = true  # パスワードなどの機密情報をフィルタリング

# キーバインド設定
# enter_accept = true  # Enterキーで選択を確定

# 統計情報の表示
show_stats = true

# タイムゾーン設定
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

PROJECT_CONF="/home/${UNAME}/${REPO_NAME}/workloads/supervisord/project.conf"
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
        echo "workloads/supervisord/project.conf validation failed."
        echo "Using seed config (code-server only)."
        echo ""
        echo "To fix and reload:"
        echo "  1. Fix: workloads/supervisord/project.conf"
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
    echo "workloads/supervisord/project.conf not found."
    echo "Using seed config (code-server only)."
    echo ""
    echo "To create and load:"
    echo "  1. Create: workloads/supervisord/project.conf"
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

UNAME=${UNAME:-$(whoami)}
REPO_NAME=${REPO_NAME:-"hagevvashi.info-dev-hub"}

PROJECT_YAML="/home/${UNAME}/${REPO_NAME}/workloads/process-compose/project.yaml"
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
        echo "workloads/process-compose/project.yaml validation failed."
        echo "Using seed config (minimal setup)."
        echo ""
        echo "To fix and reload:"
        echo "  1. Fix: workloads/process-compose/project.yaml"
        echo "  2. Restart: s6-svc -t /run/service/process-compose"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
    fi
else
    echo "  ⚠️  workloads/process-compose/project.yaml not found"
    echo "  Using seed config (minimal setup)"

    sudo mkdir -p /etc/process-compose
    sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
fi

echo "  Using config: ${TARGET_YAML}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 6: 元のコマンドを実行
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Starting supervisord..."

# 元のコマンドを実行
exec "$@"
