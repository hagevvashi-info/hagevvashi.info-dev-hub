#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2



set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 0: 環境変数の読み込み
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay が配置した環境変数を読み込む
if [ -d /run/s6/container_environment ]; then
    for file in /run/s6/container_environment/*; do
        [ -f "$file" ] && export "$(basename "$file")=$(cat "$file")"
    done
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Docker Entrypoint: Initializing container"
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
        chown -R ${UNAME}:${GNAME} "$item"
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
        sudo usermod -a -G docker ${UNAME}
    fi

    echo "  Docker socket permissions updated"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化（削除）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 注記: Atuin 初期化は .bashrc_custom の初回ログイン時に実行されます
# 理由: docker-entrypoint は root で実行されるため、ユーザーコンテキストでの
#       初期化は .bashrc で行う方が適切です
# 参照: 25_6_22_docker_entrypoint_user_context_issue.md
#
# 重要な制約:
#   docker-entrypoint には root 権限が必要な操作のみを記述すること
#   一般ユーザーコンテキストが必要な操作を記述すると、
#   s6-overlay の環境変数展開問題により失敗します


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 4: supervisord設定ファイルの検証とフォールバック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 4: Validating supervisord configuration..."

UNAME=${UNAME:-$(whoami)}
REPO_NAME=${REPO_NAME}

PROJECT_CONF="/home/${UNAME}/${REPO_NAME}/workloads/supervisord/project.conf"
SEED_CONF="/etc/supervisor/seed.conf"
TARGET_CONF="/etc/supervisor/supervisord.conf"

if [ -f "${PROJECT_CONF}" ]; then
    echo "  ✅ Found: ${PROJECT_CONF}"

    sudo rm -f "${TARGET_CONF}"
    sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"

    # 設定ファイルの基本的な構文チェック（静的検証）
    if grep -q "\[supervisord\]" "${PROJECT_CONF}" && grep -q "\[supervisorctl\]" "${PROJECT_CONF}"; then
        echo "  ✅ project.conf appears valid"
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
REPO_NAME=${REPO_NAME}

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
echo "✅ docker-entrypoint.sh finished."
echo "   s6-overlay will now start supervisord and process-compose as longrun services."
echo ""

# Phase 6削除: s6-overlayがsupervisordとprocess-composeを起動する
