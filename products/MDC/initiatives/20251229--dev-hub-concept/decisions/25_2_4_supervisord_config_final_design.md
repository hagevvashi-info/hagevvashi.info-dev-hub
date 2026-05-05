# supervisord設定ファイル配置戦略の最終設計

**作成日**: 2026-01-03
**バージョン**: v3（Gemini第2回フィードバック反映版）
**関連**:
- [27_2_supervisord_config_strategy_revised.md](27_2_supervisord_config_strategy_revised.md)
- [27_3_に対するgeminiのツッコミ.md](27_3_supervisord_config_strategy_revised_に対するgeminiのツッコミ.md)

## 概要

v2で提案した「バインドマウント方式」に対して、Geminiから**ビルド時検証の矛盾**という致命的な指摘を受けました。この問題を解決した最終設計を提示します。

---

## Geminiからの追加フィードバック

### ツッコミ① ビルド時検証とバインドマウントの矛盾（致命的）

**Geminiの指摘:**
> バインドマウント方式を採用した場合、Dockerfile内でビルド時に設定ファイルを検証しても、その時点ではマウントされていないので意味がない。鶏と卵問題。

**評価: ✅✅ 完全に正しい（重大な設計ミス）**

**問題の構造:**
```
ビルド時: supervisord.conf.default を検証 ✅ パス
↓
起動時: マウントされた supervisord.conf を使用
↓
起動失敗: マウントされた設定が壊れている ❌
```

**つまり、ビルド時検証は実際に使われる設定ファイルをチェックできない。**

### ツッコミ② DEBUG_MODEによる偽陽性の問題

**Geminiの指摘:**
> DEBUG_MODE でコンテナを維持すると、`Up` 状態なのにサービスが動いていない偽陽性が発生する。healthcheck が必要。

**評価: ✅ 妥当**

---

## 最終設計: 3段階の検証戦略

バインドマウント方式を維持しつつ、検証を**適切なタイミング**で行う。

### 検証の3段階

| タイミング | 場所 | 目的 | ツール |
|----------|------|------|--------|
| **1. ホスト側（事前）** | host-setup.sh | 開発者への早期フィードバック | validate-config.sh |
| **2. 起動時（必須）** | docker-entrypoint.sh | 起動前の Fail Fast | supervisord -t |
| **3. 稼働中（監視）** | healthcheck | サービスの生存確認 | docker healthcheck |

---

## 実装詳細

### 1. ホスト側での事前検証

#### validate-config.sh（改訂版）

```bash
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
    "${SCRIPT_DIR}/Dockerfile"
    "${SCRIPT_DIR}/docker-compose.yml"
    "${SCRIPT_DIR}/supervisord/supervisord.conf"
    "${SCRIPT_DIR}/process-compose/process-compose.yaml"
    "${SCRIPT_DIR}/post-create.sh"
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
if grep -q "^\[supervisord\]" "${SCRIPT_DIR}/supervisord/supervisord.conf"; then
    echo "  ✅ [supervisord] section found"
else
    echo "  ❌ [supervisord] section not found"
    exit 1
fi

if grep -q "^\[inet_http_server\]" "${SCRIPT_DIR}/supervisord/supervisord.conf"; then
    echo "  ✅ [inet_http_server] section found (Web UI)"
else
    echo "  ⚠️  [inet_http_server] section not found (Web UI disabled)"
fi

# supervisord コマンドがホストにある場合は詳細チェック
if command -v supervisord >/dev/null 2>&1; then
    echo ""
    echo "  📋 supervisord found on host. Running detailed validation..."
    if supervisord -c "${SCRIPT_DIR}/supervisord/supervisord.conf" -t; then
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

if grep -q "^version:" "${SCRIPT_DIR}/process-compose/process-compose.yaml"; then
    echo "  ✅ version field found"
else
    echo "  ❌ version field not found"
    exit 1
fi

if grep -q "^processes:" "${SCRIPT_DIR}/process-compose/process-compose.yaml"; then
    echo "  ✅ processes field found"
else
    echo "  ❌ processes field not found"
    exit 1
fi

# YAML構文チェック（yq がホストにある場合）
if command -v yq >/dev/null 2>&1; then
    echo ""
    echo "  📋 yq found on host. Running YAML syntax check..."
    if yq eval '.' "${SCRIPT_DIR}/process-compose/process-compose.yaml" > /dev/null 2>&1; then
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
```

**実行タイミング:**
```bash
# host-setup.sh から呼び出す
./.devcontainer/validate-config.sh
```

**意義:**
- ✅ 開発者への早期フィードバック
- ✅ ホストで可能な範囲での検証
- ⚠️ ホストに supervisord/yq がなければスキップ（警告のみ）

---

### 2. 起動時の必須検証（Fail Fast）

#### docker-entrypoint.sh（改訂版）

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Docker Entrypoint: Initializing container..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 1: パーミッション修正（既存の処理）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📁 Phase 1: Fixing permissions for mounted config volumes..."
CONFIG_ITEMS=(
    ~/.config
    ~/.local
    ~/.git
    ~/.ssh
    ~/.aws
    ~/.claude
    ~/.claude.json
    ~/.cursor
    ~/.bash_history
    ~/.gitconfig
)
for item in "${CONFIG_ITEMS[@]}"; do
    if [ -e "$item" ]; then
        echo "  Updating ownership for $item"
        sudo chown -R $(id -u):$(id -g) "$item"
    fi
done
echo "✅ Permissions fixed."

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 2: Docker Socket調整（既存の処理）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🐳 Phase 2: Adjusting Docker socket permissions..."
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    DOCKER_MODE=$(stat -c '%a' /var/run/docker.sock)
    echo "Docker socket GID: $DOCKER_GID, Mode: $DOCKER_MODE"

    sudo chmod 666 /var/run/docker.sock
    echo "Docker socket permissions updated"

    if ! groups | grep -q docker; then
        sudo usermod -a -G docker $(whoami)
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化（既存の処理）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "⏱️  Phase 3: Initializing Atuin configuration..."
if command -v atuin >/dev/null 2>&1; then
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin

    if [ ! -f ~/.config/atuin/config.toml ]; then
        cat > ~/.config/atuin/config.toml <<'EOF'
# Atuin configuration
sync_address = "https://api.atuin.sh"
sync_frequency = "0"
search_mode = "fuzzy"
filter_mode = "global"
style = "compact"
inline_height = 20
show_preview = true
EOF
        echo "ℹ️  Created default Atuin configuration"
    else
        echo "ℹ️  Atuin config already exists, using existing configuration"
    fi
fi
echo "✅ Atuin initialization complete"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 4: supervisord設定ファイルの検証（★新規追加★）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 4: Validating supervisord configuration..."

# 環境変数から値を取得（フォールバック付き）
UNAME=${UNAME:-$(whoami)}
MDC_REPO_ROOT=${MDC_REPO_ROOT:-"<MonolithicDevContainerレポジトリ名>"}

# マウントされた設定ファイルのパス
SUPERVISORD_CONF_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/.devcontainer/supervisord/supervisord.conf"
SUPERVISORD_CONF_TARGET="/etc/supervisor/supervisord.conf"

# 設定ファイルの存在確認
if [ ! -f "${SUPERVISORD_CONF_SOURCE}" ]; then
    echo "❌ Error: supervisord.conf not found at ${SUPERVISORD_CONF_SOURCE}"
    echo ""
    echo "Please ensure:"
    echo "  1. The repository is properly bind-mounted"
    echo "  2. The file exists in .devcontainer/supervisord/supervisord.conf"
    echo ""
    exit 1
fi

echo "  ✅ Found: ${SUPERVISORD_CONF_SOURCE}"

# シンボリックリンク作成
echo "  Creating symlink: ${SUPERVISORD_CONF_TARGET} -> ${SUPERVISORD_CONF_SOURCE}"
sudo ln -sf "${SUPERVISORD_CONF_SOURCE}" "${SUPERVISORD_CONF_TARGET}"

# ★★★ 起動前の必須検証（Fail Fast） ★★★
echo "  Validating configuration syntax..."
if ! supervisord -c "${SUPERVISORD_CONF_TARGET}" -t 2>&1; then
    echo ""
    echo "❌ Error: supervisord.conf validation failed"
    echo ""
    echo "Please check the configuration file:"
    echo "  ${SUPERVISORD_CONF_SOURCE}"
    echo ""
    echo "Common issues:"
    echo "  - Syntax errors in .conf file"
    echo "  - Missing required sections ([supervisord], etc.)"
    echo "  - Invalid program commands"
    echo ""
    exit 1
fi

echo "  ✅ supervisord.conf is valid"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 5: process-compose設定ファイルのセットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 5: Setting up process-compose configuration..."

PROCESS_COMPOSE_YAML_SOURCE="/home/${UNAME}/${MDC_REPO_ROOT}/.devcontainer/process-compose/process-compose.yaml"
PROCESS_COMPOSE_YAML_TARGET="/etc/process-compose/process-compose.yaml"

if [ -f "${PROCESS_COMPOSE_YAML_SOURCE}" ]; then
    echo "  ✅ Found: ${PROCESS_COMPOSE_YAML_SOURCE}"
    sudo mkdir -p /etc/process-compose
    sudo ln -sf "${PROCESS_COMPOSE_YAML_SOURCE}" "${PROCESS_COMPOSE_YAML_TARGET}"
    echo "  ✅ process-compose.yaml symlink created"
else
    echo "  ⚠️  Warning: ${PROCESS_COMPOSE_YAML_SOURCE} not found"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 6: 元のコマンドを実行
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Starting supervisord..."

exec "$@"
```

**効果:**
- ✅ **起動時に必ず検証される**（マウントされた実際の設定ファイル）
- ✅ 設定エラーがあれば即座に終了（Fail Fast）
- ✅ エラーメッセージで問題箇所を明示

---

### 3. 稼働中の監視（healthcheck）

#### docker-compose.yml に healthcheck 追加

```yaml
services:
  dev:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
      args:
        UID: ${UID:-1000}
        GID: ${GID:-1000}
        UNAME: ${UNAME:-vscode}
        GNAME: ${GNAME:-vscode}

    volumes:
      - type: bind
        source: ..
        target: /home/${UNAME:-vscode}/${MDC_REPO_ROOT:-dev-hub}
        consistency: cached
      - type: volume
        source: repos
        target: /home/${UNAME:-vscode}/${MDC_REPO_ROOT:-dev-hub}/repos

    working_dir: /home/${UNAME:-vscode}/${MDC_REPO_ROOT:-dev-hub}

    ports:
      - "4035:4035"  # code-server
      - "8035:8035"  # difit
      - "9001:9001"  # supervisord Web UI
      - "8080:8080"  # process-compose TUI/API

    user: "${UID:-1000}:${GID:-1000}"
    tty: true
    stdin_open: true

    environment:
      - DEBUG_MODE=false  # true にするとデバッグモード

    # ★★★ healthcheck 追加 ★★★
    healthcheck:
      test: |
        if [ "$DEBUG_MODE" = "true" ]; then
          # DEBUG_MODE 時はヘルスチェックをパス（常に healthy）
          exit 0
        else
          # 通常モード: supervisorctl で code-server の状態を確認
          supervisorctl status code-server | grep -q RUNNING || exit 1
        fi
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

volumes:
  repos:
    external: true
```

**効果:**
```bash
$ docker ps
CONTAINER ID   STATUS
abc123         Up 2 minutes (healthy)      # 正常稼働
abc123         Up 2 minutes (unhealthy)    # supervisord が落ちている
abc123         Up 2 minutes                # DEBUG_MODE=true（監視免除）
```

---

### 4. DEBUG_MODE の改善

#### debug-entrypoint.sh（改訂版）

```bash
#!/usr/bin/env bash

cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️   WARNING: DEBUG MODE IS ENABLED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Container status will show 'Up' but services are NOT running.
This is intentional for debugging purposes.

Important:
  - supervisord is NOT started automatically
  - code-server is NOT running
  - Web UI (port 9001) is NOT accessible

To start supervisord manually:
  supervisord -c /etc/supervisor/supervisord.conf

To validate supervisord configuration:
  supervisord -c /etc/supervisor/supervisord.conf -t

To check supervisord status:
  supervisorctl status

To exit debug mode:
  1. Edit docker-compose.yml
  2. Set DEBUG_MODE=false
  3. Restart container: docker-compose restart

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo ""
echo "Starting bash shell for debugging..."
echo ""

# Keep container running with bash
exec /bin/bash
```

**効果:**
- ✅ 起動時に警告を明示
- ✅ 「Up だがサービスは動いていない」ことを明確化
- ✅ デバッグ手順を表示

---

## Dockerfileの修正

### ビルド時検証を削除（または明記）

```dockerfile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: supervisord
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# supervisord インストール
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      supervisor \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/*

# デフォルト設定をコピー（フォールバック用）
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/supervisord.conf.default

# ★★★ 注意: ここでの検証は「デフォルト設定」のみ ★★★
# ★★★ 実際に使われるマウント設定は起動時に検証される ★★★
RUN echo "🔍 Validating default supervisord configuration..." && \
    supervisord -c /etc/supervisor/supervisord.conf.default -t && \
    echo "✅ Default supervisord configuration is valid"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: process-compose
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# process-compose インストール（既存の処理）
ARG PROCESS_COMPOSE_VERSION=1.85.0
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -L "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_linux_${ARCH}.tar.gz" \
    -o /tmp/process-compose.tar.gz && \
    tar -xzf /tmp/process-compose.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/process-compose && \
    rm /tmp/process-compose.tar.gz

# デフォルト設定をコピー（フォールバック用）
RUN mkdir -p /etc/process-compose
COPY .devcontainer/process-compose/process-compose.yaml /etc/process-compose/process-compose.yaml.default

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# デバッグモード用エントリーポイント
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COPY .devcontainer/debug-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/debug-entrypoint.sh

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CMD: DEBUG_MODE で切り替え
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CMD [ "/bin/bash", "-c", "if [ \"${DEBUG_MODE:-false}\" = \"true\" ]; then exec /usr/local/bin/debug-entrypoint.sh; else exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf; fi" ]
```

**重要な変更:**
- ✅ ビルド時検証は「デフォルト設定のみ」と明記
- ✅ コメントで「実際の検証は起動時」と説明
- ✅ 誤解を防ぐ

---

## 検証タイミングの整理

| タイミング | 対象 | ツール | 必須？ | 効果 |
|----------|------|--------|-------|------|
| **ホスト側** | .devcontainer/supervisord/supervisord.conf | validate-config.sh | オプション | 早期フィードバック |
| **ビルド時** | supervisord.conf.default | supervisord -t | 必須 | デフォルト設定の検証 |
| **起動時** | マウントされた supervisord.conf | supervisord -t | **必須** | **実際に使われる設定を検証** |
| **稼働中** | supervisord プロセス | docker healthcheck | 推奨 | 継続的な監視 |

**最も重要なのは「起動時の検証」**

---

## Geminiのツッコミへの対応状況

| # | ツッコミ | v2の問題 | v3の対応 | 状態 |
|---|---------|---------|---------|------|
| ① | ビルド時検証の矛盾 | ビルド時にマウントされた設定を検証できない | 起動時（docker-entrypoint.sh）に検証 | ✅ 解決 |
| ② | DEBUG_MODE の偽陽性 | Up 状態だがサービスが動いていない | healthcheck 追加 + 警告メッセージ | ✅ 解決 |

---

## 実装手順

### Phase 1: 検証の移行

1. **docker-entrypoint.sh に検証を追加**
   - Phase 4 として supervisord.conf の検証を追加
   - `supervisord -t` で Fail Fast

2. **validate-config.sh を改訂**
   - ホスト側での事前チェック
   - supervisord/yq がなければ警告のみ

3. **Dockerfile のコメント追加**
   - ビルド時検証は「デフォルト設定のみ」と明記

### Phase 2: healthcheck の追加

4. **docker-compose.yml に healthcheck 追加**
   - DEBUG_MODE 時は免除
   - 通常時は supervisorctl で確認

### Phase 3: DEBUG_MODE の改善

5. **debug-entrypoint.sh を改訂**
   - 警告メッセージを明示
   - デバッグ手順を表示

---

## まとめ

### v3の改善点

1. **検証タイミングの修正（ツッコミ①対応）**
   - ビルド時 → 起動時に変更
   - マウントされた実際の設定ファイルを検証

2. **healthcheck の追加（ツッコミ②対応）**
   - コンテナステータスでサービスの稼働状況を確認
   - DEBUG_MODE 時は免除

3. **デバッグ体験の向上**
   - 警告メッセージで状況を明示
   - 混乱を防ぐ

### 最終設計の要点

| 観点 | 設計 |
|------|------|
| **配置方式** | バインドマウント + シンボリックリンク |
| **検証タイミング** | ホスト側（事前）→ 起動時（必須）→ 稼働中（監視） |
| **Fail Fast** | docker-entrypoint.sh で `supervisord -t` |
| **監視** | docker healthcheck で継続的確認 |
| **デバッグ** | DEBUG_MODE + 警告メッセージ |

### Geminiから得られた教訓

- ✅ **バインドマウントとビルド時検証は相性が悪い**
- ✅ **検証は適切なタイミングで行うべき**
- ✅ **healthcheck で継続的な監視を**
- ✅ **デバッグモードは「優しく」設計する**

---

## 参考資料

- [27_2_supervisord_config_strategy_revised.md](27_2_supervisord_config_strategy_revised.md): v2の設計
- [27_3_に対するgeminiのツッコミ.md](27_3_supervisord_config_strategy_revised_に対するgeminiのツッコミ.md): Geminiの第2回フィードバック
- [Supervisor Documentation](http://supervisord.org/)
- [Docker Compose Healthcheck](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck)

---

## 変更履歴

### 2026-01-03 v3
- ビルド時検証を起動時検証に変更（Geminiツッコミ①対応）
- docker healthcheck を追加（Geminiツッコミ②対応）
- DEBUG_MODE の警告メッセージ改善
- 検証タイミングの整理と明確化
