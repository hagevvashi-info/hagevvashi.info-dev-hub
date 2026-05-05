#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

TMP_DIR="./.devcontainer/tmp"
PID_FILE="${TMP_DIR}/host-debug-dispatcher.pid"
FIFO_FILE="${TMP_DIR}/host-debug-dispatcher.fifo"
LOG_FILE="${TMP_DIR}/host-debug-dispatcher.log"
VERSION_FILE="${TMP_DIR}/host-debug-dispatcher.version"
REQUEST_FILE="${TMP_DIR}/host-debug.request"
RESULT_FILE="${TMP_DIR}/host-debug.result"

# ==========================================
# ヘルパー関数: クロスプラットフォームなSHA256ハッシュ計算
# ==========================================
get_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Error: sha256sum or shasum command not found." >&2
    exit 1
  fi
}

# monitor スクリプトの差し替えを検知するため、自身の内容から version を作る
CURRENT_VERSION=$(get_sha256 "${BASH_SOURCE[0]}")
RUNNING_VERSION=""

if [ -f "${VERSION_FILE}" ]; then
  RUNNING_VERSION=$(cat "${VERSION_FILE}")
fi

if [ -f "${PID_FILE}" ]; then
  RUNNING_PID=$(cat "${PID_FILE}")

  if ps -p "${RUNNING_PID}" > /dev/null 2>&1; then
    if [ "${RUNNING_VERSION}" = "${CURRENT_VERSION}" ]; then
      exit 0
    fi

    kill "${RUNNING_PID}" > /dev/null 2>&1 || true
    wait "${RUNNING_PID}" 2>/dev/null || true
  fi
fi

mkdir -p "${TMP_DIR}"
rm -f "${FIFO_FILE}"
mkfifo "${FIFO_FILE}"
: > "${REQUEST_FILE}"
: > "${LOG_FILE}"

nohup sh -c "
  set -eu

  handle_request() {
    if [ ! -s \"${REQUEST_FILE}\" ]; then
      return 0
    fi

    REQUEST_ID=\$(sed -n '1p' \"${REQUEST_FILE}\")
    COMMAND_NAME=\$(sed -n '2p' \"${REQUEST_FILE}\")
    ARG1=\$(sed -n '3p' \"${REQUEST_FILE}\")

    {
      echo \"request_id=\${REQUEST_ID}\"
      echo \"handled_at=\$(date -Iseconds)\"
      echo \"hostname=\$(hostname)\"
      echo \"uname=\$(uname -a)\"

      case \"\${COMMAND_NAME}\" in
        inspect_pid)
          if [ -z \"\${ARG1}\" ]; then
            echo \"status=error\"
            echo \"message=missing_pid\"
          elif ps -p \"\${ARG1}\" > /dev/null 2>&1; then
            echo \"status=running\"
            ps -p \"\${ARG1}\" -o pid=,ppid=,user=,comm=,args=
          else
            echo \"status=not_found\"
            echo \"pid=\${ARG1}\"
          fi
          ;;
        *)
          echo \"status=error\"
          echo \"message=unsupported_command:\${COMMAND_NAME}\"
          ;;
      esac
    } > \"${RESULT_FILE}\"

    : > \"${REQUEST_FILE}\"
  }

  cleanup() {
    if [ -n \"\${TAIL_PID:-}\" ]; then
      kill \"\${TAIL_PID}\" 2>/dev/null || true
      wait \"\${TAIL_PID}\" 2>/dev/null || true
    fi

    if [ -n \"\${WORKER_PID:-}\" ]; then
      kill \"\${WORKER_PID}\" 2>/dev/null || true
      wait \"\${WORKER_PID}\" 2>/dev/null || true
    fi
  }

  trap cleanup TERM EXIT

  tail -n 0 -F \"${REQUEST_FILE}\" > \"${FIFO_FILE}\" &
  TAIL_PID=\$!

  while read -r _; do
    handle_request >> \"${LOG_FILE}\" 2>&1
  done < \"${FIFO_FILE}\" &
  WORKER_PID=\$!

  wait \"\${TAIL_PID}\" \"\${WORKER_PID}\"
" > /dev/null 2>&1 < /dev/null &

echo $! > "${PID_FILE}"
echo "${CURRENT_VERSION}" > "${VERSION_FILE}"
