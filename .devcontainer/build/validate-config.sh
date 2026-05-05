#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Validating DevContainer configuration (Host-side)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 1: ファイル存在確認
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📁 Phase 1: Checking required files..."
REQUIRED_FILES=(
    "${SCRIPT_DIR}/../Dockerfile"
    "${SCRIPT_DIR}/../docker-compose.yml"
    "${SCRIPT_DIR}/../config/supervisord/seed.conf"
    "${SCRIPT_DIR}/../config/process-compose/seed.yaml"
    "${SCRIPT_DIR}/docker-entrypoint.sh"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ❌ Missing: $file"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        echo "  ✅ Found: $file"
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo ""
    echo "❌ Validation failed: $MISSING_FILES file(s) missing"
    exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 2: supervisord.conf の基本的な構文チェック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 2: Validating supervisord.conf (syntax check)..."

# 必須セクションの存在確認
if grep -q "^\[supervisord\]" "${SCRIPT_DIR}/../config/supervisord/seed.conf"; then
    echo "  ✅ [supervisord] section found"
else
    echo "  ❌ [supervisord] section not found"
    exit 1
fi

if grep -q "^\[inet_http_server\]" "${SCRIPT_DIR}/../config/supervisord/seed.conf"; then
    echo "  ✅ [inet_http_server] section found (Web UI)"
else
    echo "  ⚠️  [inet_http_server] section not found (Web UI disabled)"
fi

# supervisord コマンドがホストにある場合は詳細チェック
if command -v supervisord >/dev/null 2>&1; then
    echo ""
    echo "  📋 supervisord found on host. Running detailed validation..."
    if supervisord -c "${SCRIPT_DIR}/../config/supervisord/seed.conf" -t; then
        echo "  ✅ supervisord.conf is valid (detailed check)"
    else
        echo "  ❌ supervisord.conf validation failed"
        exit 1
    fi
else
    echo "  ⚠️  supervisord not installed on host. Skipping detailed validation."
    echo "     (Configuration will be validated in container at startup)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: process-compose.yaml の基本的な構文チェック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 3: Validating process-compose.yaml (syntax check)..."

if grep -q "^version:" "${SCRIPT_DIR}/../config/process-compose/seed.yaml"; then
    echo "  ✅ version field found"
else
    echo "  ❌ version field not found"
    exit 1
fi

if grep -q "^processes:" "${SCRIPT_DIR}/../config/process-compose/seed.yaml"; then
    echo "  ✅ processes field found"
else
    echo "  ❌ processes field not found"
    exit 1
fi

# YAML構文チェック（yq がホストにある場合）
if command -v yq >/dev/null 2>&1; then
    echo ""
    echo "  📋 yq found on host. Running YAML syntax check..."
    if yq eval '.' "${SCRIPT_DIR}/../config/process-compose/seed.yaml" > /dev/null 2>&1; then
        echo "  ✅ YAML syntax is valid"
    else
        echo "  ❌ YAML syntax error detected"
        exit 1
    fi
else
    echo "  ⚠️  yq not installed on host. Skipping YAML syntax check."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All validations passed (Host-side)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "ℹ️  Note: Final validation will occur in container at startup."
