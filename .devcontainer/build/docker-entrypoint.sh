#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 0: 環境変数の読み込み
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay が配置した環境変数を読み込む
if [ -d /run/s6/container_environment ]; then
  for file in /run/s6/container_environment/*; do
    if [ -f "$file" ]; then
      varname="$(basename "$file")"
      # Skip invalid variable names (must match [a-zA-Z_][a-zA-Z0-9_]*)
      case "$varname" in
        [a-zA-Z_]*[a-zA-Z0-9_]|[a-zA-Z_])
          export "${varname}=$(cat "$file")"
          ;;
        *)
          echo "⚠️  Skipping invalid environment variable name: $varname" >&2
          ;;
      esac
    fi
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
# Phase 1.5: repos/ ディレクトリの所有権修正とシンボリックリンク作成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📁 Phase 1.5: Fixing repos/ directory ownership and symlinks..."

REPOS_PATH="/home/${UNAME}/${MDC_REPO_ROOT}/repos"

# repos/ディレクトリの所有権修正
if [ -d "${REPOS_PATH}" ]; then
  CURRENT_OWNER=$(stat -c '%U' "${REPOS_PATH}" 2>/dev/null || echo "unknown")
  echo "  repos/ current owner: ${CURRENT_OWNER}"
    
  if [ "${CURRENT_OWNER}" = "root" ]; then
    echo "  🔧 Updating ownership from root to ${UNAME}:${GNAME}..."
    chown -R ${UNAME}:${GNAME} "${REPOS_PATH}"
    echo "  ✅ repos/ ownership updated"
  else
    echo "  ✅ repos/ ownership is correct"
  fi
else
  echo "  ⚠️  repos/ directory not found (will be created when mounted)"
fi

# Devin互換用のシンボリックリンクを作成
# /home/<user>/repos -> /home/<user>/<repo-name>/repos
REPOS_SYMLINK_PATH="/home/${UNAME}/repos"

if [ ! -L "${REPOS_SYMLINK_PATH}" ]; then
  # シンボリックリンクでない場合
  if [ -e "${REPOS_SYMLINK_PATH}" ]; then
    # 通常のディレクトリまたはファイルが既に存在する場合
    echo "  ⚠️  ${REPOS_SYMLINK_PATH} exists as a regular file/directory"
    echo "  🔧 Removing and creating symlink..."
    rm -rf "${REPOS_SYMLINK_PATH}"
  fi
  echo "  🔗 Creating symlink: ${REPOS_SYMLINK_PATH} -> ${REPOS_PATH}"
  ln -sfn "${REPOS_PATH}" "${REPOS_SYMLINK_PATH}"
  echo "  ✅ Symlink created successfully"
else
  # シンボリックリンクの向き先を確認
  CURRENT_TARGET=$(readlink "${REPOS_SYMLINK_PATH}")
  if [ "${CURRENT_TARGET}" != "${REPOS_PATH}" ]; then
    echo "  🔗 Updating symlink: ${REPOS_SYMLINK_PATH} -> ${REPOS_PATH}"
    ln -sfn "${REPOS_PATH}" "${REPOS_SYMLINK_PATH}"
    echo "  ✅ Symlink updated"
  else
    echo "  ✅ Symlink already correct: ${REPOS_SYMLINK_PATH} -> ${REPOS_PATH}"
  fi
fi

# リンク自体のオーナーを変えるには -h
chown -h ${UNAME}:${GNAME} "${REPOS_SYMLINK_PATH}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 1.5.1: mise設定ファイル調整
#      /home/${UNAME}/.mise.toml -symlink-> <MDC_REPO_ROOT>/.mise.toml
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# mise の設定ファイルをシンボリックリンクで設定

echo ""
echo "📁 Phase 1.5.1: Fixing .mise.toml file ownership and symlinks..."

MISE_CONFIG_PATH="/home/${UNAME}/${MDC_REPO_ROOT}/.mise.toml"

MISE_CONFIG_SYMLINK_PATH="/home/${UNAME}/.mise.toml"
if [ ! -L "${MISE_CONFIG_SYMLINK_PATH}" ]; then
  # シンボリックリンクでない場合
  if [ -e "${MISE_CONFIG_SYMLINK_PATH}" ]; then
    # 通常のディレクトリまたはファイルが既に存在する場合
    echo "  ⚠️  ${MISE_CONFIG_SYMLINK_PATH} exists as a regular file/directory"
    echo "  🔧 Removing and creating symlink..."
    rm -rf "${MISE_CONFIG_SYMLINK_PATH}"
  fi
  echo "  🔗 Creating symlink: ${MISE_CONFIG_SYMLINK_PATH} -> ${MISE_CONFIG_PATH}"
  ln -sf "${MISE_CONFIG_PATH}" "${MISE_CONFIG_SYMLINK_PATH}"
  echo "  ✅ Symlink created successfully"
else
  # シンボリックリンクの向き先を確認
  CURRENT_TARGET=$(readlink "${MISE_CONFIG_SYMLINK_PATH}")
  if [ "${CURRENT_TARGET}" != "${MISE_CONFIG_PATH}" ]; then
    echo "  🔗 Updating symlink: ${MISE_CONFIG_SYMLINK_PATH} -> ${MISE_CONFIG_PATH}"
    ln -sf "${MISE_CONFIG_PATH}" "${MISE_CONFIG_SYMLINK_PATH}"
    echo "  ✅ Symlink updated"
  else
    echo "  ✅ Symlink already correct: ${MISE_CONFIG_SYMLINK_PATH} -> ${MISE_CONFIG_PATH}"
  fi
fi

# リンク自体のオーナーを変えるには -h
chown -h ${UNAME}:${GNAME} "${MISE_CONFIG_SYMLINK_PATH}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 1.5.2: python(uv)設定ファイル調整
#      /home/${UNAME}/pyproject.toml -symlink-> <MDC_REPO_ROOT>/pyproject.toml
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# python(uv) の設定ファイルをシンボリックリンクで設定

echo ""
echo "📁 Phase 1.5.2: Fixing pyproject.toml file ownership and symlinks..."

PYPJ_CONFIG_PATH="/home/${UNAME}/${MDC_REPO_ROOT}/pyproject.toml"

PYPJ_CONFIG_SYMLINK_PATH="/home/${UNAME}/pyproject.toml"

if [ ! -L "${PYPJ_CONFIG_SYMLINK_PATH}" ]; then
  # シンボリックリンクでない場合
  if [ -e "${PYPJ_CONFIG_SYMLINK_PATH}" ]; then
    # 通常のディレクトリまたはファイルが既に存在する場合
    echo "  ⚠️  ${PYPJ_CONFIG_SYMLINK_PATH} exists as a regular file/directory"
    echo "  🔧 Removing and creating symlink..."
    rm -rf "${PYPJ_CONFIG_SYMLINK_PATH}"
  fi
  echo "  🔗 Creating symlink: ${PYPJ_CONFIG_SYMLINK_PATH} -> ${PYPJ_CONFIG_PATH}"
  ln -sf "${PYPJ_CONFIG_PATH}" "${PYPJ_CONFIG_SYMLINK_PATH}"
  echo "  ✅ Symlink created successfully"
else
  # シンボリックリンクの向き先を確認
  CURRENT_TARGET=$(readlink "${PYPJ_CONFIG_SYMLINK_PATH}")
  if [ "${CURRENT_TARGET}" != "${PYPJ_CONFIG_PATH}" ]; then
    echo "  🔗 Updating symlink: ${PYPJ_CONFIG_SYMLINK_PATH} -> ${PYPJ_CONFIG_PATH}"
    ln -sf "${PYPJ_CONFIG_PATH}" "${PYPJ_CONFIG_SYMLINK_PATH}"
    echo "  ✅ Symlink updated"
  else
    echo "  ✅ Symlink already correct: ${PYPJ_CONFIG_SYMLINK_PATH} -> ${PYPJ_CONFIG_PATH}"
  fi
fi

# リンク自体のオーナーを変えるには -h
chown -h ${UNAME}:${GNAME} "${PYPJ_CONFIG_SYMLINK_PATH}"


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 2: supervisord設定ファイルの検証とフォールバック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 2: Validating supervisord configuration..."

UNAME=${UNAME:-$(whoami)}
MDC_REPO_ROOT=${MDC_REPO_ROOT}

PROJECT_CONF="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/supervisord/project.conf"
SEED_CONF="/etc/supervisor/seed.conf"
TARGET_CONF="/etc/supervisor/supervisord.conf"

if [ -f "${PROJECT_CONF}" ]; then
  echo "  ✅ Found: ${PROJECT_CONF}"

  rm -f "${TARGET_CONF}"
  ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"

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

    ln -sf "${SEED_CONF}" "${TARGET_CONF}"
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

  ln -sf "${SEED_CONF}" "${TARGET_CONF}"
fi

echo "  Using config: ${TARGET_CONF}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: process-compose設定ファイルの検証とフォールバック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 3: Validating process-compose configuration..."

UNAME=${UNAME:-$(whoami)}
MDC_REPO_ROOT=${MDC_REPO_ROOT}

PROJECT_YAML="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/process-compose/project.yaml"
SEED_YAML="/etc/process-compose/seed.yaml"
TARGET_YAML="/etc/process-compose/process-compose.yaml"

if [ -f "${PROJECT_YAML}" ]; then
    echo "  ✅ Found: ${PROJECT_YAML}"

    mkdir -p /etc/process-compose
    ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"

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

        ln -sf "${SEED_YAML}" "${TARGET_YAML}"
    fi
else
    echo "  ⚠️  workloads/process-compose/project.yaml not found"
    echo "  Using seed config (minimal setup)"

    mkdir -p /etc/process-compose
    ln -sf "${SEED_YAML}" "${TARGET_YAML}"
fi

echo "  Using config: ${TARGET_YAML}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3.1: Nginx設定ファイルとHTMLのシンボリックリンク作成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 3.1: Setting up Nginx configurations..."

UNAME=${UNAME:-$(whoami)}
MDC_REPO_ROOT=${MDC_REPO_ROOT}

# Main nginx.conf
NGINX_CONF_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/nginx/nginx.conf"
NGINX_CONF_TARGET="/etc/nginx/nginx.conf"

if [ -f "${NGINX_CONF_SOURCE}" ]; then
  echo "  ✅ Found: ${NGINX_CONF_SOURCE}"
  ln -sf "${NGINX_CONF_SOURCE}" "${NGINX_CONF_TARGET}"
  echo "  🔗 Symlink created: ${NGINX_CONF_TARGET}"
else
  echo "  ⚠️  ${NGINX_CONF_SOURCE} not found"
  echo "  Using system default nginx.conf"
fi

# WebSocket upgrade map
WEBSOCKET_MAP_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/nginx/conf.d/websocket-upgrade-map.conf"
WEBSOCKET_MAP_TARGET="/etc/nginx/conf.d/websocket-upgrade-map.conf"

if [ -f "${WEBSOCKET_MAP_SOURCE}" ]; then
  echo "  ✅ Found: ${WEBSOCKET_MAP_SOURCE}"
  ln -sf "${WEBSOCKET_MAP_SOURCE}" "${WEBSOCKET_MAP_TARGET}"
  echo "  🔗 Symlink created: ${WEBSOCKET_MAP_TARGET}"
else
  echo "  ⚠️  ${WEBSOCKET_MAP_SOURCE} not found"
  echo "  nginx WebSocket proxy may not work correctly"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3.1.1: Process Compose Dashboard の Nginx設定とHTMLのシンボリックリンク作成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


# Process Compose Dashboard - Nginx site config
DASHBOARD_CONF_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/process-compose-dashboard/nginx/process-compose-dashboard.conf"
DASHBOARD_CONF_TARGET="/etc/nginx/sites-enabled/process-compose-dashboard.conf"

if [ -f "${DASHBOARD_CONF_SOURCE}" ]; then
  echo "  ✅ Found: ${DASHBOARD_CONF_SOURCE}"
  ln -sf "${DASHBOARD_CONF_SOURCE}" "${DASHBOARD_CONF_TARGET}"
  echo "  🔗 Symlink created: ${DASHBOARD_CONF_TARGET}"
else
  echo "  ⚠️  ${DASHBOARD_CONF_SOURCE} not found"
  echo "  Process Compose Dashboard will not be available"
fi

# Process Compose Dashboard - HTML files
DASHBOARD_HTML_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/process-compose-dashboard/html"
DASHBOARD_HTML_TARGET="/var/www/process-compose-dashboard"

if [ -d "${DASHBOARD_HTML_SOURCE}" ]; then
  echo "  ✅ Found: ${DASHBOARD_HTML_SOURCE}"
  
  # ターゲットディレクトリが存在する場合は削除
  if [ -e "${DASHBOARD_HTML_TARGET}" ] && [ ! -L "${DASHBOARD_HTML_TARGET}" ]; then
    rm -rf "${DASHBOARD_HTML_TARGET}"
  fi
  
  ln -sfn "${DASHBOARD_HTML_SOURCE}" "${DASHBOARD_HTML_TARGET}"
  echo "  🔗 Symlink created: ${DASHBOARD_HTML_TARGET}"
else
  echo "  ⚠️  ${DASHBOARD_HTML_SOURCE} not found"
  echo "  Dashboard HTML files will not be available"
fi


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3.1.2: Static File Server の Nginx設定と/workspace へのシンボリックリンク作成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Static File Server - Nginx site config
STATIC_FILE_SERVER_CONF_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/static-file-server/nginx/static-file-server.conf"
STATIC_FILE_SERVER_CONF_TARGET="/etc/nginx/sites-enabled/static-file-server.conf"

if [ -f "${STATIC_FILE_SERVER_CONF_SOURCE}" ]; then
  echo "  ✅ Found: ${STATIC_FILE_SERVER_CONF_SOURCE}"
  ln -sf "${STATIC_FILE_SERVER_CONF_SOURCE}" "${STATIC_FILE_SERVER_CONF_TARGET}"
  echo "  🔗 Symlink created: ${STATIC_FILE_SERVER_CONF_TARGET}"
else
  echo "  ⚠️  ${STATIC_FILE_SERVER_CONF_SOURCE} not found"
  echo "  Static File Server will not be available"
fi

# TODO: ここでいいの？問題
#   【事象】/workspace という他の用途でも使いそうなパスをここで定義している
#   【問題①】本来は static-file-server の conf 内で解決すべき内容。動的 template にするなど
#   【問題②】/workspace と同じ解決策を他の用途で取りたくなった時、二重三重と同じような symlink ができる

# Static File Server - Workspace symlink
WORKSPACE_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}"
WORKSPACE_TARGET="/workspace"

if [ -d "${WORKSPACE_SOURCE}" ]; then
  echo "  ✅ Found: ${WORKSPACE_SOURCE}"

  # ターゲットディレクトリが存在する場合は削除
  if [ -e "${WORKSPACE_TARGET}" ] && [ ! -L "${WORKSPACE_TARGET}" ]; then
    rm -rf "${WORKSPACE_TARGET}"
  fi

  ln -sfn "${WORKSPACE_SOURCE}" "${WORKSPACE_TARGET}"
  echo "  🔗 Symlink created: ${WORKSPACE_TARGET}"
else
  echo "  ⚠️  ${WORKSPACE_SOURCE} not found"
  echo "  Static File Server root directory will not be available"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ docker-entrypoint.sh finished."
echo "   s6-overlay will now start supervisord and process-compose as longrun services."
echo ""
