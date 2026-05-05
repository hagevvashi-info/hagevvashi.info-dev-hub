#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

./.devcontainer/host-scripts/monitor-attached.sh
./.devcontainer/host-scripts/host-debug-dispatcher.sh
./.devcontainer/host-scripts/generate-env.sh
