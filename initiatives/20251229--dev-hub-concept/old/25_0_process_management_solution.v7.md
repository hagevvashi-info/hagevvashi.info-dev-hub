# プロセス管理ツールの選定と2層設定構造の統合戦略

**作成日**: 2026-01-03
**バージョン**: v7（2層構造統合版）
**関連**:
- [25_process_management_solution.v6.md](25_process_management_solution.v6.md) - ハイブリッド構成の基礎
- [28_0_supervisord_config_implementation_strategy.md](28_0_supervisord_config_implementation_strategy.md) - 2層構造の提案
- [28_1_supervisord_config_implementation_strategy_に対する考察.md](28_1_supervisord_config_implementation_strategy_に対する考察.md) - シード層の再解釈
- [27_4_supervisord_config_final_design.md](27_4_supervisord_config_final_design.md) - v3検証戦略

---

## １．課題（目標とのギャップ）

### 現在の状況

**v6までで決定した構成**:
- supervisord（またはprocess-compose）をPID 1として採用
- 2層設定構造（シード設定 + 実運用設定）の必要性が明確化

**残された課題**:
1. **設定ファイルの配置戦略が未確定**
   - シード設定（ダミー）と実運用設定の物理的な配置場所
   - ディレクトリ構造の命名（`runtime/` vs `configs/` vs `operations/`）
2. **検証戦略が実装と乖離**
   - v3（27_4）で設計した検証戦略が、2層構造を前提としていない
   - 「ビルド時検証」と「起動時検証」の対象ファイルが曖昧
3. **プロセス管理ツールの最終決定が保留**
   - supervisord と process-compose のどちらを採用するか
   - または両方をハイブリッド運用するか

---

## ２．原因

### 設計上の原因

1. **段階的な設計の副作用**
   - v1→v6: プロセス管理ツールの選定に集中
   - 27系: 設定ファイルの配置戦略に集中
   - 28系: 2層構造の理論に集中
   - **結果**: それぞれの知見が統合されていない

2. **「ビルド時検証の対象」の誤解**
   - 当初: ビルド時に「実際に使う設定」を検証しようとした
   - Geminiの指摘: バインドマウント方式では不可能（鶏と卵問題）
   - 再解釈: シードはあくまで「ビルドを通すためのダミー」

3. **ネーミングの曖昧性**
   - `runtime/`: 一時ファイル（pid, sock）を連想させる
   - `operations/`: DevOps感が強すぎる
   - 開発者にとって「ここを編集するんだな」という直感が欠如

---

## ３．目的（あるべき状態）

### 実現したい状態

1. **明確な2層構造**
   - **シード層**: `.devcontainer/` 配下、ビルド用ダミー、COPY対象、不変
   - **実運用層**: プロジェクトルート配下、開発者編集、バインドマウント対象、可変
   - それぞれの責務が明確で、開発者が迷わない

2. **3段階検証戦略の確立**
   - **ホスト側（事前）**: validate-config.sh による基本チェック
   - **ビルド時**: シード設定（ダミー）の構文検証
   - **起動時**: 実運用設定の存在確認・構文検証・シンボリックリンク作成

3. **フォールバック機構の実装**
   - 実運用設定エラー時: シード設定（code-serverのみ）で起動
   - 開発者への明確な通知（ログ + Web UI）
   - コンテナ内からの修正が可能

4. **プロセス管理ツールの決定**
   - supervisord または process-compose のどちらか一方に決定
   - または、明確な役割分担でハイブリッド運用

---

## ４．戦略・アプローチ（解決の方針）

### 基本戦略

1. **「設定ディレクトリ」の命名決定を優先**
   - ネーミングが開発者体験に直結するため、最優先で決定
   - 候補: `configs/`, `manifests/`, `compositions/`

2. **2層構造の物理的配置を確定**
   - シード層: `.devcontainer/supervisord/seed.conf` (または同等)
   - 実運用層: `<決定したディレクトリ>/supervisord/`

3. **検証戦略を2層構造に適合させる**
   - 27_4の3段階検証をベースに、「何を検証するか」を明確化
   - ビルド時: シード設定のみ
   - 起動時: 実運用設定のみ

4. **フォールバック実装**
   - docker-entrypoint.sh で実運用設定の検証
   - エラー時: シード設定へのフォールバック + 警告表示

5. **プロセス管理ツール決定基準の設定**
   - 決定基準: AIエージェントとの相性、開発者の好み、UI/TUIの選択
   - 並行運用期間での評価

---

## ５．解決策（3つの異なる、比較可能な解決策）

### 解決策1: configs/ ベース・シンプル分離（推奨）

**概要**:
- **実運用設定**: `configs/supervisord/project.conf`
- **シード設定**: `.devcontainer/supervisord/seed.conf`
- プロセス管理ツール: **supervisord単独採用**（Web UIを重視）

**ディレクトリ構造**:
```
<MonolithicDevContainerレポジトリ名>/
├── .devcontainer/
│   ├── supervisord/
│   │   └── seed.conf              # ダミー設定（ビルド用）
│   ├── docker-entrypoint.sh       # 起動時検証・シンボリックリンク作成
│   ├── validate-config.sh         # ホスト側事前検証
│   ├── debug-entrypoint.sh        # DEBUG_MODE用
│   ├── Dockerfile
│   └── docker-compose.yml
├── configs/                        # ★新規ディレクトリ★
│   └── supervisord/
│       └── project.conf           # 実運用設定（開発者編集）
└── foundations/
    └── onboarding/
        └── process-management-guide.md
```

**seed.conf の内容** (ダミー・最小構成):
```ini
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# これはビルド用のダミー設定です
# 実際の設定は configs/supervisord/project.conf を編集してください
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[supervisord]
nodaemon=true
user=root

[inet_http_server]
port=*:9001

[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
autostart=true
autorestart=false
```

**project.conf の内容** (実運用設定):
```ini
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

[program:docker-entrypoint]
command=/usr/local/bin/docker-entrypoint.sh
user=<一般ユーザー>
autostart=true
autorestart=false
startsecs=0
priority=1

[program:code-server]
command=/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
autostart=true
autorestart=false
priority=10

[program:difit]
command=/home/<一般ユーザー>/.asdf/shims/difit
user=<一般ユーザー>
autostart=false
autorestart=false
priority=20
```

**検証戦略**:
```bash
# ビルド時（Dockerfile内）
RUN supervisord -c /etc/supervisor/seed.conf -t

# 起動時（docker-entrypoint.sh Phase 4）
if [ -f "/home/${UNAME}/${REPO_NAME}/configs/supervisord/project.conf" ]; then
    sudo ln -sf "/home/${UNAME}/${REPO_NAME}/configs/supervisord/project.conf" /etc/supervisor/supervisord.conf
    if ! supervisord -c /etc/supervisor/supervisord.conf -t; then
        echo "⚠️  FALLBACK: Using seed config (code-server only)"
        sudo ln -sf /etc/supervisor/seed.conf /etc/supervisor/supervisord.conf
    fi
else
    echo "⚠️  FALLBACK: configs/supervisord/project.conf not found"
    sudo ln -sf /etc/supervisor/seed.conf /etc/supervisor/supervisord.conf
fi
```

**利点**:
- ✅ `configs/` はシンプルで直感的、開発者が「ここを編集する」と即座に理解
- ✅ シード設定が最小限（code-serverのみ）で、フォールバックの意図が明確
- ✅ supervisord単独でシンプル、Web UIで全体管理可能
- ✅ 実装コストが低い

**欠点**:
- ⚠️ TUIファンには不満（process-composeなし）
- ⚠️ 個人設定と組織設定の分離が不十分（全て `project.conf` に混在）

**実装ステップ**:
1. `configs/supervisord/` ディレクトリ作成
2. `seed.conf` と `project.conf` を作成
3. Dockerfile修正（seed.conf を COPY、検証）
4. docker-entrypoint.sh Phase 4 実装（検証・シンボリックリンク・フォールバック）
5. validate-config.sh 更新
6. docker-compose.yml healthcheck 追加（27_4 v3ベース）

---

### 解決策2: configs/ ベース・拡張分離（チーム開発対応）

**概要**:
- 解決策1をベースに、**組織共通設定と個人設定を分離**
- `configs/supervisord/team.conf` (Git管理) + `configs/supervisord/*.local.conf` (Git管理外)
- プロセス管理ツール: supervisord単独

**ディレクトリ構造**:
```
configs/
└── supervisord/
    ├── team.conf           # チーム共通設定（Git管理）
    ├── user.local.conf     # 個人設定（.gitignore）
    └── .gitignore          # *.local.conf を除外
```

**team.conf の内容**:
```ini
# チーム共通のプロセス定義
[include]
files = /home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/configs/supervisord/*.local.conf

[program:code-server]
# 共通設定...

[program:difit]
# 共通設定...
```

**user.local.conf の例**:
```ini
# 個人用の実験的プロセス
[program:my-experiment]
command=npm run dev
working_dir=/home/<一般ユーザー>/repos/my-project
autostart=false
```

**利点**:
- ✅ チーム開発でのコンフリクト回避
- ✅ 個人の実験的設定がGitコミットに混入しない
- ✅ includeで柔軟に設定を統合

**欠点**:
- ⚠️ 設定が複数ファイルに分散、初学者には複雑
- ⚠️ 起動時検証で「どのファイルがエラーか」の特定が難しい

**実装ステップ**:
- 解決策1 + include設定 + .gitignore追加

---

### 解決策3: process-compose単独採用・YAML中心（モダン派）

**概要**:
- **プロセス管理ツール: process-compose単独採用**
- supervisordは使わず、process-composeをPID 1として起動
- 設定: `configs/process-compose/project.yaml`

**ディレクトリ構造**:
```
configs/
└── process-compose/
    └── project.yaml
.devcontainer/
└── process-compose/
    └── seed.yaml           # ダミー設定
```

**seed.yaml** (ダミー):
```yaml
version: "0.5"
processes:
  code-server:
    command: "/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password"
    working_dir: "/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>"
```

**project.yaml** (実運用):
```yaml
version: "0.5"

log_location: /tmp/process-compose-${USER}.log
log_level: info

processes:
  code-server:
    command: "/home/<一般ユーザー>/.local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password"
    working_dir: "/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>"
    availability:
      restart: "no"

  difit:
    command: "difit"
    working_dir: "/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>"
    availability:
      restart: "no"
    depends_on:
      code-server:
        condition: process_started
```

**利点**:
- ✅ YAMLで親しみやすい（docker-composeライク）
- ✅ TUIがデフォルト、ターミナルワークフローに最適
- ✅ 依存関係の記述が柔軟
- ✅ モダンで、今後の拡張性が高い

**欠点**:
- ⚠️ Web UIがない（APIはあるが、公式UIは開発中）
- ⚠️ supervisordより新しく、AIエージェントの知識が不足している可能性
- ⚠️ 枯れた技術ではない（プロダクション実績が少ない）

**実装ステップ**:
- 解決策1のsupervisord部分をprocess-composeに置き換え
- CMD修正: `process-compose -f /etc/process-compose/project.yaml`

---

## ６．比較表

| 観点 | 解決策1（configs/・supervisord単独） | 解決策2（configs/・拡張分離） | 解決策3（process-compose単独） |
|------|-------------------------------------|------------------------------|-------------------------------|
| **シンプルさ** | ✅ 非常にシンプル | ⚠️ やや複雑 | ✅ シンプル（YAMLに慣れていれば） |
| **Web UI** | ✅ あり（supervisord） | ✅ あり（supervisord） | ❌ なし |
| **TUI** | ❌ なし | ❌ なし | ✅ あり（デフォルト） |
| **チーム開発** | ⚠️ 全員が同じproject.conf | ✅ team + local分離 | ⚠️ 全員が同じproject.yaml |
| **AIエージェント相性** | ✅ 高い（枯れた技術） | ✅ 高い（枯れた技術） | ⚠️ 未知数（新しい技術） |
| **設定ファイル** | INI形式（1ファイル） | INI形式（複数ファイル） | YAML形式（1ファイル） |
| **実装コスト** | 低 | 中 | 低 |
| **長期保守性** | 高 | 高 | 中〜高（技術の成熟度次第） |

---

## ７．推奨解決策

### **解決策1（configs/ ベース・supervisord単独）を推奨**

**理由**:

1. **シンプルさが最優先**
   - Monolithic DevContainerの目的は「環境を考えなくていい」こと
   - 設定の複雑さは開発者の認知負荷を増やす
   - 解決策1が最もシンプルで、初学者にも優しい

2. **Web UIの重要性**
   - ブラウザでプロセス状態を確認できるのは、デバッグ時に非常に便利
   - AIエージェントに「Web UIを見て」と指示できる
   - TUIは好みの問題だが、Web UIは普遍的

3. **AIエージェントとの相性**
   - supervisordは枯れた技術で、AIの知識データベースに豊富
   - process-composeは新しく、AIが誤った情報を返すリスク

4. **段階的拡張が可能**
   - 解決策1で開始し、必要に応じて解決策2（チーム開発対応）に拡張可能
   - 逆（解決策2→1）の縮小は難しい

5. **ネーミングの直感性**
   - `configs/` は「設定ファイル置き場」として直感的
   - `runtime/` より明確、`operations/` より親しみやすい

---

## ８．実装計画

### Phase 1: ディレクトリ構造の準備

**タスク**:
1. `configs/supervisord/` ディレクトリ作成
2. `.devcontainer/supervisord/seed.conf` 作成（ダミー設定）
3. `configs/supervisord/project.conf` 作成（実運用設定）

**検証**:
- ファイルが正しい場所に配置されているか確認
- seed.conf と project.conf の構文が有効か確認

---

### Phase 2: Dockerfile修正

**変更内容**:
```dockerfile
# supervisord インストール（既存）
RUN apt-get update && apt-get install -y supervisor

# シード設定をコピー
COPY .devcontainer/supervisord/seed.conf /etc/supervisor/seed.conf

# ★★★ ビルド時検証: シード設定のみ ★★★
RUN echo "🔍 Validating seed supervisord configuration..." && \
    supervisord -c /etc/supervisor/seed.conf -t && \
    echo "✅ Seed configuration is valid"

# CMD: DEBUG_MODE で切り替え
CMD [ "/bin/bash", "-c", "if [ \"${DEBUG_MODE:-false}\" = \"true\" ]; then exec /usr/local/bin/debug-entrypoint.sh; else exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf; fi" ]
```

**検証**:
- イメージビルドが成功するか
- ビルド時検証が seed.conf に対して実行されているか

---

### Phase 3: docker-entrypoint.sh Phase 4 実装

**実装内容**:
```bash
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
        echo "To fix:"
        echo "  1. Check syntax: configs/supervisord/project.conf"
        echo "  2. Restart container: docker-compose restart"
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
    echo "To fix:"
    echo "  1. Create: configs/supervisord/project.conf"
    echo "  2. Restart container: docker-compose restart"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
fi

echo "  Using config: ${TARGET_CONF}"
```

**検証**:
- 正常系: project.conf が有効な場合、それが使われるか
- 異常系: project.conf が壊れている場合、seed.conf にフォールバックするか
- 異常系: project.conf が存在しない場合、seed.conf にフォールバックするか

---

### Phase 4: validate-config.sh 更新

**更新内容**:
```bash
# Phase 2: supervisord.conf の基本的な構文チェック
echo ""
echo "🔍 Phase 2: Validating supervisord configs..."

# シード設定チェック
if grep -q "^\[supervisord\]" "${SCRIPT_DIR}/supervisord/seed.conf"; then
    echo "  ✅ seed.conf: [supervisord] section found"
else
    echo "  ❌ seed.conf: [supervisord] section not found"
    exit 1
fi

# 実運用設定チェック
PROJECT_CONF="${SCRIPT_DIR}/../configs/supervisord/project.conf"
if [ -f "${PROJECT_CONF}" ]; then
    if grep -q "^\[supervisord\]" "${PROJECT_CONF}"; then
        echo "  ✅ project.conf: [supervisord] section found"
    else
        echo "  ❌ project.conf: [supervisord] section not found"
        exit 1
    fi

    # supervisord がホストにある場合は詳細チェック
    if command -v supervisord >/dev/null 2>&1; then
        if supervisord -c "${PROJECT_CONF}" -t; then
            echo "  ✅ project.conf is valid (detailed check)"
        else
            echo "  ❌ project.conf validation failed"
            exit 1
        fi
    fi
else
    echo "  ⚠️  project.conf not found (will be created later)"
fi
```

**検証**:
- ホスト側で実行し、seed.conf と project.conf の両方をチェック

---

### Phase 5: docker-compose.yml healthcheck 追加

**追加内容**（27_4 v3ベース）:
```yaml
services:
  dev:
    # ... 既存設定 ...

    environment:
      - DEBUG_MODE=false  # true にするとデバッグモード

    healthcheck:
      test: |
        if [ "$DEBUG_MODE" = "true" ]; then
          exit 0
        else
          supervisorctl status code-server | grep -q RUNNING || exit 1
        fi
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
```

**検証**:
- `docker ps` で healthcheck の状態が確認できるか
- code-server が起動していない場合、unhealthy になるか

---

### Phase 6: ドキュメント整備

**作成するドキュメント**:
1. `foundations/onboarding/supervisord-guide.md`
   - 2層構造の説明
   - 設定ファイルの編集方法
   - フォールバック時の対処法
2. `configs/supervisord/README.md`
   - project.conf の編集ガイド
   - 巨大な警告コメント（シード設定を編集しないように）

---

## ９．プロセス管理ツール決定基準

### 並行運用からの決定は見送り

**判断理由**:
- v6のハイブリッド構成は「両方試してから決める」アプローチ
- しかし、28系の2層構造を優先すると、実装コストが2倍になる
- **まずsupervisordで2層構造を完成させ、必要に応じてprocess-composeを検討**

### supervisord採用の決定的理由

1. **Web UIの存在**
   - フォールバック時に「何が起動しているか」を視覚的に確認できる
   - AIエージェントに「supervisord Web UIを確認して」と指示可能

2. **AIエージェントとの相性**
   - Claude、Gemini、Devinなど、主要AIは全てsupervisordの知識を持つ
   - process-composeは新しく、AIの回答精度が不安定

3. **枯れた技術**
   - 長年の実績があり、トラブルシューティング情報が豊富
   - 開発環境としての安定性が重要

### process-compose検討のタイミング

**将来的に検討すべきケース**:
- ✅ supervisord Web UIに不満が出た場合
- ✅ TUIでの開発体験を向上させたい場合
- ✅ 依存関係の複雑な管理が必要になった場合

**その場合の移行戦略**:
- `configs/process-compose/` を追加
- 2層構造はそのまま（設計の再利用）
- supervisord → process-compose への段階的移行

---

## １０．リスクと対策

### リスク1: 開発者がシード設定を誤編集

**リスク**:
- `.devcontainer/supervisord/seed.conf` を編集してしまう
- 変更がコンテナ再起動後に失われ、混乱

**対策**:
- seed.conf の先頭に巨大な警告コメント
- README.md での明確な説明
- validate-config.sh でのチェック

### リスク2: フォールバックに気づかない

**リスク**:
- project.conf がエラーでもコンテナは起動（seed.confで）
- 開発者が「なぜdifitが起動しないのか」と悩む

**対策**:
- docker-entrypoint.sh での派手な警告メッセージ
- healthcheck で異常を通知
- Web UIで「code-serverのみ」が一目瞭然

### リスク3: configs/ の命名変更要求

**リスク**:
- 将来的に「やっぱり runtime/ がいい」となる可能性

**対策**:
- 初期段階でネーミングを確定
- Git管理しているので、必要なら一括リネーム可能

---

## １１．次のステップ

### 即座に実行すべきタスク

1. **ネーミングの最終確認**
   - `configs/` で確定するか、ユーザーに確認

2. **Phase 1実装**
   - ディレクトリ作成、seed.conf と project.conf 作成

3. **Phase 2実装**
   - Dockerfile修正、ビルドテスト

4. **Phase 3実装**
   - docker-entrypoint.sh Phase 4 実装、起動テスト

5. **Phase 4-6実装**
   - validate-config.sh、healthcheck、ドキュメント

### 長期的なタスク

- [ ] AIエージェントとの相性テスト（supervisord操作を指示）
- [ ] チーム開発時の運用フィードバック収集
- [ ] process-compose への移行可能性の検討

---

## １２．参考資料

- [Supervisor Documentation](http://supervisord.org/)
- [27_4_supervisord_config_final_design.md](27_4_supervisord_config_final_design.md) - v3検証戦略
- [28_0_supervisord_config_implementation_strategy.md](28_0_supervisord_config_implementation_strategy.md) - 2層構造の提案
- [28_1考察.md](28_1_supervisord_config_implementation_strategy_に対する考察.md) - Geminiとの議論

---

## １３．変更履歴

### v7 (2026-01-03)
- v6のハイブリッド構成と28系の2層構造を統合
- **configs/ ベース・supervisord単独**を推奨解決策として決定
- 3段階検証戦略を2層構造に適合（ビルド時=シード、起動時=実運用）
- フォールバック機構の詳細実装を設計
- 段階的実装計画（Phase 1-6）を策定
