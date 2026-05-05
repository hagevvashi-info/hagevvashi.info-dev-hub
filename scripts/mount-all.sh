#!/usr/bin/env bash

# ${1}配下の1階層目の全て *.encrypted ディレクトリをマウント

set -euox pipefail

# Determine the project root directory based on the script's location.
# This allows the script to be run from any directory.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# Adjust the number of '../' based on the script's depth relative to the project root.
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)
export PROJECT_ROOT # Export for any child scripts that might need it

MOUNT_ROOT_DIR=${1}

cd "${PROJECT_ROOT}"
pwd

# .encrypted ディレクトリを取得し、.encrypted を削除した名前で crypt-mount を実行
echo "🔓 Mounting all archive directories..."
echo ""

find "${MOUNT_ROOT_DIR}" -maxdepth 1 -type d -name "*.encrypted" | sort | while read -r encrypted_dir; do
  # ファイル名を取得（フルパスから名前のみ抽出）
  dir_name=$(basename "${encrypted_dir}")

  # .encryptedを削除
  mount_name="${dir_name%.encrypted}"

  echo "📁 Mounting: ${mount_name}"
  ./bin/crypt-mount "${MOUNT_ROOT_DIR}/${mount_name}"
done

echo ""
echo "✅ All archives mounted successfully!"
