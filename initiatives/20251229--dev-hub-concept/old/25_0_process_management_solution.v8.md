# プロセス管理ツールの選定と実装（PID 1保護構成）

**作成日**: 2026-01-03
**バージョン**: v8（PID 1保護構成・s6-overlay採用）
**関連**:
- [25_process_management_solution.v7.md](25_process_management_solution.v7.md) - v7（PID 1問題発覚）
- [25_process_management_solution.v6.md](25_process_management_solution.v6.md) - ハイブリッド構成の基礎
- [28_0_supervisord_config_implementation_strategy.md](28_0_supervisord_config_implementation_strategy.md) - 2層構造の提案

---

## １．課題（目標とのギャップ）

### v7で発覚した致命的な問題

**supervisord を PID 1 にすると、設定変更後の再起動ができない**

```
開発者の操作:
1. configs/supervisord/project.conf を編集（新プロセス追加）
2. supervisord を再起動して設定を反映
3. → PID 1 が終了 → コンテナ全体が終了

または、AIエージェントの誤操作:
1. AIに「supervisordを再起動して」と指示
2. AI: supervisord コマンドを再実行
3. → PID 1 が終了 → コンテナ全体が終了
```

### 見落としていた要求

v7までの設計で以下の要求を**完全に見落としていた**:

1. ❌ **設定変更後の柔軟な再読み込み**
   - 開発環境では頻繁に設定を変更する
   - 毎回コンテナを再起動するのは非効率

2. ❌ **プロセス管理ツール自体の再起動可能性**
   - supervisord 自体がクラッシュした場合の復旧
   - AIエージェントが誤って supervisord を終了させた場合の自動復旧

3. ❌ **AIエージェントによる破壊的操作の防止**
   - AIが「supervisordを再起動」を文字通り解釈してコンテナを落とす
   - 開発環境として致命的

### v7との比較

| 要素 | v7の設計 | 現実の問題 |
|------|---------|----------|
| PID 1 | supervisord | 再起動でコンテナ終了 |
| 設定変更 | supervisorctl reload | AIが理解せず supervisord 再実行 |
| フォールバック | seed.conf で起動 | supervisord 終了で意味なし |
| 堅牢性 | Web UI + healthcheck | PID 1 を守る仕組みなし |

---

## ２．原因

### 根本原因

1. **「PID 1 は再起動できない」という Docker の基本を軽視**
   - Linux コンテナでは PID 1 が終了するとコンテナ全体が終了する
   - これは仕様であり、回避不可能

2. **「開発環境としての柔軟性」の定義が不十分**
   - 「複数プロセスを管理できる」だけでなく
   - 「頻繁に設定を変更できる」「ツール自体を再起動できる」が必要

3. **AIエージェントとの協調を考慮していない**
   - AIは「supervisordを再起動して」と言われたら素直に再実行する
   - 「supervisorctl reload を使うべき」という文脈理解は期待できない

---

## ３．目的（あるべき状態）

### 実現したい状態

1. **PID 1 の不変性と堅牢性**
   - PID 1 は軽量な init プロセス（tini または s6-overlay）
   - supervisord や process-compose が終了してもコンテナは維持される
   - 必要に応じて自動的に再起動される

2. **設定変更の柔軟性**
   - configs/ 配下の設定を編集後、すぐに反映可能
   - supervisord 自体を再起動しても問題なし
   - AIエージェントが誤操作してもコンテナは落ちない

3. **2層構造の維持**
   - シード設定（.devcontainer/）と実運用設定（configs/）の分離
   - フォールバック機構（設定エラー時はcode-serverのみで起動）

4. **開発者体験の向上**
   - 「何をしてもコンテナは落ちない」という安心感
   - Web UI または TUI でプロセス管理
   - ログが見やすい、デバッグしやすい

---

## ４．戦略・アプローチ（解決の方針）

### 基本戦略

1. **PID 1 を専用の init プロセスにする**
   - 候補: tini, s6-overlay, dumb-init
   - supervisord は PID 1 から管理される側に変更

2. **s6-overlay を採用（推奨）**
   - 理由:
     - プロセス監視・自動再起動機能を持つ
     - supervisord が落ちても自動復旧
     - Docker環境での実績が豊富
     - 軽量（イメージサイズ増加は数MB程度）

3. **supervisord の役割を再定義**
   - PID 1 ではなく、s6-overlay 管理下のサービスの1つ
   - Web UI による可視化とプロセス管理
   - 再起動しても s6-overlay が保護

4. **2層構造は v7 を踏襲**
   - configs/supervisord/ と .devcontainer/supervisord/seed.conf
   - フォールバック機構も継続

---

## ５．解決策（3つの異なる、比較可能な解決策）

### 解決策1: s6-overlay + supervisord（推奨）

**アーキテクチャ**:
```
PID 1: s6-overlay (init + プロセス監視)
  ├─ s6-svscan (サービススキャナー)
  │   ├─ docker-entrypoint (初期化スクリプト)
  │   └─ supervisord (プロセス管理)
  │       ├─ code-server
  │       ├─ difit
  │       └─ その他のアプリケーション
  └─ zombie reaping (ゾンビプロセス回収)
```

**Dockerfile**:
```dockerfile
# s6-overlay のインストール
ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && \
    rm /tmp/s6-overlay-*.tar.xz

# supervisord インストール（既存）
RUN apt-get update && apt-get install -y supervisor

# s6-overlay 用のサービス定義
COPY .devcontainer/s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# シード設定をコピー
COPY .devcontainer/supervisord/seed.conf /etc/supervisor/seed.conf

# s6-overlay をエントリーポイントに
ENTRYPOINT ["/init"]

# CMD はなし（s6-overlay がサービスを起動）
```

**s6-overlay サービス定義**:

`.devcontainer/s6-rc.d/user/contents.d/`:
```
docker-entrypoint
supervisord
```

`.devcontainer/s6-rc.d/docker-entrypoint/run`:
```bash
#!/usr/bin/with-contenv bash
/usr/local/bin/docker-entrypoint.sh
```

`.devcontainer/s6-rc.d/supervisord/run`:
```bash
#!/usr/bin/with-contenv bash
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
```

**利点**:
- ✅ supervisord を何度再起動してもコンテナは落ちない
- ✅ supervisord がクラッシュしても s6-overlay が自動再起動
- ✅ Web UI（supervisord）による可視化
- ✅ AIエージェントが誤操作してもコンテナ保護
- ✅ 2層構造（configs/ + seed.conf）を維持

**欠点**:
- ⚠️ s6-overlay の学習コストが追加
- ⚠️ ディレクトリ構造がやや複雑化（.devcontainer/s6-rc.d/）
- ⚠️ イメージサイズが数MB増加

**実装コスト**: 中

---

### 解決策2: tini + supervisord（軽量版）

**アーキテクチャ**:
```
PID 1: tini (最小限の init)
  └─ supervisord (プロセス管理)
      ├─ code-server
      ├─ difit
      └─ その他のアプリケーション
```

**Dockerfile**:
```dockerfile
# tini のインストール
RUN apt-get update && apt-get install -y tini

# supervisord インストール（既存）
RUN apt-get install -y supervisor

# シード設定をコピー
COPY .devcontainer/supervisord/seed.conf /etc/supervisor/seed.conf

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
```

**利点**:
- ✅ 非常にシンプル（tini は1つのバイナリ）
- ✅ イメージサイズ増加が最小限（数十KB）
- ✅ ゾンビプロセスの回収機能あり

**欠点**:
- ❌ supervisord がクラッシュしても自動再起動しない
- ❌ supervisord を手動で再起動した場合、PID が変わるだけでコンテナは落ちない（これは利点でもある）
- ⚠️ プロセス監視機能がない（単なる init のみ）

**実装コスト**: 低

**評価**:
- シンプルさは魅力的だが、「supervisord がクラッシュした場合に自動復旧しない」のは開発環境として不安
- ただし、supervisord 自体は安定しているので、実用上は問題ないかもしれない

---

### 解決策3: process-compose 単独 + tini（YAML重視）

**アーキテクチャ**:
```
PID 1: tini (最小限の init)
  └─ process-compose (プロセス管理)
      ├─ code-server
      ├─ difit
      └─ その他のアプリケーション
```

**Dockerfile**:
```dockerfile
# tini のインストール
RUN apt-get install -y tini

# process-compose インストール（既存）
ARG PROCESS_COMPOSE_VERSION=1.85.0
RUN curl -L "..." && tar -xzf ...

# シード設定をコピー
COPY .devcontainer/process-compose/seed.yaml /etc/process-compose/seed.yaml

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/process-compose", "-f", "/etc/process-compose/project.yaml"]
```

**利点**:
- ✅ YAML設定で親しみやすい
- ✅ TUIがデフォルト
- ✅ tini で PID 1 保護

**欠点**:
- ❌ Web UI がない（APIはあるが、UIは開発中）
- ❌ process-compose 自体がクラッシュしても自動再起動しない
- ⚠️ AIエージェントの知識が不足している可能性

**実装コスト**: 低

**評価**:
- Web UI がないのは痛い（特にフォールバック時の確認）
- TUI派には魅力的だが、ブラウザ派には不便

---

## ６．比較表

| 観点 | 解決策1（s6-overlay + supervisord） | 解決策2（tini + supervisord） | 解決策3（tini + process-compose） |
|------|-----------------------------------|------------------------------|----------------------------------|
| **PID 1 保護** | ✅ 完璧 | ✅ あり | ✅ あり |
| **自動復旧** | ✅ supervisord クラッシュ時も自動再起動 | ❌ なし | ❌ なし |
| **シンプルさ** | ⚠️ やや複雑（s6-rc.d/） | ✅ 非常にシンプル | ✅ シンプル |
| **Web UI** | ✅ あり（supervisord） | ✅ あり（supervisord） | ❌ なし |
| **TUI** | ❌ なし | ❌ なし | ✅ あり（process-compose） |
| **AI相性** | ✅ 高い | ✅ 高い | ⚠️ 未知数 |
| **イメージサイズ** | +数MB | +数十KB | +数MB |
| **実装コスト** | 中 | 低 | 低 |
| **堅牢性** | ✅✅ 最高 | ✅ 良好 | ✅ 良好 |
| **開発者体験** | ✅ 「何をしても大丈夫」感 | ✅ 良好 | ⚠️ Web UIなし |

---

## ７．推奨解決策

### **解決策1（s6-overlay + supervisord）を推奨**

**決定理由**:

1. **堅牢性が最優先**
   - Monolithic DevContainer の目的は「環境を考えなくていい」こと
   - supervisord が何らかの理由でクラッシュしても、自動復旧する安心感
   - AIエージェントがどんな操作をしてもコンテナは落ちない

2. **Web UI の重要性**
   - フォールバック時に「何が起動しているか」を視覚的に確認
   - AIエージェントに「Web UI を見て」と指示可能
   - process-compose の TUI より汎用的

3. **学習コストは許容範囲**
   - s6-overlay のサービス定義は一度作れば変更不要
   - 開発者は s6-overlay を意識せず、supervisord だけを触る
   - ドキュメントで「なぜ s6-overlay を使うか」を説明すれば理解しやすい

4. **長期的な保守性**
   - s6-overlay は Docker 公式イメージでも採用されている
   - コミュニティが活発で、情報が豊富
   - 将来的に他のサービス（例：DBの自動起動）を追加する際も柔軟に対応

5. **トレードオフの評価**
   - 複雑性の増加（s6-rc.d/ ディレクトリ）: 一度セットアップすれば変更不要
   - イメージサイズ増加（数MB）: 開発環境なので許容可能
   - → メリット（堅牢性・自動復旧）がデメリットを上回る

---

## ８．実装内容（解決策1ベース）

### 8.1 ディレクトリ構造

```
<MonolithicDevContainerレポジトリ名>/
├── .devcontainer/
│   ├── s6-rc.d/                    # ★新規★ s6-overlay サービス定義
│   │   ├── user/
│   │   │   ├── contents.d/
│   │   │   │   ├── docker-entrypoint
│   │   │   │   └── supervisord
│   │   ├── docker-entrypoint/
│   │   │   ├── type              # oneshot
│   │   │   ├── up                # 実行スクリプト
│   │   │   └── dependencies.d/
│   │   │       └── base          # 依存関係
│   │   └── supervisord/
│   │       ├── type              # longrun
│   │       ├── run               # 実行スクリプト
│   │       └── dependencies.d/
│   │           └── docker-entrypoint
│   ├── supervisord/
│   │   └── seed.conf             # ダミー設定（ビルド用）
│   ├── docker-entrypoint.sh      # 起動時検証・シンボリックリンク作成
│   ├── validate-config.sh        # ホスト側事前検証
│   ├── debug-entrypoint.sh       # DEBUG_MODE用（修正必要）
│   ├── Dockerfile
│   └── docker-compose.yml
├── configs/                       # 実運用設定
│   └── supervisord/
│       └── project.conf
└── foundations/
    └── onboarding/
        └── s6-supervisord-guide.md
```

---

### 8.2 Dockerfile

```dockerfile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Base image
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM ubuntu:22.04

ARG TARGETARCH
ARG UID=1000
ARG GID=1000
ARG UNAME=<一般ユーザー>
ARG GNAME=<一般ユーザー>

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay: PID 1 保護・プロセス監視
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz

# アーキテクチャ別のバイナリ
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "x86_64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "x86_64" ;; \
    esac) && \
    curl -L "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz" \
    -o /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    rm /tmp/s6-overlay-arch.tar.xz

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: supervisord
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN apt-get update && \
    apt-get install -y supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# デフォルト設定をコピー（フォールバック用）
COPY .devcontainer/supervisord/seed.conf /etc/supervisor/seed.conf

# ★★★ ビルド時検証: シード設定のみ ★★★
RUN echo "🔍 Validating seed supervisord configuration..." && \
    supervisord -c /etc/supervisor/seed.conf -t && \
    echo "✅ Seed configuration is valid"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay サービス定義
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# サービス定義をコピー
COPY .devcontainer/s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# docker-entrypoint.sh を実行可能にする
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# ... 既存のツールインストール処理（code-server, asdf等）...

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entrypoint: s6-overlay
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ENTRYPOINT ["/init"]

# s6-overlay がサービスを起動するため、CMD は不要
```

---

### 8.3 s6-overlay サービス定義

#### `.devcontainer/s6-rc.d/user/contents.d/docker-entrypoint`
```
docker-entrypoint
```

#### `.devcontainer/s6-rc.d/user/contents.d/supervisord`
```
supervisord
```

#### `.devcontainer/s6-rc.d/docker-entrypoint/type`
```
oneshot
```

#### `.devcontainer/s6-rc.d/docker-entrypoint/up`
```bash
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh
```

#### `.devcontainer/s6-rc.d/docker-entrypoint/dependencies.d/base`
（空ファイル - base サービスに依存）

#### `.devcontainer/s6-rc.d/supervisord/type`
```
longrun
```

#### `.devcontainer/s6-rc.d/supervisord/run`
```bash
#!/command/with-contenv bash
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
```

#### `.devcontainer/s6-rc.d/supervisord/dependencies.d/docker-entrypoint`
（空ファイル - docker-entrypoint の後に起動）

---

### 8.4 docker-entrypoint.sh（v7とほぼ同じ）

```bash
#!/usr/bin/env bash

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Docker Entrypoint: Initializing container..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Phase 1-3: パーミッション、Docker Socket、Atuin（既存処理）
# ...

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 4: supervisord設定ファイルの検証とフォールバック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Phase 4: Validating supervisord configuration..."

UNAME=${UNAME:-$(whoami)}
REPO_NAME=${REPO_NAME:-"<MonolithicDevContainerレポジトリ名>"}

PROJECT_CONF="/home/${UNAME}/${REPO_NAME}/configs/supervisord/project.conf"
SEED_CONF="/etc/supervisor/seed.conf"
TARGET_CONF="/etc/supervisor/supervisord.conf"

# 実運用設定の存在確認
if [ -f "${PROJECT_CONF}" ]; then
    echo "  ✅ Found: ${PROJECT_CONF}"

    # シンボリックリンク作成
    sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"

    # 検証
    if supervisord -c "${TARGET_CONF}" -t 2>&1; then
        echo "  ✅ project.conf is valid"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️   WARNING: FALLBACK MODE ACTIVE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "configs/supervisord/project.conf validation failed."
        echo "Using seed config (code-server only)."
        echo ""
        echo "supervisord will start with minimal config."
        echo "You can fix the config and restart supervisord:"
        echo "  supervisorctl restart supervisord"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
    fi
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️   WARNING: FALLBACK MODE ACTIVE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "configs/supervisord/project.conf not found."
    echo "Using seed config (code-server only)."
    echo ""
    echo "To create the config:"
    echo "  1. Create: configs/supervisord/project.conf"
    echo "  2. Restart supervisord: supervisorctl restart supervisord"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
fi

echo "  Using config: ${TARGET_CONF}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

**重要な変更点**:
- `exec "$@"` を削除（s6-overlay が管理するため不要）
- フォールバック時のメッセージに「supervisorctl restart supervisord」を追加
  - **これが v7 との決定的な違い**: supervisord を再起動してもコンテナは落ちない

---

### 8.5 seed.conf（ダミー設定）

```ini
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# これはビルド用のダミー設定です
# 実際の設定は configs/supervisord/project.conf を編集してください
#
# このファイルは以下の場合にのみ使用されます:
# 1. ビルド時の構文検証
# 2. configs/supervisord/project.conf が見つからない場合
# 3. configs/supervisord/project.conf にエラーがある場合
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0

[inet_http_server]
port=*:9001
username=admin
password=admin

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=http://127.0.0.1:9001

# 最小限のプロセス: code-server のみ
[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>
autostart=true
autorestart=false
priority=10
environment=CODE_SERVER_PORT="4035",HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

---

### 8.6 configs/supervisord/project.conf（実運用設定）

```ini
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Supervisord 実運用設定
# このファイルを編集後、以下のコマンドで反映:
#   supervisorctl reread
#   supervisorctl update
#
# または、supervisord 自体を再起動:
#   supervisorctl restart supervisord
# （s6-overlay が保護しているので、コンテナは落ちません）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[inet_http_server]
port=*:9001
username=admin
password=admin

[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

# ========================================
# 安定稼働が必要なサービス
# ========================================

[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>
autostart=true
autorestart=false
priority=10
environment=CODE_SERVER_PORT="4035",HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# ========================================
# 開発ツール（必要に応じて追加）
# ========================================

[program:difit]
command=/home/<一般ユーザー>/.asdf/shims/difit
user=<一般ユーザー>
directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>
autostart=false
autorestart=false
priority=20
environment=HOME="/home/<一般ユーザー>"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

---

## ９．使い方ガイド

### 設定変更後の反映方法

**重要**: v8 では supervisord を再起動してもコンテナは落ちません

```bash
# 方法1: 設定を再読み込み（推奨）
supervisorctl reread   # 設定ファイルを再読み込み
supervisorctl update   # 変更を反映（新規プロセスを追加）

# 方法2: supervisord 自体を再起動
supervisorctl restart supervisord
# または
s6-svc -t /run/service/supervisord

# ★ v7 との違い: どちらの方法でもコンテナは落ちない ★
```

### AIエージェントへの指示例

```
# AIに「supervisordを再起動して」と指示しても安全
ユーザー: configs/supervisord/project.conf を編集したので、supervisordを再起動してください

AI: わかりました。supervisordを再起動します。
$ supervisorctl restart supervisord
Restarted supervisord

# → コンテナは落ちない（s6-overlay が保護）
```

### フォールバック時の復旧方法

```bash
# 1. project.conf のエラーを修正
nano configs/supervisord/project.conf

# 2. supervisord を再起動（設定を再読み込み）
supervisorctl restart supervisord

# 3. Web UI で確認
# http://localhost:9001
```

---

## １０．メリット・デメリット

### メリット

1. **PID 1 保護が完璧**
   - ✅ supervisord を何度再起動してもコンテナは落ちない
   - ✅ supervisord がクラッシュしても s6-overlay が自動再起動
   - ✅ AIエージェントがどんな操作をしてもコンテナ保護

2. **設定変更の柔軟性**
   - ✅ configs/ を編集後、すぐに反映可能
   - ✅ `supervisorctl restart supervisord` が安全に使える

3. **開発者体験の向上**
   - ✅ 「何をしてもコンテナは落ちない」という安心感
   - ✅ Web UI で視覚的にプロセス管理
   - ✅ フォールバック機構も継続

4. **堅牢性**
   - ✅ プロセス監視・自動復旧
   - ✅ ゾンビプロセスの回収
   - ✅ Docker 公式イメージでも採用されている実績

### デメリット

1. **複雑性の増加**
   - ⚠️ s6-rc.d/ ディレクトリが追加
   - ⚠️ s6-overlay の仕組みを理解する必要がある

2. **学習コスト**
   - ⚠️ 開発者が s6-overlay の存在を知る必要がある
   - ⚠️ ただし、日常的には supervisord だけを触る

3. **イメージサイズ**
   - ⚠️ 数MB増加（開発環境なので許容範囲）

### トレードオフの評価

**デメリットは許容可能**:
- s6-rc.d/ は一度セットアップすれば変更不要
- 開発者は「supervisord を再起動しても大丈夫」だけ知っていればOK
- 堅牢性のメリットが複雑性のデメリットを大きく上回る

---

## １１．実装計画

### Phase 1: s6-overlay のセットアップ

**タスク**:
1. s6-overlay のダウンロードURLを Dockerfile に追加
2. .devcontainer/s6-rc.d/ ディレクトリ作成
3. サービス定義ファイル作成（docker-entrypoint, supervisord）

**検証**:
- イメージビルドが成功するか
- s6-overlay が正しくインストールされているか

---

### Phase 2: docker-entrypoint.sh 修正

**変更内容**:
- `exec "$@"` を削除
- フォールバック時のメッセージに「supervisorctl restart supervisord」を追加

**検証**:
- s6-overlay 経由で docker-entrypoint.sh が実行されるか
- 実行後に supervisord が起動するか

---

### Phase 3: configs/ ディレクトリ準備

**タスク**:
1. configs/supervisord/ ディレクトリ作成
2. seed.conf 作成（ダミー設定）
3. project.conf 作成（実運用設定）

**検証**:
- ファイルが正しい場所に配置されているか
- 構文が有効か

---

### Phase 4: 動作確認

**テストケース**:

1. **正常系**: project.conf が有効
   - コンテナ起動
   - supervisord が project.conf を読み込む
   - Web UI で確認

2. **異常系**: project.conf にエラー
   - コンテナ起動
   - seed.conf にフォールバック
   - Web UI で code-server のみが起動

3. **再起動テスト**: supervisord の再起動
   - `supervisorctl restart supervisord` を実行
   - コンテナが落ちないことを確認
   - supervisord が再起動することを確認

4. **AIエージェントテスト**: AIに supervisord 再起動を指示
   - AIが `supervisorctl restart supervisord` を実行
   - コンテナが落ちないことを確認

---

### Phase 5: ドキュメント整備

**作成するドキュメント**:
1. `foundations/onboarding/s6-supervisord-guide.md`
   - s6-overlay + supervisord のアーキテクチャ説明
   - なぜ s6-overlay を使うのか
   - supervisord の再起動方法
   - フォールバック時の対処法

2. `configs/supervisord/README.md`
   - project.conf の編集ガイド
   - 設定変更後の反映方法

---

## １２．v7 からの変更点まとめ

| 要素 | v7 | v8（推奨解決策） |
|------|---|-----------------|
| **PID 1** | supervisord | s6-overlay |
| **supervisord の位置** | PID 1 | s6-overlay 管理下のサービス |
| **再起動の可否** | ❌ 再起動でコンテナ終了 | ✅ 何度でも再起動可能 |
| **自動復旧** | ❌ なし | ✅ クラッシュ時に自動再起動 |
| **設定変更** | supervisorctl reload のみ | reload も restart も安全 |
| **AI誤操作** | ❌ コンテナを落とすリスク | ✅ 保護される |
| **複雑性** | シンプル | やや複雑（s6-rc.d/） |
| **堅牢性** | 良好 | 最高 |

---

## １３．リスクと対策

### リスク1: s6-overlay の学習コスト

**リスク**: 開発者が s6-overlay を理解できない

**対策**:
- 詳細なドキュメント作成
- 「supervisord だけを触ればOK」と明記
- s6-overlay は「裏で動いている保護機構」と説明

### リスク2: デバッグの複雑化

**リスク**: s6-overlay のログと supervisord のログが混在

**対策**:
- s6-overlay のログは /run/s6-overlay/ に保存
- supervisord のログは stdout/stderr に出力（既存通り）
- Web UI で supervisord のプロセスを確認

### リスク3: イメージサイズ増加

**リスク**: s6-overlay で数MB増加

**対策**:
- 開発環境なので許容可能
- 必要であれば multi-stage build で最適化

---

## １４．次のステップ

### 即座に実行すべきタスク

1. **s6-overlay のセットアップ**
   - Dockerfile 修正
   - s6-rc.d/ ディレクトリ作成

2. **動作確認**
   - ビルド成功
   - supervisord 再起動テスト

3. **ドキュメント作成**
   - s6-supervisord-guide.md

### 長期的なタスク

- [ ] AIエージェントとの相性テスト
- [ ] s6-overlay の他の機能活用（例：環境変数管理）
- [ ] process-compose への移行可能性の検討（s6-overlay ベースで）

---

## １５．参考資料

- [s6-overlay Documentation](https://github.com/just-containers/s6-overlay)
- [Supervisor Documentation](http://supervisord.org/)
- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- [27_4_supervisord_config_final_design.md](27_4_supervisord_config_final_design.md) - v3検証戦略
- [25_process_management_solution.v7.md](25_process_management_solution.v7.md) - v7（PID 1問題発覚版）

---

## １６．変更履歴

### v8 (2026-01-03)
- **PID 1 保護の実装**: s6-overlay を採用
- supervisord を s6-overlay 管理下のサービスに変更
- supervisord の再起動が安全に実行可能に
- AIエージェントによるコンテナ破壊リスクを排除
- v7 で見落としていた「設定変更の柔軟性」要求を実現
- 2層構造（configs/ + seed.conf）は v7 を踏襲
