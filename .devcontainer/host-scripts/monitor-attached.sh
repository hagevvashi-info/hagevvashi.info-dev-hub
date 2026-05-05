#!/usr/bin/env bash

set -euox pipefail

# カレントディレクトリを固定
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/../.." &>/dev/null && pwd)
cd "${REPOSITORY_ROOT}"

# ==========================================
# 設定エリア
# ==========================================
TMP_DIR="./.devcontainer/tmp"
PID_FILE="${TMP_DIR}/monitor.pid"
FIFO_FILE="${TMP_DIR}/monitor.fifo"
LOG_FILE="${TMP_DIR}/host-action.log"
VERSION_FILE="${TMP_DIR}/monitor.version"
ACTION_CMD="{ echo '🔄 変更を検知しました！' && ./.devcontainer/host-scripts/setup.sh; } >> ${LOG_FILE}"
# ==========================================

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

# 1. 既存 monitor の再利用判定
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

# 2. 下準備
mkdir -p "${TMP_DIR}"
rm -f "${FIFO_FILE}"
mkfifo "${FIFO_FILE}"
: > "${WATCH_FILE}" # 起動スイッチは内容を持たせず空の状態から始める
: > "${LOG_FILE}"   # ログファイルも空にする

# 3. 実行
# 処理ループと監視をひとつの常駐単位として切り離して起動する
nohup sh -c "
  set -eu

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

  tail -n 0 -F \"${WATCH_FILE}\" > \"${FIFO_FILE}\" &
  TAIL_PID=\$!

  while read -r _; do
    eval \"${ACTION_CMD}\" >> \"${LOG_FILE}\" 2>&1
  done < \"${FIFO_FILE}\" &
  WORKER_PID=\$!

  wait \"\${TAIL_PID}\" \"\${WORKER_PID}\"
" > /dev/null 2>&1 < /dev/null &

# 4. PID と version を保存
# ここでの $! は、監視と処理をまとめて持つ常駐シェルの PID です。
echo $! > "${PID_FILE}"
echo "${CURRENT_VERSION}" > "${VERSION_FILE}"

# 5. 不要なパイプファイルの削除（プロセス終了時に消えるよう設定は可能だが、ここではシンプルに）
