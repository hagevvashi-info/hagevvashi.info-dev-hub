#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

echo "🔧 Generating build environment variables..."

# リポジトリ名を取得（ディレクトリ名から）
MDC_REPO_ROOT=$(basename "$(cd "${REPOSITORY_ROOT}" && pwd)")

# .envファイルのみ生成
cat > .devcontainer/.env << EOF
UID="$(id -u)"
GID="$(id -g)"
UNAME="$(whoami)"
GNAME="$(id -n -g | sed 's/ /\\u00A0/g')"
MDC_REPO_ROOT="${MDC_REPO_ROOT}"
EOF

# ホスト Docker daemon の API バージョンを検出
# Docker CLI の自動 API version negotiation 機能を利用
echo "🔍 Detecting host Docker daemon API version..."
DETECTED_API_VERSION=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || echo "")

# 検出失敗時のフォールバック処理
if [ -z "$DETECTED_API_VERSION" ]; then
  echo "⚠️  Warning: Failed to detect Docker daemon API version. Using fallback version 1.43"
  DETECTED_API_VERSION="1.43"
else
  echo "✅ Detected Docker daemon API version: $DETECTED_API_VERSION"
fi

# .env ファイルに DOCKER_API_VERSION を追加
cat >> .devcontainer/.env << EOF
DOCKER_API_VERSION="${DETECTED_API_VERSION}"
EOF

# ハイパーバイザーOS の docker.sock GID を取得
# docker run でコンテナ内から確認することで、ホストOSの種別（Mac/Linux）に依らず正確な値を取得できる
# 理由: ホストOS（Mac）では docker.sock の GID が hypervisor 内部の GID と異なるため、
#       ホストOSから直接取得しても正しい値が得られない
echo "🔍 Detecting Docker socket GID via container..."
DOCKER_GID=$(docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  alpine stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "")
if [ -z "$DOCKER_GID" ]; then
  echo "❌ Error: Failed to detect Docker socket GID. Is Docker running?"
  exit 1
fi
echo "✅ Detected Docker socket GID: $DOCKER_GID"

cat >> .devcontainer/.env << EOF
DOCKER_GID="${DOCKER_GID}"
EOF

echo "✅ Environment variables generated:"
cat .devcontainer/.env
