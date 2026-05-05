#!/usr/bin/env bash

# ${1}配下の1階層目の全て *.plain ディレクトリをアンマウント

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

# .plain ディレクトリを取得し、.plain を削除した名前で crypt-umount を実行
echo "🔒 Unmounting all archive directories..."
echo ""

find "${MOUNT_ROOT_DIR}" -maxdepth 1 -type d -name "*.plain" | sort | while read -r plain_dir; do
  # ファイル名を取得（フルパスから名前のみ抽出）
  dir_name=$(basename "${plain_dir}")

  # .plain を削除
  mount_name="${dir_name%.plain}"

  echo "📁 Unmounting: ${mount_name}"
  ./bin/crypt-umount "${MOUNT_ROOT_DIR}/${mount_name}"
done

echo ""
echo "✅ All archives unmounted successfully!"
