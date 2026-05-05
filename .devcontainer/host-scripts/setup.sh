#!/usr/bin/env bash
set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)
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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# バインドマウントに備えて、ディレクトリとファイル準備
# 参考: 
#   <MDC_REPO_ROOT>/.devcontainer/devcontainer.json.template
#   <MDC_REPO_ROOT>/.devcontainer/docker-compose.dev-vm.yml.template
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Files
# __HOME__/.bash_history
# __HOME__/.gitconfig
# __HOME__/.claude.json
# __HOME__/.tmux.conf
BIND_MOUNT_FILES=(
  ~/.bash_history
  ~/.gitconfig
  ~/.claude.json
  ~/.tmux.conf
)

# Directories
# __HOME__/.git
# __HOME__/.ssh
# __HOME__/.aws
# __HOME__/.gemini
# __HOME__/.claude
# __HOME__/.cursor
# __HOME__/.config/code-server
# __HOME__/.config/gh
# __HOME__/.config/gcloud
# __HOME__/.config/atuin
# __HOME__/.config/mise
# __HOME__/.local/share/atuin
# __HOME__/.local/share/code-server
# __HOME__/.local/state/claude
# __HOME__/.local/state/mise
# __HOME__/.codex
# __HOME__/.tmux
# __HOME__/.vscode-server
BIND_MOUNT_DIRS=(
  ~/.git
  ~/.ssh
  ~/.aws
  ~/.gemini
  ~/.claude
  ~/.cursor
  ~/.config/code-server
  ~/.config/gh
  ~/.config/gcloud
  ~/.config/atuin
  ~/.config/mise
  ~/.local/share/atuin
  ~/.local/share/code-server
  ~/.local/state/claude
  ~/.local/state/mise
  ~/.codex
  ~/.tmux
  ~/.vscode-server
)

for A_BIND_MOUNT_DIR in "${BIND_MOUNT_DIRS[@]}"; do
  mkdir -p "${A_BIND_MOUNT_DIR}" || echo "Warning: Failed to create ${A_BIND_MOUNT_DIR}"
done

for A_BIND_MOUNT_FILE in "${BIND_MOUNT_FILES[@]}"; do
  touch "${A_BIND_MOUNT_FILE}" || echo "Warning: Failed to create ${A_BIND_MOUNT_FILE}"
done

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


echo "✅ devcontainer.json, docker-compose.dev-vm.yml generated:"
cat ./.devcontainer/devcontainer.json
cat ./.devcontainer/docker-compose.dev-vm.yml
echo "✅ Ready to open in Dev Container"
