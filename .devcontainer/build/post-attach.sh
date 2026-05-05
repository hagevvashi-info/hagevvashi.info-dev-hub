#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/../.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

printf 'trigger\n' > "${WATCH_FILE}"
