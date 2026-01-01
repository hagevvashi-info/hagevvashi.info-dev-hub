#!/usr/bin/env bash

set -euo pipefail

# Fix permissions for mounted user config directories
echo "Fixing permissions for mounted config volumes..."
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
        echo "Updating ownership for $item"
        sudo chown -R $(id -u):$(id -g) "$item"
    fi
done
echo "✅ Permissions fixed."

# Docker Socket のパーミッションを動的に調整
if [ -S /var/run/docker.sock ]; then
    # Docker Socket の現在の所有者とパーミッションを確認
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    DOCKER_SOCK_MODE=$(stat -c '%a' /var/run/docker.sock)

    echo "Docker socket GID: $DOCKER_SOCK_GID, Mode: $DOCKER_SOCK_MODE"

    # Docker Socket に書き込み権限を付与
    sudo chmod 666 /var/run/docker.sock

    # ユーザーのグループにdockerグループを追加（必要に応じて）
    if ! groups | grep -q docker; then
        sudo usermod -a -G docker $(whoami)
    fi

    echo "Docker socket permissions updated"
fi

# Atuin の設定ファイルを初期化
if command -v atuin >/dev/null 2>&1; then
    echo "Initializing Atuin configuration..."

    # Atuin設定ディレクトリの作成
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin

    # 設定ファイルが存在しない場合のみデフォルト設定を作成
    if [ ! -f ~/.config/atuin/config.toml ]; then
        echo "Creating default Atuin config..."
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
        echo "✅ Atuin configuration created"
    else
        echo "ℹ️  Atuin config already exists, using existing configuration"
    fi

    echo "✅ Atuin initialization complete"
fi

# 元のコマンドを実行
exec "$@"
