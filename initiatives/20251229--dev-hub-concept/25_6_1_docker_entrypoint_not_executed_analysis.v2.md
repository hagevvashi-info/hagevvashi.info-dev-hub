# docker-entrypoint.sh 未実行問題の分析と戦略（v2 - Geminiフィードバック反映版）

**作成日**: 2026-01-04
**バージョン**: v2
**前バージョン**: `25_6_1_docker_entrypoint_not_executed_analysis.md` (存在しない場合は初版)
**レビュー**: `25_6_2_docker_entrypoint_not_executed_analysis_review_by_gemini.md` のフィードバックを反映

---

## 0. Geminiレビューからの学び

### 0.1 v1の構造的弱点の認識

Geminiからの批判的レビューにより、v1には以下の構造的弱点があることが明確になりました:

1. **実装トラッカーが機能不全を起こしていた根本原因への踏み込み不足**
2. **s6-overlay の基礎知識習得プロセスとデバッグ作法の欠如**
3. **「実行されていない」という断定に対する証拠の不十分さ**
4. **再発防止策が手作業レベルに留まり、自動化・テンプレート化への言及不足**

### 0.2 各ツッコミの妥当性判断

| ツッコミ | 妥当性 | 理由 |
|---------|--------|------|
| ツッコミ1: 実装トラッカーの機能不全 | **極めて高い** | Phase 1が「完了」とマークされていたが実装は不完全。トラッカー更新プロセスに「完了」の定義が曖昧であり、実装との乖離を検出する仕組みが不在 |
| ツッコミ2: s6-overlay知識とデバッグ作法 | **高い** | `oneshot` vs `longrun`、`up` vs `run` の理解不足。`s6-rc` コマンドやログ確認という基本的デバッグステップを踏んでいない |
| ツッコミ3: 問題断定の証拠不十分 | **非常に高い** | DevContainer出力ログのみで判断。`s6-rc -d list/status` やs6-overlayログ、デバッグecho文による実行痕跡確認を実施していない |
| ツッコミ4: 再発防止の甘さ | **高い** | 最小修正のみ提案。サービス定義の手動作成ミス再発可能性、`user/contents.d/` 登録忘れ防止策、ビルド時自動検証への言及不足 |

### 0.3 v2での改善方針

本ドキュメント（v2）では、以下の改善を実施します:

1. **証拠ベースの問題分析**: `s6-rc` コマンドによる実証的な状態確認を追加
2. **実装トラッカー機能不全の根本原因分析**: プロセス改善への示唆を明記
3. **s6-overlay 知識習得とデバッグ作法の標準化**: 最小動作検証（PoC）プロセスの導入
4. **自動化・テンプレート化による再発防止**: ビルド時検証スクリプトとサービス定義テンプレートの提案

---

## 1. 問題の発見経緯

### 1.1 初期観察

DevContainer起動後、以下の状態が観察されました:

```bash
$ ls -la /etc/process-compose/
lrwxrwxrwx 1 root root ... process-compose.yaml -> /etc/process-compose/
```

**予想**: `/etc/process-compose/process-compose.yaml` が `workloads/process-compose/project.yaml` へのシンボリックリンクとなるべき
**実際**: シンボリックリンク先が自分自身を指す無限ループ状態

### 1.2 設計との照合

[25_0_process_management_solution.v10.md](25_0_process_management_solution.v10.md) によれば、docker-entrypoint.shは以下を実行すべき:

- **Phase 4**: supervisord設定の検証とシンボリックリンク作成
- **Phase 5**: process-compose設定の検証とシンボリックリンク作成

この状態は、`docker-entrypoint.sh` が**正しく動作していない可能性**を示唆します。

---

## 2. 証拠ベースの原因分析（Gemini指摘への対応）

### 2.1 証拠収集の必要性

**Geminiの指摘**: v1では「実行されていない」という断定には、以下の証拠が不足している。

実施すべき確認項目:
1. `s6-rc -d list` でサービス登録状況の確認
2. `s6-rc -d status docker-entrypoint` でサービス状態の確認
3. `/run/s6/etc/s6-svscan/default/s6-log/current` など s6-overlay ログの確認
4. `docker-entrypoint.sh` へのデバッグecho文挿入による実行痕跡確認

### 2.2 s6-rc.d サービス定義の詳細調査

実際のファイル構成を確認した結果:

```bash
.devcontainer/s6-rc.d/docker-entrypoint/
├── type          # 内容: "longrun"
├── run           # 空ファイル
└── dependencies.d/
    └── base
```

**発見した問題点**:

| 項目 | 実際の状態 | v10設計での期待値 | 影響 |
|------|-----------|----------------|------|
| `type` ファイル | `longrun` | `oneshot` | サービスが継続実行プロセスとして扱われる |
| 実行スクリプト | 空の `run` ファイル | `up` スクリプト（execlineb形式） | 実行すべきコマンドが定義されていない |
| `user/contents.d/` 登録 | 未登録 | `docker-entrypoint` エントリが必要 | s6-rcがサービスを認識しない |

### 2.3 s6-overlay における oneshot と longrun の違い

**Geminiの指摘**: `oneshot` と `longrun` の基本的な違いが理解されていなかった可能性。

| サービスタイプ | 用途 | 実行形態 | スクリプトファイル |
|--------------|------|---------|-----------------|
| `oneshot` | 初期化処理、設定準備 | 一度だけ実行され完了 | `up` |
| `longrun` | 常駐デーモンプロセス | PIDを保持し続ける | `run` |

`docker-entrypoint.sh` は設定ファイルのシンボリックリンク作成という**初期化処理**であり、`oneshot` が適切です。

### 2.4 実装トラッカーとの矛盾分析

[25_4_2_v10_implementation_tracker.md](25_4_2_v10_implementation_tracker.md) では:

```markdown
### Phase 1: s6-overlay導入（PID 1変更）
- [x] Dockerfileにs6-overlayをインストールし、ENTRYPOINTを`/init`に変更
- [x] `.devcontainer/s6-rc.d/` にサービス定義を作成
```

**問題**: Phase 1は「完了」とマークされているが、実際のサービス定義は不完全。

**根本原因の仮説**（Gemini指摘への応答）:
1. **「完了」の定義が曖昧**: 「ファイルが存在すれば完了」という判断基準だった可能性
2. **実装との乖離検出プロセスの不在**: トラッカー更新時に実際の動作確認や設計書との照合をしていない
3. **確認者の役割が不明確**: 誰が、いつ、どのように実装を検証するかが定義されていない

---

## 3. 根本原因のまとめ

### 3.1 直接的原因

1. **サービス定義の設計乖離**: `type`, `up`/`run`, `user/contents.d/` が v10 設計と異なる
2. **s6-overlay の基礎知識不足**: `oneshot` と `longrun` の違い、`up` と `run` の使い分けが理解されていなかった

### 3.2 構造的原因（Geminiフィードバックから）

1. **実装トラッカーの機能不全**:
   - タスク完了基準が曖昧（ファイル存在 vs 設計通りの実装）
   - 実装と設計の乖離を検出する仕組みの不在
   - 確認者の役割と責任が不明確

2. **デバッグ作法の欠如**:
   - s6-overlay 導入時の最小動作検証（PoC）を実施していない
   - `s6-rc` コマンドやログ確認という基本的デバッグ手法を踏んでいない

3. **再発防止策の不足**:
   - サービス定義の手動作成によるミスの可能性
   - ビルド時の自動検証スクリプトの不在

---

## 4. 解決策の比較検討

### 解決策1: 最小修正（s6-rc.d サービス定義の修正のみ）

**概要**: `docker-entrypoint` サービス定義を v10 設計に合わせて修正。

**変更内容**:
```bash
# .devcontainer/s6-rc.d/docker-entrypoint/type
oneshot

# .devcontainer/s6-rc.d/docker-entrypoint/up（新規作成、chmod +x）
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh

# .devcontainer/s6-rc.d/docker-entrypoint/run（削除）
# 削除

# .devcontainer/s6-rc.d/user/contents.d/docker-entrypoint（新規作成）
# 空ファイルとして作成
```

**利点**:
- 実装が単純で、既存構造への影響が最小
- v10 設計への準拠が明確
- 即座に問題を解決できる

**欠点**:
- 手作業による修正のため、同様のミスが再発する可能性
- 実装トラッカーのプロセス改善には言及していない
- s6-overlay の知識習得プロセスがない

---

### 解決策2: 最小修正 + 実装トラッカープロセス改善 ★推奨★

**概要**: 解決策1に加えて、実装トラッカーの運用プロセスを改善。

**追加要素**:
1. **タスク完了基準の明確化**:
   ```markdown
   ### Phase 1: s6-overlay導入（PID 1変更）
   - [x] `.devcontainer/s6-rc.d/` にサービス定義を作成
     - 完了基準:
       - `s6-rc -d list` でサービス名が認識される
       - `s6-rc -d status <service>` で正常状態である
       - 設計書のサービス定義仕様と一致している
   ```

2. **確認者の明記**:
   - トラッカー更新時に「確認者: <名前または自動チェック>」を記載
   - 自動チェックスクリプトによる検証を推奨

3. **トラッカー更新ガイドラインの策定**:
   - 完了基準: ファイル存在 + 内容の設計適合性 + 動作確認
   - 確認手順: s6-overlay の場合は `s6-rc` コマンドによる検証
   - 確認者の記載を義務化

**利点**:
- 実装トラッカーが実装状態を正しく反映する仕組みになる
- 設計と実装の乖離を早期に検出できる
- 今後の開発プロセスが改善される

**欠点**:
- プロセス改善の浸透に時間がかかる
- ガイドライン作成とトラッカー更新の手間がかかる

---

### 解決策3: 最小修正 + s6-overlay 知識習得 + PoC プロセス導入

**概要**: 解決策1に加えて、s6-overlay の基礎知識習得と最小動作検証プロセスを導入。

**追加要素**:
1. **s6-overlay 基礎学習**:
   - 公式ドキュメント（s6-rc, s6-svscan）の再確認
   - `oneshot` と `longrun` の違い、サービスバンドルの概念を理解
   - チーム内での知識共有セッション実施

2. **最小動作検証（PoC）プロセス**:
   ```bash
   # PoC: 単純な oneshot サービスの動作確認
   .devcontainer/s6-rc.d/test-oneshot/
   ├── type          # "oneshot"
   └── up            # echo "test-oneshot executed" >> /tmp/test.log

   # PoC: 単純な longrun サービスの動作確認
   .devcontainer/s6-rc.d/test-longrun/
   ├── type          # "longrun"
   └── run           # while true; do sleep 10; done
   ```
   - 新技術導入時は、まずシンプルな動作確認を実施
   - 期待通りに動作することを確認してから本格実装

3. **デバッグ作法の標準化**:
   - サービスが動作しない場合、以下を必ず確認:
     - `s6-rc -d list` でサービス登録状況
     - `s6-rc -d status <service>` でサービス状態
     - `/run/s6/etc/s6-svscan/default/s6-log/current` でログ
     - スクリプト内にデバッグecho文を挿入

**利点**:
- s6-overlay に関する理解が深まり、同様のミスを防げる
- 新技術導入時の失敗リスクを低減
- デバッグ手法が標準化され、問題解決が早くなる

**欠点**:
- 学習とPoC実施に時間が必要
- 緊急対応には向かない

---

### 解決策4: 最小修正 + 自動化・テンプレート化による再発防止

**概要**: 解決策1に加えて、サービス定義の自動生成とビルド時検証を導入。

**追加要素**:
1. **サービス定義テンプレートスクリプト**:
   ```bash
   # scripts/new-s6-service.sh
   #!/usr/bin/env bash
   SERVICE_NAME=$1
   SERVICE_TYPE=$2  # oneshot or longrun

   mkdir -p .devcontainer/s6-rc.d/$SERVICE_NAME/dependencies.d
   echo "$SERVICE_TYPE" > .devcontainer/s6-rc.d/$SERVICE_NAME/type

   if [ "$SERVICE_TYPE" = "oneshot" ]; then
       cat > .devcontainer/s6-rc.d/$SERVICE_NAME/up <<'EOF'
   #!/command/execlineb -P
   # TODO: Add your command here
   EOF
       chmod +x .devcontainer/s6-rc.d/$SERVICE_NAME/up
   else
       cat > .devcontainer/s6-rc.d/$SERVICE_NAME/run <<'EOF'
   #!/usr/bin/env bash
   set -euo pipefail
   # TODO: Add your long-running command here
   exec sleep infinity
   EOF
       chmod +x .devcontainer/s6-rc.d/$SERVICE_NAME/run
   fi

   touch .devcontainer/s6-rc.d/user/contents.d/$SERVICE_NAME
   ```

2. **ビルド時検証スクリプト**:
   ```bash
   # scripts/validate-s6-services.sh
   #!/usr/bin/env bash
   set -euo pipefail

   SERVICES_DIR=".devcontainer/s6-rc.d"
   ERRORS=0

   for service in $(ls -d $SERVICES_DIR/*/ | xargs -n1 basename); do
       if [ "$service" = "user" ] || [ "$service" = "base" ]; then
           continue
       fi

       # Check type file exists
       if [ ! -f "$SERVICES_DIR/$service/type" ]; then
           echo "ERROR: $service missing type file"
           ERRORS=$((ERRORS + 1))
       else
           TYPE=$(cat "$SERVICES_DIR/$service/type")

           # Check appropriate script exists
           if [ "$TYPE" = "oneshot" ]; then
               if [ ! -x "$SERVICES_DIR/$service/up" ]; then
                   echo "ERROR: $service is oneshot but missing executable up script"
                   ERRORS=$((ERRORS + 1))
               fi
           elif [ "$TYPE" = "longrun" ]; then
               if [ ! -x "$SERVICES_DIR/$service/run" ]; then
                   echo "ERROR: $service is longrun but missing executable run script"
                   ERRORS=$((ERRORS + 1))
               fi
           fi
       fi

       # Check user registration
       if [ ! -f "$SERVICES_DIR/user/contents.d/$service" ]; then
           echo "WARNING: $service not registered in user/contents.d/"
           ERRORS=$((ERRORS + 1))
       fi
   done

   if [ $ERRORS -gt 0 ]; then
       echo "Found $ERRORS errors in s6-rc service definitions"
       exit 1
   fi

   echo "All s6-rc service definitions are valid"
   ```

3. **Dockerfile への統合**:
   ```dockerfile
   # ビルド時にサービス定義を検証
   COPY scripts/validate-s6-services.sh /tmp/
   RUN /tmp/validate-s6-services.sh
   ```

**利点**:
- サービス定義の手作業ミスを自動的に防止
- ビルド時にエラーを早期検出（Fail Fast）
- 新規サービス追加の学習コストが下がる

**欠点**:
- スクリプト開発と保守のコストがかかる
- テンプレートが実際のニーズに合わない場合、カスタマイズが必要

---

### 解決策5: 統合アプローチ（解決策2 + 3 + 4）

**概要**: 実装トラッカープロセス改善、s6-overlay知識習得、自動化・テンプレート化をすべて実施。

**利点**:
- 最も堅牢で再発防止効果が高い
- Monolithic DevContainer の長期的な安定性向上

**欠点**:
- 実装コストと時間が最大
- 短期的には過剰投資の可能性

---

## 5. 推奨アプローチ

### 5.1 推奨: 解決策2（最小修正 + 実装トラッカープロセス改善）

**理由**:
1. **即時性と持続性のバランス**: 問題を即座に解決しつつ、プロセス改善で再発を防ぐ
2. **コスト対効果**: 自動化（解決策4）ほどの開発コストをかけずに、実装トラッカーの信頼性を向上
3. **Geminiの指摘への対応**: ツッコミ1（実装トラッカー機能不全）に直接対応
4. **段階的改善の起点**: 将来的に解決策3や4を追加実施する余地を残す

**実装の流れ**:
1. サービス定義の修正（解決策1の内容）
2. デバッグログの追加と検証（証拠ベースの確認）
3. 実装トラッカーへのガイドライン追加
4. 既存トラッカー（25_4_2）の Phase 1 を完了基準付きで更新

---

## 6. 実装計画（解決策2ベース）

### 6.1 サービス定義の修正

#### Step 1: ファイル操作

```bash
# 1. type ファイルを修正
echo "oneshot" > .devcontainer/s6-rc.d/docker-entrypoint/type

# 2. run ファイルを削除
rm .devcontainer/s6-rc.d/docker-entrypoint/run

# 3. up スクリプトを作成
cat > .devcontainer/s6-rc.d/docker-entrypoint/up <<'EOF'
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh
EOF

# 4. up スクリプトに実行権限を付与
chmod +x .devcontainer/s6-rc.d/docker-entrypoint/up

# 5. user/contents.d/ に登録
touch .devcontainer/s6-rc.d/user/contents.d/docker-entrypoint
```

#### Step 2: デバッグログの追加（Gemini指摘への対応）

`docker-entrypoint.sh` の冒頭にデバッグログを追加:

```bash
#!/usr/bin/env bash
echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2
set -euo pipefail
```

#### Step 3: git commit

```bash
git add .devcontainer/s6-rc.d/docker-entrypoint/ .devcontainer/docker-entrypoint.sh
git commit -m "fix: correct docker-entrypoint s6-rc service definition to match v10 design

- Change service type from 'longrun' to 'oneshot'
- Remove empty 'run' file and create 'up' script with execlineb
- Register service in user/contents.d/
- Add debug log to docker-entrypoint.sh for execution tracking

Resolves issue identified in 25_6_1_docker_entrypoint_not_executed_analysis.v2.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### 6.2 DevContainer 再ビルドと検証（証拠ベースの確認）

```bash
# 1. DevContainer を再ビルド
# VS Code: "Dev Containers: Rebuild Container"

# 2. コンテナ内で s6-rc コマンドで検証（Gemini指摘への対応）
s6-rc -d list | grep docker-entrypoint
# 期待: docker-entrypoint が表示される

s6-rc -d status docker-entrypoint
# 期待: up と表示される

# 3. シンボリックリンクの確認
ls -la /etc/process-compose/process-compose.yaml
# 期待: -> /workspace/workloads/process-compose/project.yaml

ls -la /etc/supervisor/supervisord.conf
# 期待: -> /workspace/workloads/supervisord/project.conf

# 4. docker-entrypoint.sh のログ確認
# DevContainer の出力ログに "docker-entrypoint.sh STARTED" が表示されることを確認
```

### 6.3 実装トラッカープロセス改善

#### Step 1: トラッカー更新ガイドラインの追加

`25_4_2_v10_implementation_tracker.md` の末尾に以下を追加:

```markdown
---

## トラッカー更新ガイドライン

### タスク完了の基準

各タスクを「完了」とマークする前に、以下を確認すること:

1. **ファイルの存在確認**: 設計書で指定されたファイルがすべて存在する
2. **内容の設計適合性**: ファイルの内容が設計書の仕様と一致する
3. **動作確認**: 該当機能が期待通りに動作する
4. **自動検証**: 可能であれば、自動検証スクリプトでチェックする

### s6-overlay サービス定義の完了基準（具体例）

- [ ] `.devcontainer/s6-rc.d/<service>/type` が存在し、内容が設計通り（`oneshot` or `longrun`）
- [ ] `oneshot` の場合: `up` スクリプトが存在し、実行権限がある
- [ ] `longrun` の場合: `run` スクリプトが存在し、実行権限がある
- [ ] `.devcontainer/s6-rc.d/user/contents.d/<service>` が存在する
- [ ] `s6-rc -d list` でサービス名が認識される（コンテナビルド後）
- [ ] `s6-rc -d status <service>` で正常状態である（コンテナビルド後）

### 確認者の記載

各タスク完了時には、以下のいずれかを記載:

- **確認者**: <名前>
- **自動検証**: scripts/validate-s6-services.sh
```

#### Step 2: Phase 1 の更新

`25_4_2_v10_implementation_tracker.md` の Phase 1 を以下のように更新:

```markdown
### Phase 1: s6-overlay導入（PID 1変更）
- [x] Dockerfileにs6-overlayをインストールし、ENTRYPOINTを`/init`に変更
  - 確認者: <作業者名>
- [x] `.devcontainer/s6-rc.d/` にサービス定義を作成
  - 完了基準:
    - [x] `docker-entrypoint` サービスの `type` が `oneshot`
    - [x] `up` スクリプトが存在し、実行権限がある
    - [x] `user/contents.d/docker-entrypoint` が存在
    - [x] コンテナビルド後、`s6-rc -d list | grep docker-entrypoint` が成功
    - [x] コンテナビルド後、`s6-rc -d status docker-entrypoint` が `up`
  - 確認者: <修正実施者名>
  - 修正日: 2026-01-04
  - 参照: 25_6_3_docker_entrypoint_fix_implementation_tracker.md
```

---

## 7. 成功基準

このドキュメントに基づく修正は、以下がすべて満たされたときに「成功」とします:

| 基準 | 確認方法 |
|------|---------|
| サービス定義が v10 設計に準拠 | ファイル構成と内容を確認 |
| s6-rc がサービスを認識 | `s6-rc -d list \| grep docker-entrypoint` が成功 |
| サービスが正常状態 | `s6-rc -d status docker-entrypoint` が `up` を返す |
| シンボリックリンクが正しい | `/etc/process-compose/process-compose.yaml` と `/etc/supervisor/supervisord.conf` を確認 |
| デバッグログが出力される | DevContainer ログに "docker-entrypoint.sh STARTED" が存在 |
| 実装トラッカーが更新された | `25_4_2_v10_implementation_tracker.md` にガイドラインが追加され、Phase 1 が更新された |

---

## 8. リスク管理と緩和策

### 8.1 識別されたリスク

| リスク | 影響度 | 発生確率 | 緩和策 |
|--------|--------|---------|--------|
| 修正後にコンテナが起動しない | 高 | 低 | ロールバック計画を用意、段階的適用 |
| トラッカープロセス改善が浸透しない | 中 | 中 | ドキュメント整備、チーム内レビュー実施 |
| s6-overlay の理解不足が継続 | 中 | 中 | 将来的に解決策3（学習・PoC）を実施 |

### 8.2 ロールバック手順

もし修正後にコンテナが起動しない場合:

1. **即座にロールバック**:
   ```bash
   git revert HEAD
   # VS Code: "Dev Containers: Rebuild Container"
   ```

2. **問題の再分析**:
   - s6-overlay のログを確認: `/run/s6/etc/s6-svscan/default/s6-log/current`
   - エラーメッセージを記録
   - より詳細な調査を実施

---

## 9. Geminiフィードバックへの最終応答

### 9.1 ツッコミ1への対応

**問題**: 実装トラッカーが機能不全を起こしていた。

**対応**:
- トラッカー更新ガイドラインを策定（完了基準の明確化、確認者の明記）
- Phase 1 を詳細な完了基準付きで更新
- 今後のタスクには s6-rc コマンドによる動作確認を含める

### 9.2 ツッコミ2への対応

**問題**: s6-overlay の知識レベルとデバッグ作法の欠如。

**対応**:
- 本ドキュメントで `oneshot` vs `longrun` の違いを明記
- デバッグ作法（`s6-rc -d list/status`、ログ確認）を検証手順に含める
- 将来的に解決策3（基礎学習とPoC）の実施を検討

### 9.3 ツッコミ3への対応

**問題**: 問題断定の証拠が不十分。

**対応**:
- 検証手順に `s6-rc` コマンドによる実証的な確認を含める
- デバッグログを追加し、実行痕跡を確認
- 「実行されていない」ではなく「正しく動作していない」という表現に修正

### 9.4 ツッコミ4への対応

**問題**: 再発防止策が手作業レベルに留まっている。

**対応**:
- 実装トラッカープロセス改善により、手作業ミスの検出率を向上
- 将来的に解決策4（テンプレート化、自動検証）の実施を検討
- 段階的なアプローチで、まずプロセス改善から着手

---

## 10. 次のアクション

1. **即時実施**:
   - [ ] サービス定義ファイルの修正（6.1参照）
   - [ ] デバッグログの追加
   - [ ] git commit

2. **検証実施**:
   - [ ] DevContainer 再ビルド
   - [ ] s6-rc コマンドによる検証（6.2参照）
   - [ ] シンボリックリンクの確認
   - [ ] デバッグログの確認

3. **トラッカー更新**:
   - [ ] `25_4_2_v10_implementation_tracker.md` にガイドライン追加（6.3参照）
   - [ ] Phase 1 を完了基準付きで更新

4. **将来的な検討**:
   - [ ] s6-overlay 基礎学習とPoC実施（解決策3）
   - [ ] サービス定義テンプレートと自動検証スクリプト開発（解決策4）

---

## 付録A: 参考資料

- [25_6_2_docker_entrypoint_not_executed_analysis_review_by_gemini.md](25_6_2_docker_entrypoint_not_executed_analysis_review_by_gemini.md) - Gemini レビュー
- [25_0_process_management_solution.v10.md](25_0_process_management_solution.v10.md) - v10 プロセス管理設計
- [25_4_2_v10_implementation_tracker.md](25_4_2_v10_implementation_tracker.md) - 実装トラッカー
- [s6-overlay GitHub](https://github.com/just-containers/s6-overlay)
- [s6-rc documentation](https://skarnet.org/software/s6-rc/)

---

## 付録B: v1からの主な変更点（想定）

| セクション | v1の内容（想定） | v2での改善 |
|-----------|---------------|-----------|
| 0. Geminiレビューからの学び | （なし） | **新規追加**: v1の弱点認識と改善方針を明記 |
| 2. 原因分析 | DevContainerログのみで判断 | **強化**: `s6-rc` コマンド、ログ確認、デバッグecho文による証拠収集を明記 |
| 3. 根本原因 | 直接的原因のみ | **拡張**: 構造的原因（トラッカー機能不全、デバッグ作法欠如）を追加 |
| 5. 推奨アプローチ | 解決策1を推奨（想定） | **変更**: 解決策2（最小修正+トラッカー改善）を推奨 |
| 6. 実装計画 | 技術的修正のみ | **拡張**: トラッカープロセス改善を含める |
| 9. Geminiへの応答 | （なし） | **新規追加**: 各ツッコミへの対応を明記 |

---

**このドキュメントは、Geminiの批判的フィードバックを真摯に受け止め、証拠ベースの分析とプロセス改善を含む実用的なアプローチを提示するものです。**

---

## 11. 追跡調査: supervisordフォールバック問題（2026-01-04）

v2で提案された修正を適用後、`25_6_3_docker_entrypoint_fix_implementation_tracker.md` に基づく統合検証（セクションE-2）を実施したところ、新たな問題が判明した。

### 11.1 検証で判明した事実

1.  **s6-rcサービスは登録済み**:
    ```bash
    $ /command/s6-rc -d list
    docker-entrypoint
    supervisord
    process-compose
    ...
    ```
    → `docker-entrypoint` はs6-overlayにサービスとして正しく認識されている。

2.  **`supervisorctl` コマンドが失敗**:
    ```bash
    $ supervisorctl status
    Error: .ini file does not include supervisorctl section
    ```
    → supervisordが読み込んでいる設定ファイルに `[supervisorctl]` セクションがない。

3.  **シンボリックリンクの確認**:
    ```bash
    $ ls -l /etc/supervisor/supervisord.conf
    lrwxrwxrwx 1 root root ... -> /etc/supervisor/seed.conf
    ```
    → supervisordの設定が、実運用設定 (`workloads/supervisord/project.conf`) ではなく、フォールバック用の `seed.conf` を参照している。

### 11.2 問題の再定義

当初の「`docker-entrypoint.sh` が実行されていない」という仮説は誤りであった。
より正確な問題定義は以下の通りである。

**「`docker-entrypoint.sh` は実行されているが、Phase 4のsupervisord設定検証で失敗し、`seed.conf` へのフォールバックが発生している。その結果、`[supervisorctl]` セクションが含まれていない設定が読み込まれ、`supervisorctl` コマンドが使用できなくなっている」**

### 11.3 根本原因の特定

なぜPhase 4の検証が失敗したのかを特定する必要がある。しかし、以下の理由により原因の特定が困難であった。

- `journalctl` コマンドがコンテナ内に存在しない。
- `s6-log` コマンドで `docker-entrypoint.sh`（oneshotサービス）のログを直接参照する方法が確立できていない。
- `/run/s6/` 配下を探索したが、明確なログファイルを発見できなかった。

### 11.4 次のアプローチ：デバッグ情報の強制出力

ログ追跡が困難であるため、より確実な方法として、`docker-entrypoint.sh` スクリプト自体を修正し、実行内容をすべてファイルにリダイレクトする。

#### 具体的な修正案

`.devcontainer/docker-entrypoint.sh` の冒頭（`set -euo pipefail` の直前）に以下の2行を追加する。

```bash
exec > /tmp/entrypoint.log 2>&1
set -x
```

- **`exec > /tmp/entrypoint.log 2>&1`**: スクリプト全体の標準出力と標準エラー出力を `/tmp/entrypoint.log` にリダイレクトする。
- **`set -x`**: 実行される各コマンドをトレースログとして出力する。

これにより、コンテナを再ビルド＆起動した後、`/tmp/entrypoint.log` を確認すれば、どのコマンドで失敗し、なぜフォールバックが発生したのかを確実に特定できる。

**次のアクション**: この修正を適用し、DevContainerを再ビルドしてログファイルを分析する。
