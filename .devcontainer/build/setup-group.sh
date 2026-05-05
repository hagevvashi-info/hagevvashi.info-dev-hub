#!/usr/bin/env bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# グループ作成・衝突対応スクリプト
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ホストOS（macOS）のユーザーグループ GID をコンテナに反映する必要がある。
# バインドマウントしたファイルのアクセス権はカーネルレベルで GID「番号」で判定されるため、
# ホスト側の GID とコンテナ側の GID を一致させる必要がある。
#
# ただし、Debian の apt パッケージがインストール時に動的にシステムグループを作成する際に、
# ホスト由来の GID と衝突する可能性がある。
# 例：ホスト GID 20（staff）vs Debian 内で既に使用されている GID 20（adm など）
#
# さらに、既存グループ名が異なるGIDで存在する場合も考慮する必要がある。
# 例：Debian に staff:x:50: が存在しており、ホストの GID 20 で新しい staff を作成したい
#
# この競合を回避するため、以下の 2 ステップで対応：
#
# ステップ 1: グループ名が異なるGIDで存在する場合はリネーム
#   - 既存グループ名（例：staff）が異なるGID（例：50）で存在
#   - → 既存グループを ${GROUP_NAME}-orig にリネーム
#   - 理由：グループ「名前」の重複は Linux で許可されないため
#
# ステップ 2: ホストGIDでグループを作成またはリネーム
#   - GID が既に存在し、グループ名が異なる → リネーム
#     例：GID 20 が adm → staff にリネーム
#   - GID が存在しない → 新規作成
#   - グループが既に正しく設定されている → 何もしない
#
# 複数回実行時の冪等性
# - グループが既に正しく設定されている場合は何もしない
# - これにより、複数回 docker build しても同じ結果が得られる
#
# 使用方法：
#   setup-group.sh <group_name> <group_gid>
#
# 例：
#   setup-group.sh staff 20
#   setup-group.sh docker 0
#
# 補足：UID はホスト由来でも 1000 以上、apt パッケージのシステム UID は 100 台以下のため衝突しない。
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -euo pipefail

GROUP_NAME="${1}"
GROUP_GID="${2}"

if [ -z "${GROUP_NAME}" ] || [ -z "${GROUP_GID}" ]; then
  echo "❌ Usage: $0 <group_name> <group_gid>"
  exit 1
fi

echo "🔧 Setting up group: ${GROUP_NAME} (GID: ${GROUP_GID})"

# ステップ 1: グループ名が異なるGIDで存在する場合はリネーム
EXISTING_GID=$(getent group "${GROUP_NAME}" 2>/dev/null | cut -d: -f3 || echo "")
if [ -n "${EXISTING_GID}" ] && [ "${EXISTING_GID}" != "${GROUP_GID}" ]; then
  echo "  ⚠️  Renaming existing group '${GROUP_NAME}' (GID ${EXISTING_GID}) to ${GROUP_NAME}-orig"
  groupmod -n "${GROUP_NAME}-orig" "${GROUP_NAME}"
fi

# ステップ 2: ホストGIDでグループを作成またはリネーム
EXISTING_GROUP=$(awk -F: '$3 == '${GROUP_GID}' { print $1 }' /etc/group || echo "")
if [ -n "${EXISTING_GROUP}" ] && [ "${EXISTING_GROUP}" != "${GROUP_NAME}" ]; then
  # GID 0 (root) などの保護されたシステムグループはリネームしない
  # -o オプションで GID 重複を許可して新規作成
  if [ "${GROUP_GID}" = "0" ] || [ "${EXISTING_GROUP}" = "root" ]; then
    echo "  ⚠️  GID ${GROUP_GID} is protected group '${EXISTING_GROUP}'"
    if ! grep -q "^${GROUP_NAME}:" /etc/group; then
      echo "  ✨ Creating '${GROUP_NAME}' with GID ${GROUP_GID} (duplicate GID allowed)"
      groupadd -o -g ${GROUP_GID} "${GROUP_NAME}"
    else
      echo "  ✅ Group '${GROUP_NAME}' already exists"
    fi
  else
    echo "  ℹ️  Renaming group '${EXISTING_GROUP}' (GID ${GROUP_GID}) to '${GROUP_NAME}'"
    groupmod -n "${GROUP_NAME}" "${EXISTING_GROUP}"
  fi
elif ! grep -q "^${GROUP_NAME}:" /etc/group; then
  echo "  ✨ Creating group '${GROUP_NAME}' with GID ${GROUP_GID}"
  groupadd -g ${GROUP_GID} "${GROUP_NAME}"
else
  echo "  ✅ Group '${GROUP_NAME}' already configured correctly"
fi