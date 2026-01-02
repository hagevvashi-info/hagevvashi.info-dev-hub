#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

echo "🔧 Generating build environment variables..."

# リポジトリ名を取得（ディレクトリ名から）
REPO_NAME=$(basename "$(cd "$REPOSITORY_ROOT" && pwd)")

# .envファイルのみ生成
cat > .devcontainer/.env << EOF
UID="$(id -u)"
GID="$(id -g)"
UNAME="$(whoami)"
GNAME="$(id -n -g | sed 's/ /\\u00A0/g')"
REPO_NAME="${REPO_NAME}"
EOF

echo "✅ Environment variables generated:"
cat .devcontainer/.env
