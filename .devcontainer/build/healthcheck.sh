#!/usr/bin/env bash
# workloads/supervisord/healthcheck.sh
# コンテナの健全性をチェックする

set -euo pipefail  # エラー時終了、未定義変数エラー、パイプライン全体のエラー検知

# DEBUG_MODE が true の場合は常に成功
if [ "${DEBUG_MODE:-false}" = "true" ]; then
    echo "DEBUG_MODE is enabled, skipping healthcheck"
    exit 0
fi

echo "=== Healthcheck started ==="

# 1. supervisord の動作確認
echo "Checking code-server status..."
if ! supervisorctl status code-server | grep -q RUNNING; then
    echo "ERROR: code-server is not RUNNING"
    exit 1
fi

# 2. log-forwarder の動作確認
echo "Checking log-forwarder status..."
if ! supervisorctl status log-forwarder | grep -q RUNNING; then
    echo "ERROR: log-forwarder is not RUNNING"
    exit 1
fi

# 3. log-forwarder-monitor の動作確認
echo "Checking log-forwarder-monitor status..."
if ! supervisorctl status log-forwarder-monitor | grep -q RUNNING; then
    echo "ERROR: log-forwarder-monitor is not RUNNING"
    exit 1
fi

# 4. tail プロセスが動作しているか確認
echo "Checking tail process..."
if ! pgrep -f "tail.*supervisor.*log" >/dev/null; then
    echo "ERROR: tail process not found"
    exit 1
fi

echo "=== Healthcheck passed ==="
exit 0
