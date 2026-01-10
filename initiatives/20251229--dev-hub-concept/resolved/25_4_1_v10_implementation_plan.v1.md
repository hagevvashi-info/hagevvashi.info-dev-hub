# v10プロセス管理設計の実装計画

**作成日**: 2026-01-03
**バージョン**: v1
**関連**:
- [25_0_process_management_solution.v10.md](25_0_process_management_solution.v10.md) - v10設計（目標）
- [14_詳細設計_ディレクトリ構成.v10.md](14_詳細設計_ディレクトリ構成.v10.md) - ディレクトリ構成設計

---

## １．課題（目標とのギャップ）

### v10設計と現在実装の乖離

v10設計ドキュメントは完成しているが、実装が追いついていない。

#### 主要な乖離ポイント

| 要素 | v10設計 | 現在の実装 | 乖離度 |
|------|---------|-----------|--------|
| **PID 1** | s6-overlay | supervisord | ❌ **重大** |
| **プロセス管理** | s6-overlay → supervisord/process-compose | supervisord直接 | ❌ **重大** |
| **設定ディレクトリ** | `workloads/` | `.devcontainer/supervisord/`<br>`.devcontainer/process-compose/` | ❌ **重大** |
| **2層構造** | seed.conf + workloads/project.conf | supervisord.conf（単層） | ❌ **重大** |
| **ディレクトリ構成ドキュメント** | v10あり | workloads反映なし | ⚠️ **中** |

### 具体的な問題

1. **アーキテクチャの不一致**
   - v10: s6-overlay (PID 1) → supervisord/process-compose
   - 実装: supervisord (PID 1)
   - 問題: supervisord再起動 = コンテナ停止のリスク

2. **ディレクトリ構造の不一致**
   - v10: `workloads/supervisord/project.conf` + `.devcontainer/supervisord/seed.conf`
   - 実装: `.devcontainer/supervisord/supervisord.conf` のみ
   - 問題: 2層構造とフォールバック機構が未実装

3. **s6-overlay未実装**
   - v10: `.devcontainer/s6-rc.d/` にサービス定義
   - 実装: s6-rc.d/ ディレクトリなし
   - 問題: PID 1保護機構なし

4. **ディレクトリ構成設計ドキュメントの不整合**
   - 14_詳細設計_ディレクトリ構成.v10.mdに `workloads/` が記載されていない
   - v10設計との一貫性がない

---

## ２．原因

1. **ドキュメント先行で実装が後回し**
   - v10設計は完成したが、実装PRには含まれなかった
   - PRはドキュメント追加のみで終わった

2. **段階的実装の計画不足**
   - v10設計全体を一度に実装しようとした
   - Phase分けが不十分

3. **ディレクトリ構成設計との連携不足**
   - プロセス管理設計と全体ディレクトリ構成の整合性確認が漏れた

---

## ３．目的（あるべき状態）

1. **v10設計の完全実装**
   - s6-overlay as PID 1
   - supervisord + process-compose 並行運用
   - `workloads/` ディレクトリ構造
   - 2層構造（seed + project）
   - フォールバック機構

2. **ディレクトリ構成設計との一貫性**
   - 14_詳細設計_ディレクトリ構成.v11.md に `workloads/` を反映
   - プロセス管理設計と全体設計の整合性確保

3. **段階的かつ安全な実装**
   - Phase分けして段階的に実装
   - 各Phaseで動作確認
   - リスクを最小化

---

## ４．実装計画

### Phase 0: ディレクトリ構成設計の更新（最優先）

**目的**: プロセス管理設計と全体ディレクトリ構成の一貫性を確保

#### タスク

1. **14_詳細設計_ディレクトリ構成.v10.mdの確認**
   - 現在の記載内容を確認
   - `workloads/` が含まれているか確認
   - プロセス管理関連の記述を確認

2. **14_詳細設計_ディレクトリ構成.v11.md作成**
   - `workloads/` ディレクトリを追加
   - プロセス管理設計（v10）との整合性を確保
   - `.devcontainer/s6-rc.d/` の追加
   - 2層構造（seed + project）の記述

3. **変更内容**
   ```
   ${project}-dev-hub/
   ├── .devcontainer/
   │   ├── s6-rc.d/                    # ★追加: s6-overlayサービス定義
   │   ├── supervisord/
   │   │   └── seed.conf               # ★変更: supervisord.conf → seed.conf
   │   ├── process-compose/
   │   │   └── seed.yaml               # ★変更: process-compose.yaml → seed.yaml
   │   └── ...
   ├── workloads/                      # ★追加: 実運用設定
   │   ├── supervisord/
   │   │   ├── project.conf
   │   │   └── README.md
   │   └── process-compose/
   │       ├── project.yaml
   │       └── README.md
   ├── foundations/
   ├── initiatives/
   └── ...
   ```

#### 検証

- ✅ v10プロセス管理設計と14_詳細設計_ディレクトリ構成.v11の整合性
- ✅ 既存の設計思想（Monolithic DevContainer）との整合性

#### 成果物

- `initiatives/20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v11.md`

---

### Phase 1: s6-overlay導入（PID 1変更）

**目的**: PID 1をsupervisordからs6-overlayに変更し、プロセス管理の堅牢性を確保

#### タスク

1. **Dockerfile修正**
   - s6-overlayインストール
   ```dockerfile
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
   ```

   - ENTRYPOINTを `/init` に変更
   ```dockerfile
   ENTRYPOINT ["/init"]
   ```

   - CMDをs6-overlay管理下に変更（後でs6-rc.d/で制御）

2. **s6-rc.d/ サービス定義作成**

   **ディレクトリ構造**:
   ```
   .devcontainer/s6-rc.d/
   ├── user/contents.d/
   │   ├── docker-entrypoint
   │   ├── supervisord
   │   └── process-compose
   ├── docker-entrypoint/
   │   ├── type
   │   ├── up
   │   └── dependencies.d/base
   ├── supervisord/
   │   ├── type
   │   ├── run
   │   └── dependencies.d/docker-entrypoint
   └── process-compose/
       ├── type
       ├── run
       └── dependencies.d/docker-entrypoint
   ```

   **ファイル内容**:

   `.devcontainer/s6-rc.d/user/contents.d/docker-entrypoint`:
   ```
   docker-entrypoint
   ```

   `.devcontainer/s6-rc.d/user/contents.d/supervisord`:
   ```
   supervisord
   ```

   `.devcontainer/s6-rc.d/user/contents.d/process-compose`:
   ```
   process-compose
   ```

   `.devcontainer/s6-rc.d/docker-entrypoint/type`:
   ```
   oneshot
   ```

   `.devcontainer/s6-rc.d/docker-entrypoint/up`:
   ```bash
   #!/command/execlineb -P
   /usr/local/bin/docker-entrypoint.sh
   ```

   `.devcontainer/s6-rc.d/docker-entrypoint/dependencies.d/base`:
   （空ファイル）

   `.devcontainer/s6-rc.d/supervisord/type`:
   ```
   longrun
   ```

   `.devcontainer/s6-rc.d/supervisord/run`:
   ```bash
   #!/command/with-contenv bash
   exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
   ```

   `.devcontainer/s6-rc.d/supervisord/dependencies.d/docker-entrypoint`:
   （空ファイル）

   `.devcontainer/s6-rc.d/process-compose/type`:
   ```
   longrun
   ```

   `.devcontainer/s6-rc.d/process-compose/run`:
   ```bash
   #!/command/with-contenv bash
   exec /usr/local/bin/process-compose -f /etc/process-compose/process-compose.yaml
   ```

   `.devcontainer/s6-rc.d/process-compose/dependencies.d/docker-entrypoint`:
   （空ファイル）

3. **Dockerfileにs6-rc.d/コピー追加**
   ```dockerfile
   COPY .devcontainer/s6-rc.d/ /etc/s6-overlay/s6-rc.d/
   ```

#### 検証

- ✅ s6-overlayがPID 1として起動するか
- ✅ supervisordがs6-overlay管理下で起動するか
- ✅ docker-entrypointがoneshot serviceとして実行されるか

#### リスク

- **s6-overlay設定ミスによるコンテナ起動失敗**
  - 対策: DEBUG_MODE=true で bash起動して調査可能

#### 影響範囲

- Dockerfile
- .devcontainer/s6-rc.d/（新規）

---

### Phase 2: 2層構造実装（seed + project）

**目的**: ビルド時検証用seed設定と実運用project設定を分離

#### タスク

1. **seed設定作成**

   `.devcontainer/supervisord/supervisord.conf` → `seed.conf` にリネーム

   内容を最小限に簡素化（code-serverのみ）:
   ```ini
   # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   # Supervisord シード設定（ダミー・ビルド用）
   # 実際の設定は workloads/supervisord/project.conf を編集してください
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

   `.devcontainer/process-compose/process-compose.yaml` → `seed.yaml` にリネーム

   内容を最小限に簡素化:
   ```yaml
   # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   # Process-Compose シード設定（ダミー・ビルド用）
   # 実際の設定は workloads/process-compose/project.yaml を編集してください
   # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   version: "0.5"

   log_location: /tmp/process-compose-${USER}.log
   log_level: info

   processes:
     # 最小限の設定（プレースホルダー）
     placeholder:
       command: "echo 'process-compose is ready. Edit workloads/process-compose/project.yaml to add processes.'"
       working_dir: "/tmp"
       availability:
         restart: "no"
   ```

2. **workloads/ ディレクトリ作成**

   ```bash
   mkdir -p workloads/supervisord
   mkdir -p workloads/process-compose
   ```

3. **project.conf/project.yaml作成**

   `workloads/supervisord/project.conf`:
   - 現在の `.devcontainer/supervisord/supervisord.conf` をベースに作成
   - difitなどの追加プロセスを含む実運用設定

   `workloads/process-compose/project.yaml`:
   - 実験的プロセス用の設定
   - 初期状態はプレースホルダー

4. **README.md作成**

   `workloads/supervisord/README.md`:
   - project.conf編集ガイド
   - 設定変更後の反映方法
   - process-composeとの使い分け

   `workloads/process-compose/README.md`:
   - project.yaml編集ガイド
   - 設定変更後の反映方法
   - supervisordとの使い分け

5. **Dockerfile修正**

   seed設定のコピー:
   ```dockerfile
   # シード設定をコピー（フォールバック用）
   COPY .devcontainer/supervisord/seed.conf /etc/supervisor/seed.conf

   # ★★★ ビルド時検証: シード設定のみ ★★★
   RUN echo "🔍 Validating seed supervisord configuration..." && \
       supervisord -c /etc/supervisor/seed.conf -t && \
       echo "✅ Seed supervisord configuration is valid"
   ```

   ```dockerfile
   # シード設定をコピー（フォールバック用）
   RUN mkdir -p /etc/process-compose
   COPY .devcontainer/process-compose/seed.yaml /etc/process-compose/seed.yaml

   # ★★★ ビルド時検証: シード設定のみ ★★★
   RUN echo "🔍 Validating seed process-compose configuration..." && \
       process-compose -f /etc/process-compose/seed.yaml --help > /dev/null 2>&1 && \
       echo "✅ Seed process-compose configuration is valid"
   ```

6. **.gitignore更新**

   `workloads/` を Git管理対象に含める（除外しない）

#### 検証

- ✅ ビルドが成功するか（seed設定で検証）
- ✅ workloads/ ディレクトリが作成されているか
- ✅ project.conf/project.yamlが適切な内容か

#### 影響範囲

- Dockerfile
- .devcontainer/supervisord/supervisord.conf → seed.conf（リネーム）
- .devcontainer/process-compose/process-compose.yaml → seed.yaml（リネーム）
- workloads/（新規）
- .gitignore

---

### Phase 3: プロセス管理設定のクリーンアップ

**目的**: 現状の調査で判明したプロセス管理設定の重複や不整合を解消し、設計の意図を明確にする。

#### タスク

1.  **`supervisord.conf` から `process-compose` の定義を削除**
    *   **理由**: `process-compose` は `s6-overlay` によって直接管理されており、`supervisord` からの二重管理は不要なため。
    *   **対象ファイル**: `workloads/supervisord/project.conf`
    *   **変更内容**: `[program:process-compose]` のセクション全体を削除する。

2.  **`difit` の管理を `process-compose` に一本化**
    *   **理由**: `difit` のような開発ツールは、TUIを持つ `process-compose` で管理する方が、ログ確認や再起動といった操作が容易であるため。
    *   **対象ファイル**: `workloads/supervisord/project.conf`
    *   **変更内容**: `[program:difit]` のセクション全体を削除する。`workloads/process-compose/project.yaml` 側の定義は現状のまま活かす。

#### 検証

*   ✅ `supervisorctl status` の結果に `process-compose` と `difit` が表示されないこと。
*   ✅ `process-compose` のTUIで `difit` が管理対象として表示され、正常に起動・停止できること。
*   ✅ `s6-overlay` によって `supervisord` と `process-compose` が引き続き並行して起動していること。

#### 影響範囲

*   `workloads/supervisord/project.conf`

---

### Phase 4: フォールバック機構実装

**目的**: project設定失敗時にseed設定へ自動フォールバック

#### タスク

1. **docker-entrypoint.sh Phase 4修正（supervisord）**

   現在:
   ```bash
   SUPERVISORD_CONF_SOURCE="/home/${UNAME}/${REPO_NAME}/.devcontainer/supervisord/supervisord.conf"
   SUPERVISORD_CONF_TARGET="/etc/supervisor/supervisord.conf"
   ```

   修正後:
   ```bash
   PROJECT_CONF="/home/${UNAME}/${REPO_NAME}/workloads/supervisord/project.conf"
   SEED_CONF="/etc/supervisor/seed.conf"
   TARGET_CONF="/etc/supervisor/supervisord.conf"

   if [ -f "${PROJECT_CONF}" ]; then
       echo "  ✅ Found: ${PROJECT_CONF}"

       sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"

       if supervisord -c "${TARGET_CONF}" -t 2>&1; then
           echo "  ✅ project.conf is valid"
       else
           echo ""
           echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
           echo "⚠️   WARNING: SUPERVISORD FALLBACK MODE"
           echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
           echo ""
           echo "workloads/supervisord/project.conf validation failed."
           echo "Using seed config (code-server only)."
           echo ""
           echo "To fix and reload:"
           echo "  1. Fix: workloads/supervisord/project.conf"
           echo "  2. Restart: s6-svc -t /run/service/supervisord"
           echo ""
           echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
           echo ""

           sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
       fi
   else
       echo ""
       echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
       echo "⚠️   WARNING: SUPERVISORD FALLBACK MODE"
       echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
       echo ""
       echo "workloads/supervisord/project.conf not found."
       echo "Using seed config (code-server only)."
       echo ""
       echo "To create and load:"
       echo "  1. Create: workloads/supervisord/project.conf"
       echo "  2. Restart: s6-svc -t /run/service/supervisord"
       echo ""
       echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
       echo ""

       sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
   fi

   echo "  Using config: ${TARGET_CONF}"
   ```

2. **docker-entrypoint.sh Phase 5修正（process-compose）**

   現在:
   ```bash
   PROCESS_COMPOSE_YAML_SOURCE="/home/${UNAME}/${REPO_NAME}/.devcontainer/process-compose/process-compose.yaml"
   ```

   修正後:
   ```bash
   PROJECT_YAML="/home/${UNAME}/${REPO_NAME}/workloads/process-compose/project.yaml"
   SEED_YAML="/etc/process-compose/seed.yaml"
   TARGET_YAML="/etc/process-compose/process-compose.yaml"

   if [ -f "${PROJECT_YAML}" ]; then
       echo "  ✅ Found: ${PROJECT_YAML}"

       sudo mkdir -p /etc/process-compose
       sudo ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"

       # YAML構文チェック（簡易）
       if grep -q "^version:" "${PROJECT_YAML}" && grep -q "^processes:" "${PROJECT_YAML}"; then
           echo "  ✅ project.yaml appears valid"
       else
           echo ""
           echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
           echo "⚠️   WARNING: PROCESS-COMPOSE FALLBACK MODE"
           echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
           echo ""
           echo "workloads/process-compose/project.yaml validation failed."
           echo "Using seed config (minimal setup)."
           echo ""
           echo "To fix and reload:"
           echo "  1. Fix: workloads/process-compose/project.yaml"
           echo "  2. Restart: s6-svc -t /run/service/process-compose"
           echo ""
           echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
           echo ""

           sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
       fi
   else
       echo "  ⚠️  workloads/process-compose/project.yaml not found"
       echo "  Using seed config (minimal setup)"

       sudo mkdir -p /etc/process-compose
       sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
   fi

   echo "  Using config: ${TARGET_YAML}"
   ```

#### 検証

- ✅ project.confが存在する場合、それが使われるか
- ✅ project.confが存在しない場合、seed.confへフォールバックするか
- ✅ project.confが無効な場合、seed.confへフォールバックするか
- ✅ 警告メッセージが明確に表示されるか

#### 影響範囲

- docker-entrypoint.sh

---

### Phase 5: docker-compose.yml調整

**目的**: s6-overlayの動作に必要な設定を追加

#### タスク

1. **tmpfs設定追加**

   ```yaml
   tmpfs:
     - /run
     - /run/lock
     - /tmp
   ```

2. **cgroup設定追加（必要に応じて）**

   ```yaml
   cgroup: host
   ```

   または特権モード（最終手段）:
   ```yaml
   # privileged: true
   ```

3. **ヘルスチェック修正**

   現在:
   ```yaml
   healthcheck:
     test: |
       if [ "$DEBUG_MODE" = "true" ]; then
         exit 0
       else
         supervisorctl status code-server | grep -q RUNNING || exit 1
       fi
   ```

   修正不要（supervisorctlはs6-overlay経由でも動作する）

#### 検証

- ✅ s6-overlayが正常に起動するか
- ✅ tmpfsが適切にマウントされているか
- ✅ ヘルスチェックが機能するか

#### 影響範囲

- docker-compose.yml

---

### Phase 6: ドキュメント整備

**目的**: 実装結果を記録し、運用ガイドを提供

#### タスク

1. **workloads/README.md作成**

   - `workloads/supervisord/README.md`: project.conf編集ガイド
   - `workloads/process-compose/README.md`: project.yaml編集ガイド

2. **v10実装完了記録**

   - `25_0_process_management_solution.v10.md` に実装完了を追記

3. **ADR作成（必要に応じて）**

   - `foundations/adr/004_workloads_directory_naming.md`

#### 成果物

- workloads/supervisord/README.md
- workloads/process-compose/README.md
- 更新された設計ドキュメント

---

## ５．実装順序と依存関係

```
Phase 0 (ディレクトリ構成設計更新) ★最優先★
    ↓ 完了後
Phase 1 (s6-overlay導入)
    ↓ 依存
Phase 2 (2層構造)
    ↓ 依存
Phase 3 (クリーンアップ)
    ↓ 依存
Phase 4 (フォールバック)
    ↓ 依存
Phase 5 (docker-compose調整)
    ↓ 依存
Phase 6 (ドキュメント整備)
```

**重要**: 各フェーズを順番に実行し、一貫性を確保する。

---

## ６．リスクと対策

### リスク1: s6-overlay導入によるコンテナ起動失敗

**対策**:
- DEBUG_MODE=true でbashシェル起動可能にする
- s6-overlay最小限の設定から開始
- 段階的に機能追加

### リスク2: 既存のsupervisord設定との互換性

**対策**:
- 既存のsupervisord.confをproject.confとして保存
- seed.confは最小限（code-serverのみ）
- フォールバック機構で安全性確保

### リスク3: workloads/ ディレクトリのバインドマウント

**対策**:
- docker-compose.ymlでバインドマウント確認（既存のバインドマウントで自動的に含まれる）
- 存在しない場合のフォールバック機構（Phase 4で実装）

### リスク4: s6-overlay設定ミス

**対策**:
- v10設計ドキュメントの実装例を参照
- 最小限の設定から開始
- 各Phaseで動作確認

---

## ７．推定工数

| Phase | 内容 | 工数 |
|-------|------|------|
| Phase 0 | ディレクトリ構成設計更新 | 1-2時間 |
| Phase 1 | s6-overlay導入 | 2-3時間 |
| Phase 2 | 2層構造実装 | 1-2時間 |
| Phase 3 | 設定クリーンアップ | 30分-1時間 |
| Phase 4 | フォールバック実装 | 1-2時間 |
| Phase 5 | docker-compose調整 | 30分-1時間 |
| Phase 6 | ドキュメント整備 | 1-2時間 |
| **合計** | | **8-11時間** |

---

## ８．成功基準

### 必須条件

1. ✅ s6-overlayがPID 1として起動
2. ✅ supervisordがs6-overlay管理下で起動
3. ✅ process-composeがs6-overlay管理下で起動（オプション）
4. ✅ workloads/supervisord/project.confが使用される
5. ✅ project.conf失敗時にseed.confへフォールバック
6. ✅ 14_詳細設計_ディレクトリ構成.v11とv10プロセス管理設計の整合性

### 望ましい条件

1. ✅ supervisord Web UI (port 9001) でプロセス確認可能
2. ✅ process-compose TUI でプロセス確認可能
3. ✅ s6-svc コマンドでサービス再起動可能
4. ✅ ドキュメントが整備されている

---

## ９．次のアクション

1. **Phase 0実行**: 14_詳細設計_ディレクトリ構成.v11.md作成
2. **Phase 0レビュー**: v10プロセス管理設計との整合性確認
3. **Phase 1-6を順次実行**: 各Phase完了後に動作確認
4. **最終確認**: v10設計との完全一致を確認
5. **PR作成**: 実装完了後にPull Request作成

---

## １０．参考資料

- [25_0_process_management_solution.v10.md](25_0_process_management_solution.v10.md) - v10設計
- [25_0_process_management_solution.v9.md](25_0_process_management_solution.v9.md) - v9設計
- [14_詳細設計_ディレクトリ構成.v10.md](14_詳細設計_ディレクトリ構成.v10.md) - 現在のディレクトリ構成設計
- [s6-overlay Documentation](https://github.com/just-containers/s6-overlay)

---

## １１．変更履歴

### v1 (2026-01-03)
- 初版作成
- v10設計と現在実装の乖離分析
- Phase 0-5の実装計画策定
- Phase 0をディレクトリ構成設計更新に設定（最優先）
- (v2) Phase 6としてプロセス管理設定のクリーンアップを追加
- (v3) Phase 6をPhase 3に移動し、後続フェーズを再ナンバリング
