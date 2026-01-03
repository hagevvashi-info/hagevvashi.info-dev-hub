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
# Phase 4: supervisord設定ファイルの検証
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 4: Validating supervisord configuration..."

# 環境変数から値を取得（フォールバック付き）
UNAME=${UNAME:-$(whoami)}
REPO_NAME=${REPO_NAME:-"hagevvashi.info-dev-hub"}

# マウントされた設定ファイルのパス
SUPERVISORD_CONF_SOURCE="/home/${UNAME}/${REPO_NAME}/.devcontainer/supervisord/supervisord.conf"
SUPERVISORD_CONF_TARGET="/etc/supervisor/supervisord.conf"

# 設定ファイルの存在確認
if [ ! -f "${SUPERVISORD_CONF_SOURCE}" ]; then
    echo "❌ Error: supervisord.conf not found at ${SUPERVISORD_CONF_SOURCE}"
    echo ""
    echo "Please ensure:"
    echo "  1. The repository is properly bind-mounted"
    echo "  2. The file exists in .devcontainer/supervisord/supervisord.conf"
    echo ""
    exit 1
fi

echo "  ✅ Found: ${SUPERVISORD_CONF_SOURCE}"

# シンボリックリンク作成
echo "  Creating symlink: ${SUPERVISORD_CONF_TARGET} -> ${SUPERVISORD_CONF_SOURCE}"
sudo ln -sf "${SUPERVISORD_CONF_SOURCE}" "${SUPERVISORD_CONF_TARGET}"

# ★★★ 起動前の必須検証（Fail Fast） ★★★
echo "  Validating configuration syntax..."
if ! supervisord -c "${SUPERVISORD_CONF_TARGET}" -t 2>&1; then
    echo ""
    echo "❌ Error: supervisord.conf validation failed"
    echo ""
    echo "Please check the configuration file:"
    echo "  ${SUPERVISORD_CONF_SOURCE}"
    echo ""
    echo "Common issues:"
    echo "  - Syntax errors in .conf file"
    echo "  - Missing required sections ([supervisord], etc.)"
    echo "  - Invalid program commands"
    echo ""
    exit 1
fi

echo "  ✅ supervisord.conf is valid"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 5: process-compose設定ファイルのセットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 5: Setting up process-compose configuration..."

PROCESS_COMPOSE_YAML_SOURCE="/home/${UNAME}/${REPO_NAME}/.devcontainer/process-compose/process-compose.yaml"
PROCESS_COMPOSE_YAML_TARGET="/etc/process-compose/process-compose.yaml"

if [ -f "${PROCESS_COMPOSE_YAML_SOURCE}" ]; then
    echo "  ✅ Found: ${PROCESS_COMPOSE_YAML_SOURCE}"
    sudo mkdir -p /etc/process-compose
    sudo ln -sf "${PROCESS_COMPOSE_YAML_SOURCE}" "${PROCESS_COMPOSE_YAML_TARGET}"
    echo "  ✅ process-compose.yaml symlink created"
else
    echo "  ⚠️  Warning: ${PROCESS_COMPOSE_YAML_SOURCE} not found"
fi

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
