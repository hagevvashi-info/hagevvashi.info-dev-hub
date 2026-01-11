#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Running post-create setup..."

# 環境変数の確認
UNAME=$(whoami)

# スクリプトのディレクトリから相対的にリポジトリ名を取得
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
MDC_REPO_ROOT=$(basename "${REPO_ROOT}")

echo "User: ${UNAME}"
echo "Repository: ${MDC_REPO_ROOT}"
echo "Repository root: ${REPO_ROOT}"

# Devin互換用のシンボリックリンクを作成
# /home/<user>/repos -> /home/<user>/<repo-name>/repos
SYMLINK_PATH="/home/${UNAME}/repos"
TARGET_PATH="/home/${UNAME}/${MDC_REPO_ROOT}/repos"

if [ ! -L "${SYMLINK_PATH}" ]; then
    echo "Creating symlink: ${SYMLINK_PATH} -> ${TARGET_PATH}"
    ln -sf "${TARGET_PATH}" "${SYMLINK_PATH}"
    echo "✅ Symlink created successfully"
else
    echo "ℹ️  Symlink already exists: ${SYMLINK_PATH}"
    # シンボリックリンクの向き先を確認
    CURRENT_TARGET=$(readlink "${SYMLINK_PATH}")
    echo "    Current target: ${CURRENT_TARGET}"
    if [ "${CURRENT_TARGET}" != "${TARGET_PATH}" ]; then
        echo "⚠️  Warning: Symlink target mismatch. Updating..."
        ln -sf "${TARGET_PATH}" "${SYMLINK_PATH}"
        echo "✅ Symlink updated"
    fi
fi

# repos/ ディレクトリの確認
if [ ! -d "${TARGET_PATH}" ]; then
    echo "⚠️  Warning: ${TARGET_PATH} does not exist"
    echo "    This directory should be mounted as a Docker Volume"
else
    echo "✅ repos/ directory exists"
    # repos/ の内容を表示
    echo "Contents of repos/:"
    ls -la "${TARGET_PATH}" || echo "    (empty or permission denied)"
fi

echo "✅ Post-create setup completed"
