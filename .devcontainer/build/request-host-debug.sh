#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

TMP_DIR="./.devcontainer/tmp"
REQUEST_FILE="${TMP_DIR}/host-debug.request"
RESULT_FILE="${TMP_DIR}/host-debug.result"
REQUEST_ID_FILE="${TMP_DIR}/host-debug.request_id"
LOCK_FILE="${TMP_DIR}/host-debug.lock"

COMMAND_NAME="${1:-}"
ARG1="${2:-}"
TIMEOUT_SECONDS="${HOST_DEBUG_TIMEOUT_SECONDS:-10}"

if [ -z "${COMMAND_NAME}" ]; then
  echo "Usage: $0 inspect_pid <pid>" >&2
  exit 1
fi

mkdir -p "${TMP_DIR}"

exec 9>"${LOCK_FILE}"
flock 9

REQUEST_ID="$(date +%s)-$$"

rm -f "${RESULT_FILE}"

{
  echo "${REQUEST_ID}"
  echo "${COMMAND_NAME}"
  echo "${ARG1}"
} > "${REQUEST_FILE}"

echo "${REQUEST_ID}" > "${REQUEST_ID_FILE}"

STARTED_AT=$(date +%s)

while true; do
  if [ -f "${RESULT_FILE}" ]; then
    RESULT_REQUEST_ID=$(sed -n '1p' "${RESULT_FILE}" | sed 's/^request_id=//')
    if [ "${RESULT_REQUEST_ID}" = "${REQUEST_ID}" ]; then
      cat "${RESULT_FILE}"
      flock -u 9
      exit 0
    fi
  fi

  NOW=$(date +%s)
  if [ $((NOW - STARTED_AT)) -ge "${TIMEOUT_SECONDS}" ]; then
    flock -u 9
    echo "Timed out waiting for host debug result" >&2
    exit 1
  fi

  sleep 1
done
