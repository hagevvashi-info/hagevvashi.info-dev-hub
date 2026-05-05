# REPO_NAME 変数名の衝突問題と改善提案

**作成日**: 2026-01-11
**ステータス**: 🔍 検討中
**優先度**: 高
**カテゴリ**: 設計改善

---

## 1. 問題の概要

現在、Monolithic DevContainer自体のリポジトリ名を表す環境変数として `REPO_NAME` を使用していますが、この変数名は以下の問題を抱えています。

### 1-1. 主要な問題点

1. **変数名が汎用的すぎる**
   - `REPO_NAME` という名前は「リポジトリ名」を表す一般的な名前
   - プロダクトコードやスクリプト内で同名の変数が使用される可能性が高い
   - シェル変数、環境変数として衝突リスクがある

2. **何のリポジトリ名か不明確**
   - Monolithic DevContainerのリポジトリ名なのか
   - プロダクトのリポジトリ名なのか
   - 作業中のプロジェクトのリポジトリ名なのか
   - 変数名から判断できない

3. **スコープの曖昧さ**
   - DevContainer固有の変数であることが明示されていない
   - 他のツールやスクリプトとの名前空間の分離ができていない

### 1-2. 具体的な衝突シナリオ

```bash
# プロダクトコード内で一般的に使われる可能性のあるパターン

# シナリオ1: プロダクトのビルドスクリプト
REPO_NAME="my-product"  # 衝突！既存のREPO_NAMEを上書き
git clone https://github.com/org/${REPO_NAME}.git

# シナリオ2: CI/CDスクリプト
export REPO_NAME=$(basename $(git remote get-url origin) .git)  # 衝突！
docker build -t ${REPO_NAME}:latest .

# シナリオ3: 複数リポジトリを扱うスクリプト
for REPO_NAME in repo1 repo2 repo3; do  # 衝突！
    cd $REPO_NAME && npm install
done
```

---

## 2. 現状の使用箇所分析

### 2-1. 使用ファイル一覧（26ファイル）

#### **実装ファイル（7ファイル）** - 変更必須

| ファイル | 行 | 用途 | 重要度 |
|---------|---|------|-------|
| `.devcontainer/docker-compose.yml` | 15, 20, 25, 43 | bind mount, working_dir, ENV | ⭐⭐⭐ |
| `.devcontainer/docker-entrypoint.sh` | 98, 100, 160, 162 | supervisord/process-compose設定パス | ⭐⭐⭐ |
| `.devcontainer/devcontainer.json.template` | 11, 13 | workspaceFolder, postCreateCommand | ⭐⭐⭐ |
| `.devcontainer/generate-env.sh` | 13, 21 | 環境変数生成 | ⭐⭐⭐ |
| `.devcontainer/setup.sh` | 37, 39, 43 | devcontainer.json生成 | ⭐⭐⭐ |
| `.devcontainer/post-create.sh` | 13, 16, 22 | リポジトリパス構築 | ⭐⭐⭐ |
| `workloads/process-compose/project.yaml` | 12 | working_dir設定 | ⭐⭐⭐ |

#### **ドキュメントファイル（19ファイル）** - 変更推奨

- `foundations/v10_environment_variables_golden_test.md` - ゴールデンテストケース
- `initiatives/20251229--dev-hub-concept/resolved/25_6_21_verification_procedure.md` - 検証手順
- `initiatives/20251229--dev-hub-concept/decisions/25_0_process_management_solution.v10.md` - v10設計書
- その他16ファイル（古いバージョン、ログ等）

### 2-2. 使用パターン分析

```bash
# パターン1: 環境変数として
export REPO_NAME=${REPO_NAME:-dev-hub}

# パターン2: dockerコンテナ内ENV
environment:
  - REPO_NAME=${REPO_NAME:-dev-hub}

# パターン3: パス構築
/home/${UNAME}/${REPO_NAME}
/home/${UNAME}/${REPO_NAME}/workloads/supervisord/project.conf

# パターン4: supervisord設定
directory=/home/%(ENV_UNAME)s/%(ENV_REPO_NAME)s

# パターン5: process-compose設定
working_dir: "/home/${UNAME}/${REPO_NAME}"
```

---

## 3. 改善提案

### 3-1. 評価フレームワーク

#### **評価項目の定義**

変数名を選定するための評価項目を以下のように定義します。

| # | 評価項目 | 説明 | 重み |
|---|---------|------|------|
| 1 | 衝突リスク | プロダクトコードや一般的なシェルスクリプトとの変数名衝突の可能性 | ⭐⭐⭐⭐⭐ (5) |
| 2 | 名前空間分離 | Monolithic DevContainer専用であることの明確さ | ⭐⭐⭐⭐ (4) |
| 3 | 可読性 | 変数名の長さと理解のしやすさ | ⭐⭐⭐ (3) |
| 4 | 拡張性 | 将来的な変数群の統一・拡張のしやすさ | ⭐⭐⭐ (3) |
| 5 | 移行容易性 | 現状から新変数への置換の簡潔さ | ⭐⭐ (2) |

**重み付けの理由**:
- **衝突リスク (5)**: 最重要。プロダクトコードとの衝突は致命的な問題を引き起こす
- **名前空間分離 (4)**: 非常に重要。何の変数かが明確でないと混乱を招く
- **可読性 (3)**: 重要。日常的に目にする変数なので読みやすさは必要
- **拡張性 (3)**: 重要。将来的な変数追加を見越した設計
- **移行容易性 (2)**: やや重要。一度の作業なので他項目より優先度は低い

#### **評価基準値の定義**

各項目について5段階評価（1-5点）を行います。

**1. 衝突リスク**（低いほど高評価）
- 5点: 衝突可能性が極めて低い（専用プレフィックス + 固有の単語）
- 4点: 衝突可能性が低い（専用プレフィックスあり）
- 3点: 衝突可能性が中程度（一般的だが長い変数名）
- 2点: 衝突可能性が高い（一般的な単語の組み合わせ）
- 1点: 衝突可能性が非常に高い（汎用的な変数名）

**2. 名前空間分離**（明確なほど高評価）
- 5点: 専用プレフィックスで完全に分離されている
- 4点: プレフィックスで分離されているが略称
- 3点: 長い変数名で暗黙的に分離
- 2点: 一部のみ識別可能
- 1点: 分離されていない

**3. 可読性**（読みやすいほど高評価）
- 5点: 最適な長さ（10-15文字）で意味が明確
- 4点: やや短い/長いが意味は明確
- 3点: 長いが理解可能
- 2点: 非常に長く読みづらい
- 1点: 短すぎて意味不明または長すぎて使いづらい

**4. 拡張性**（将来の拡張がしやすいほど高評価）
- 5点: 明確なプレフィックスパターンで拡張容易
- 4点: プレフィックスはあるが若干の曖昧さ
- 3点: 拡張可能だが統一性に欠ける
- 2点: 拡張時に命名規則が崩れる可能性
- 1点: 拡張が困難

**5. 移行容易性**（置換が簡単なほど高評価）
- 5点: 完全に機械的に一括置換可能
- 4点: ほぼ機械的に置換可能、一部手動確認
- 3点: 手動確認が必要
- 2点: 複雑な置換ロジックが必要
- 1点: 大幅なリファクタリングが必要

### 3-2. 意思決定の構造

変数名は以下の3つの独立した意思決定から構成されます:

```
変数名 = [プレフィックス] + "_" + [コア要素] + [NAME サフィックス]
```

**意思決定①: プレフィックス**
- `MDC_` vs `MONOLITHIC_DEVCONTAINER_`

**意思決定②: コア要素**
- `REPO` を含めるか
- `ROOT` を含めるか
- 両方を含めるか (`REPO_ROOT`)

**意思決定③: NAME サフィックス**
- `_NAME` を付けるか付けないか

### 3-3. 意思決定①: プレフィックスの選択

`MDC_` vs `MONOLITHIC_DEVCONTAINER_` の比較:

| 評価項目 | MDC_ | MONOLITHIC_DEVCONTAINER_ | 理由 |
|---------|------|--------------------------|------|
| 衝突リスク (×5) | 5点 (25点) | 5点 (25点) | 両方とも専用プレフィックスで衝突可能性は極めて低い |
| 名前空間分離 (×4) | 4点 (16点) | 5点 (20点) | MONOLITHIC_DEVCONTAINER_ の方が完全に明示的だが、MDC_ も略称として十分明確 |
| 可読性 (×3) | 5点 (15点) | 2点 (6点) | MDC_ は4文字で最適、MONOLITHIC_DEVCONTAINER_ は26文字で非常に長い |
| 拡張性 (×3) | 5点 (15点) | 5点 (15点) | 両方とも明確なプレフィックスパターンで拡張容易 |
| 移行容易性 (×2) | 5点 (10点) | 5点 (10点) | どちらも機械的に一括置換可能 |
| **合計** | **81点** | **76点** | |

**結論**: `MDC_` を選択
- 可読性で大きく上回る（15点 vs 6点）
- 名前空間分離では若干劣るが、実用上問題なし
- 日常的に使用する変数なので、可読性を優先

### 3-4. 意思決定②: コア要素の選択

`REPO` / `ROOT` / `REPO_ROOT` の比較:

| 評価項目 | REPO | ROOT | REPO_ROOT | 理由 |
|---------|------|------|-----------|------|
| 衝突リスク (×5) | 4点 (20点) | 4点 (20点) | 5点 (25点) | REPO_ROOT は複合語で一般的なスクリプトでは使われにくい。REPO や ROOT 単体よりも衝突リスクが低い |
| 名前空間分離 (×4) | 3点 (12点) | 3点 (12点) | 4点 (16点) | REPO_ROOT は文脈が最も明確。「リポジトリのルート」という意味が一語で伝わる |
| 可読性 (×3) | 4点 (12点) | 4点 (12点) | 4点 (12点) | REPO_ROOT は若干長いが理解しやすい。3つとも許容範囲内 |
| 拡張性 (×3) | 3点 (9点) | 4点 (12点) | 5点 (15点) | REPO_ROOT をベースに `MDC_REPO_ROOT_PATH`、`MDC_REPO_ROOT_CONFIG` など統一的な命名が可能 |
| 移行容易性 (×2) | 5点 (10点) | 5点 (10点) | 5点 (10点) | どれも機械的に一括置換可能 |
| **合計** | **63点** | **66点** | **78点** | |

**結論**: `REPO_ROOT` を選択
- 衝突リスク、名前空間分離、拡張性の全てで優位
- 「リポジトリのルート」という意味が正確に伝わる
- REPO と ROOT のいいとこ取り

### 3-5. 意思決定③: NAME サフィックスの選択

`_NAME` あり vs なし の比較:

| 評価項目 | MDC_REPO_ROOT_NAME | MDC_REPO_ROOT | 理由 |
|---------|-------------------|---------------|------|
| 衝突リスク (×5) | 5点 (25点) | 5点 (25点) | 両方とも衝突可能性は極めて低い |
| 名前空間分離 (×4) | 4点 (16点) | 4点 (16点) | 両方とも明確 |
| 可読性 (×3) | 3点 (9点) | 4点 (12点) | MDC_REPO_ROOT の方が短く読みやすい（18文字 vs 13文字） |
| 拡張性 (×3) | 4点 (12点) | 5点 (15点) | _NAME なしの方が統一的: `MDC_REPO_ROOT`（名前）、`MDC_REPO_ROOT_PATH`（パス）など、サフィックスで役割を明示できる |
| 移行容易性 (×2) | 5点 (10点) | 5点 (10点) | どちらも機械的に一括置換可能 |
| **合計** | **72点** | **78点** | |

**結論**: `_NAME` なし（`MDC_REPO_ROOT`）を選択
- 可読性と拡張性で優位
- 現在の変数は「ディレクトリ名」を表すが、将来的に `MDC_REPO_ROOT_PATH`（フルパス）などの派生変数が必要になった際、`_NAME` なしの方が統一的に命名できる

### 3-6. 最終推奨

**3つの意思決定の結果**:
- 意思決定①: `MDC_` を選択
- 意思決定②: `REPO_ROOT` を選択
- 意思決定③: `_NAME` なし を選択

**最終推奨: `MDC_REPO_ROOT`**

---

## 4. 移行計画

### 4-1. 移行ステップ

#### **Phase 1: 実装ファイルの更新**

```bash
# 対象ファイル（7ファイル）
.devcontainer/docker-compose.yml
.devcontainer/docker-entrypoint.sh
.devcontainer/devcontainer.json.template
.devcontainer/generate-env.sh
.devcontainer/setup.sh
.devcontainer/post-create.sh
workloads/process-compose/project.yaml
```

**手順**:
1. 各ファイルで `REPO_NAME` を `MDC_REPO_ROOT` に置換
2. デフォルト値の確認（`${MDC_REPO_ROOT:-dev-hub}`）
3. supervisord設定の場合は `ENV_REPO_NAME` → `ENV_MDC_REPO_ROOT`

#### **Phase 2: ドキュメントの更新**

```bash
# 対象ファイル（重要度順）
foundations/v10_environment_variables_golden_test.md
initiatives/20251229--dev-hub-concept/resolved/25_6_21_verification_procedure.md
initiatives/20251229--dev-hub-concept/decisions/25_0_process_management_solution.v10.md
initiatives/20251229--dev-hub-concept/resolved/25_6_12_v10_completion_implementation_tracker.md
# ... その他15ファイル
```

**手順**:
1. すべてのドキュメントファイルで一括置換（old/ 含む全ファイル）
2. `REPO_NAME` → `MDC_REPO_ROOT` に統一
3. 置換漏れがないか grep -r で確認

#### **Phase 3: 検証**

1. **ビルド検証**
   ```bash
   cd .devcontainer
   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml build --no-cache
   ```

2. **起動検証**
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml up -d
   docker exec devcontainer-dev-1 env | grep MDC_REPO_ROOT
   ```

3. **ゴールデンテスト実行**
   ```bash
   # foundations/v10_environment_variables_golden_test.md の全項目を実行
   ```

### 4-2. 後方互換性の考慮

**オプション1: 後方互換性を維持しない（推奨）**

- 理由: 内部環境変数であり、外部依存がない
- 一括移行で問題なし

**オプション2: 移行期間を設ける**

```bash
# 両方の変数を一時的にサポート
MDC_REPO_ROOT=${MDC_REPO_ROOT:-${REPO_NAME:-dev-hub}}
REPO_NAME=${MDC_REPO_ROOT}  # 後方互換性のため非推奨警告付き
```

- 理由: 外部スクリプトが `REPO_NAME` に依存している可能性がある場合
- 推奨期間: 1-2リリース

### 4-3. リスク評価

| リスク | 影響度 | 発生確率 | 対策 |
|--------|--------|---------|------|
| 置換漏れによる起動失敗 | 高 | 低 | grep -r でダブルチェック、ゴールデンテスト実行 |
| 既存の作業ブランチとの競合 | 中 | 中 | マージ後すぐに実施、広報 |
| ドキュメント更新漏れ | 低 | 中 | grep -r で全ファイル確認 |
| 外部スクリプトの破損 | 中 | 低 | 後方互換レイヤー追加（オプション） |

---

## 5. 実装の詳細

### 5-1. docker-compose.yml の変更例

**変更前**:
```yaml
volumes:
  - type: bind
    source: ${REPOSITORY_ROOT}
    target: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}

working_dir: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}

environment:
  - REPO_NAME=${REPO_NAME:-dev-hub}
```

**変更後**:
```yaml
volumes:
  - type: bind
    source: ${REPOSITORY_ROOT}
    target: /home/${UNAME:-vscode}/${MDC_REPO_ROOT:-dev-hub}

working_dir: /home/${UNAME:-vscode}/${MDC_REPO_ROOT:-dev-hub}

environment:
  - MDC_REPO_ROOT=${MDC_REPO_ROOT:-dev-hub}
```

### 5-2. docker-entrypoint.sh の変更例

**変更前**:
```bash
REPO_NAME=${REPO_NAME}
PROJECT_CONF="/home/${UNAME}/${REPO_NAME}/workloads/supervisord/project.conf"
```

**変更後**:
```bash
MDC_REPO_ROOT=${MDC_REPO_ROOT}
PROJECT_CONF="/home/${UNAME}/${MDC_REPO_ROOT}/workloads/supervisord/project.conf"
```

### 5-3. generate-env.sh の変更例

**変更前**:
```bash
REPO_NAME=$(basename "$(cd "$REPOSITORY_ROOT" && pwd)")

cat <<EOF > .env
REPO_NAME="${REPO_NAME}"
EOF
```

**変更後**:
```bash
MDC_REPO_ROOT=$(basename "$(cd "$REPOSITORY_ROOT" && pwd)")

cat <<EOF > .env
MDC_REPO_ROOT="${MDC_REPO_ROOT}"
EOF
```

### 5-4. supervisord設定の変更

**workloads/supervisord/project.conf**:

**変更前**:
```ini
directory=/home/%(ENV_UNAME)s/%(ENV_REPO_NAME)s
```

**変更後**:
```ini
directory=/home/%(ENV_UNAME)s/%(ENV_MDC_REPO_ROOT)s
```

---

## 6. 検証項目

### 6-1. 必須検証項目

- [ ] docker-compose.yml: 環境変数が正しく展開される
- [ ] docker-entrypoint.sh: パスが正しく構築される
- [ ] devcontainer.json: workspaceFolder が正しい
- [ ] generate-env.sh: .env ファイルが正しく生成される
- [ ] setup.sh: devcontainer.json が正しく生成される
- [ ] post-create.sh: リポジトリパスが正しい
- [ ] process-compose/project.yaml: working_dir が正しい
- [ ] supervisord/project.conf: directory が正しい

### 6-2. 統合テスト

- [ ] ゴールデンテストケース全項目が合格
- [ ] コンテナが正常に起動する
- [ ] code-serverが正しいユーザーで起動する
- [ ] process-composeが正常に動作する
- [ ] 環境変数がコンテナ内で正しく設定される

---

## 7. 結論と推奨アクション

### 7-1. 推奨事項

1. **変数名を `MDC_REPO_ROOT` に変更する**
   - 衝突リスクの最小化
   - Monolithic DevContainer専用の名前空間確立
   - 将来的な拡張性（MDC_* プレフィックス統一）

2. **一括移行を実施する**
   - 後方互換性の維持は不要（内部変数のため）
   - 全ファイル（old/ 含む）を一度に変更してゴールデンテスト実行

3. **移行後の検証を徹底する**
   - ゴールデンテストケースの全項目実施
   - ビルド・起動の確認
   - 環境変数の展開確認

### 7-2. 次のステップ

1. **承認取得**: この提案に対する承認
2. **ブランチ作成**: `refactor/rename-repo-name-to-mdc-repo-root`
3. **一括置換実行**: grep -r で全ファイル検索・置換（old/ 含む）
4. **ゴールデンテスト実行**: 変更後の動作確認
5. **PR作成**: 変更内容のレビュー・マージ
6. **ドキュメント更新**: 変更履歴の記録

---

## 8. 補足情報

### 8-1. 関連ドキュメント

- [v10_environment_variables_golden_test.md](../../foundations/v10_environment_variables_golden_test.md) - 検証手順
- [25_0_process_management_solution.v10.md](../decisions/25_0_process_management_solution.v10.md) - v10設計

### 8-2. 参考資料

- [Docker Compose Environment Variables](https://docs.docker.com/compose/environment-variables/)
- [VS Code DevContainer Specification](https://containers.dev/implementors/json_reference/)
- [Bash Best Practices - Naming Conventions](https://google.github.io/styleguide/shellguide.html#s7-naming-conventions)

---

**最終更新**: 2026-01-11
**ステータス**: 🔍 承認待ち
