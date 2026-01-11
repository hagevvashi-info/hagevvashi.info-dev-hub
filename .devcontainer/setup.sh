#!/usr/bin/env bash
set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

# リポジトリ集約ディレクトリのマウント先ボリュームを作成
VOLUME_NAME="repos"
# volumeが存在するかチェック
if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "Volume '$VOLUME_NAME' は既に存在します"
else
  echo "Volume '$VOLUME_NAME' を作成します"
  docker volume create "$VOLUME_NAME"
fi

echo "🔧 Generating devcontainer.json..."

# ホストOSのアーキテクチャを判定
case "$(uname -m)" in
  x86_64)
    PLATFORM="linux/amd64"
    ;;
  aarch64 | arm64)
    PLATFORM="linux/arm64"
    ;;
  *)
    # サポート外のアーキテクチャの場合はエラー
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

# リポジトリ名を取得（ディレクトリ名から）
MDC_REPO_ROOT=$(basename "${REPOSITORY_ROOT}")

# devcontainer.jsonのみ生成（UNAMEとHOMEとPLATFORMとMDC_REPO_ROOTを置換）
sed -e "s/__UNAME__/$(whoami)/g" \
    -e "s|__HOME__|${HOME}|g" \
    -e "s|__PLATFORM__|${PLATFORM}|g" \
    -e "s|__MDC_REPO_ROOT__|${MDC_REPO_ROOT}|g" \
    ./.devcontainer/devcontainer.json.template > ./.devcontainer/devcontainer.json
# docker-compose.dev-vm.ymlのみ生成（HOMEを置換）
sed -e "s|__HOME__|${HOME}|g" \
    ./.devcontainer/docker-compose.dev-vm.yml.template > ./.devcontainer/docker-compose.dev-vm.yml


echo "✅ devcontainer.json generated:"
cat ./.devcontainer/devcontainer.json
echo "✅ Ready to open in Dev Container"
