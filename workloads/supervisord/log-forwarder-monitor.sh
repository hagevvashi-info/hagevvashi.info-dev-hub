#!/usr/bin/env bash
# workloads/supervisord/log-forwarder-monitor.sh
# log-forwarder の健全性を監視し、問題があれば自動修復する
#
# 【監視対象ログファイルのルール】
# - 監視対象: /var/log/supervisor/*.log および /var/log/supervisor/*-error.log
# - `.` で始まるファイル（隠しファイル）は監視対象外
# - 意図的に監視から除外したいログは `.` で始める命名にすること
#   例: .debug.log, .tmp-service.log

set -euo pipefail

CHECK_INTERVAL=30

expected_log_files() {
    find /var/log/supervisor /var/log/nginx \
        -maxdepth 1 \
        -type f \
        \( -name '*.log' -o -name '*-error.log' \) \
        -print 2>/dev/null \
        | sort -u
}

tail_pid() {
    pgrep -xo -f '^tail -F /var/log/supervisor/.+ /var/log/nginx/.+'
}

monitored_log_files() {
    local pid="$1"

    if [ ! -d "/proc/$pid/fd" ]; then
        return 0
    fi

    find -L "/proc/$pid/fd" -maxdepth 1 -type f -print 2>/dev/null \
        | sed 's#^/proc/[0-9]\\+/fd/##' >/dev/null

    find "/proc/$pid/fd" -maxdepth 1 -type l -print0 2>/dev/null \
        | while IFS= read -r -d '' fd; do
            local target
            target="$(readlink -f "$fd" 2>/dev/null || true)"
            case "$target" in
                /var/log/supervisor/*.log|/var/log/nginx/*.log)
                    printf '%s\n' "$target"
                    ;;
            esac
        done \
        | sort -u
}

while true; do
    ERROR_DETECTED=false

    # 1. log-forwarder が RUNNING か確認
    if ! supervisorctl status log-forwarder | grep -q RUNNING; then
        echo "ERROR: log-forwarder is not RUNNING"
        supervisorctl restart log-forwarder
        ERROR_DETECTED=true
    fi

    # 2. tail プロセスが動作しているか確認
    if ! tail_pid >/dev/null; then
        echo "ERROR: tail process not found"
        supervisorctl restart log-forwarder
        ERROR_DETECTED=true
    fi

    # 3. 監視対象のログファイル数が正しいか確認
    EXPECTED_FILES=$(expected_log_files | wc -l | tr -d ' \n')
    TAIL_PID="$(tail_pid || true)"

    if [ -n "$TAIL_PID" ]; then
        MONITORED_FILES=$(monitored_log_files "$TAIL_PID" | wc -l | tr -d ' \n')

        if [ "$EXPECTED_FILES" -ne "$MONITORED_FILES" ]; then
            echo "WARNING: Expected $EXPECTED_FILES files, but monitoring $MONITORED_FILES files"
            echo "Restarting log-forwarder to pick up new log files..."
            supervisorctl restart log-forwarder
            ERROR_DETECTED=true
        fi
    fi

    if [ "$ERROR_DETECTED" = false ]; then
        echo "OK: log-forwarder is healthy (monitoring ${MONITORED_FILES:-0} files)"
    fi

    sleep $CHECK_INTERVAL
done
