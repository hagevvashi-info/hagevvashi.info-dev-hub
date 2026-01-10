# ADR 005: 開発ツールスクリプトの配置場所と v12 構造の策定

**ステータス**: Accepted

**日付**: 2026-01-10

**決定者**: hagevvashi

---

## コンテキスト

v10 設計において、docker compose exec に自動的に `-u ${UNAME}` を付与するラッパースクリプト（dc）の配置場所を決定する必要があった。

### 背景

**v10 設計の課題**:
- Docker の USER ディレクティブは、イメージメタデータとして ENTRYPOINT、CMD、docker exec すべてに影響する
- PID 1 = root で起動する必要がある（s6-overlay による zombie process reaping）
- docker exec = ${UNAME} で実行する必要がある（ファイル所有権の問題回避）
- この両立を実現するため、docker compose exec に自動的に `-u ${UNAME}` を付与するラッパースクリプト（dc）が必要

### 既存のスクリプト配置状況

既存の `.devcontainer/` ディレクトリには以下の12ファイルが存在していた:

**カテゴリA: Host-side ビルド準備・検証スクリプト**
- `setup.sh` - DevContainer開く前の事前準備
- `generate-env.sh` - 環境変数ファイル生成
- `validate-config.sh` - 設定ファイル検証

**カテゴリB: Container-side 初期化・ENTRYPOINT スクリプト**
- `docker-entrypoint.sh` - コンテナ起動時の初期化（ENTRYPOINT）
- `debug-entrypoint.sh` - デバッグモード用ENTRYPOINT
- `s6-entrypoint.sh` - s6-overlay用ENTRYPOINT
- `post-create.sh` - DevContainerビルド後処理

**カテゴリC: Container-side シェル設定ファイル**
- `.devcontainer/shell/.bash_profile` - Bashログインシェル初期化
- `.devcontainer/shell/.bashrc_custom` - Bash設定
- `.devcontainer/shell/.profile` - POSIXシェル初期化
- `.devcontainer/shell/env.sh` - 環境変数設定
- `.devcontainer/shell/paths.sh` - PATH設定

これらはすべて「DevContainerのビルド・初期化」に関連するスクリプトであり、新規スクリプト（dc）の「運用ツール」という役割とは異なる。

### 問題点

1. `.devcontainer/` にdcを配置すると、役割が混在する
   - ビルド準備スクリプトと運用ツールスクリプトが同じ場所に配置される
   - 将来的な拡張時に `.devcontainer/` が肥大化する
   - 発見しにくい（開発者は運用ツールを `.devcontainer/` 内で探すことを期待しない）

2. v11 構造に `bin/` ディレクトリが存在しない
   - 一般的な慣習（`bin/` = 開発ツールスクリプト）に準拠していない
   - 運用ツールの配置場所が明確でない

3. 将来的な運用ツールの追加を考慮した配置場所が必要
   - デバッグヘルパー、ログ集約スクリプト、テストランナー等の追加を想定
   - 統一的な管理場所が必要

---

## 決定内容

**v12 構造を策定し、`bin/` ディレクトリを開発ツールスクリプト（運用時に使用）の配置場所として追加する。**

### 構造変更

```text
# v11（現行）
${project}-dev-hub/
├── .devcontainer/        # DevContainer設定とビルド準備、初期化、シェル設定
├── foundations/
├── initiatives/
├── members/
├── workloads/
├── repos/
├── workspace.code-workspace
├── .gitignore
└── .env.example

# v12（新規）
${project}-dev-hub/
├── .devcontainer/        # DevContainer設定とビルド準備、初期化、シェル設定
├── bin/                  # ★新設: 運用ツールスクリプト
│   └── dc                # docker compose exec ラッパースクリプト
├── foundations/
├── initiatives/
├── members/
├── workloads/
├── repos/
├── workspace.code-workspace
├── .gitignore
└── .env.example
```

### 役割の明確化

| ディレクトリ | 役割 | 実行タイミング | 実行場所 | 例 |
|------------|------|--------------|---------|-----|
| `.devcontainer/` | ビルド準備・コンテナ初期化・シェル設定 | DevContainer開く前/中/後 | Host/Container | setup.sh, docker-entrypoint.sh |
| `bin/` | 運用ツール | DevContainer運用中 | Host | dc, test-runner |

---

## 代替案

### 代替案1: `.devcontainer/dc` に配置

**メリット**:
- v11構造変更不要
- ADR不要
- 即座に実装可能

**デメリット**:
- ❌ 役割の混在（ビルド準備と運用ツールが同じ場所）
- ❌ 発見しにくい（`.devcontainer/` 内を探す必要）
- ❌ 将来的な拡張性が低い（`.devcontainer/` が肥大化）
- ❌ パスが長い（`./.devcontainer/dc` = 14文字）
- ❌ 技術的正当性が低い（役割混在による保守性低下）

**評価**: ❌ 技術的に不適切

---

### 代替案2: `workloads/scripts/dc` に配置

**メリット**:
- v11の `workloads/` 概念に整合（実運用プロセス管理設定）

**デメリット**:
- ❌ workloads設計意図（プロセス管理設定）とズレ
  - v11で `workloads/` は「supervisord.conf, process-compose.yaml」等の設定ファイルの配置場所
  - 「スクリプト」を含めることは設計意図の拡張
- ❌ パスが非常に長い（`./workloads/scripts/dc` = 22文字）
- ❌ 発見しにくい（`workloads/` 内を探す必要）
- ❌ ADR 004（workloads命名根拠）の更新が必要
- ❌ workloads役割の曖昧化（設定ファイルとスクリプトの混在）

**評価**: ❌ 技術的に不適切

---

## 選択理由

### 1. 役割の明確化

`.devcontainer/` と `bin/` の役割を明確に分離:
- `.devcontainer/` = ビルド準備・コンテナ初期化・シェル設定
- `bin/` = 運用ツール（DevContainer運用中に開発者が手動で実行）

明確な責務分離により、将来的な保守性が向上する。

### 2. 技術的正当性

- `bin/` は開発ツールスクリプトの標準的な配置場所
- リポジトリ構造の慣習に準拠
- 他のプロジェクトとの一貫性

### 3. 将来の拡張性

他の運用ツールを統一的に管理可能:
- デバッグヘルパー（例: `bin/debug-helper`）
- ログ集約スクリプト（例: `bin/log-aggregator`）
- テストランナー（例: `bin/test-runner`）

`.devcontainer/` の肥大化を防止し、スケーラブルな構造を実現。

### 4. 発見しやすさ

- リポジトリルート直下に配置
- パスが短い（`./bin/dc` = 8文字）
- チームメンバーが直感的に見つけられる

### 5. 保守コスト vs 長期的利益

**保守コスト**:
- ADR作成は1回のみのコスト
- v12構造ドキュメント作成は1回のみのコスト

**長期的利益**:
- 統一された構造により保守性向上
- 技術的負債の回避
- 拡張性の確保

---

## 影響

### 1. v11 → v12 へのバージョンアップ

- `14_詳細設計_ディレクトリ構成.v12.md` の作成
- v11 構造は不変のまま保持

### 2. ドキュメント更新

- `25_6_18_devcontainer_scripts_analysis.md` の更新（v12 策定に変更）
- `25_6_16_wrapper_script_strategy.md` の更新（配置場所を `bin/dc` に確定）
- `25_6_12_v10_completion_implementation_tracker.md` の更新（v12 関連タスク追加）

### 3. 実装への影響

- `bin/` ディレクトリの作成
- `bin/dc` スクリプトの配置
- `.gitignore` への追加は不要（Git管理対象）

### 4. チームへの影響

**ポジティブな影響**:
- 運用ツールの配置場所が明確になる
- 標準的な慣習に準拠することで、新規メンバーが理解しやすい
- 将来的な拡張がしやすい

**ネガティブな影響**:
- 新しいディレクトリの追加により、構造が若干複雑化
- （軽微）既存メンバーへの周知が必要

---

## 参照

- [25_6_18_devcontainer_scripts_analysis.md](../../initiatives/20251229--dev-hub-concept/25_6_18_devcontainer_scripts_analysis.md) - スクリプト分析結果
- [25_6_19_v12_structure_strategy.md](../../initiatives/20251229--dev-hub-concept/25_6_19_v12_structure_strategy.md) - v12 策定戦略
- [25_6_16_wrapper_script_strategy.md](../../initiatives/20251229--dev-hub-concept/25_6_16_wrapper_script_strategy.md) - ラッパースクリプト戦略
- [14_詳細設計_ディレクトリ構成.v11.md](../../initiatives/20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v11.md) - v11 構造定義
- [14_詳細設計_ディレクトリ構成.v12.md](../../initiatives/20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v12.md) - v12 構造定義

---

## 備考

本決定は、「変更量が少ない」「シンプル」「短期的」という理由ではなく、**技術的正当性**、**将来の拡張性**、**保守性**を重視して行われた。

assistant-modes.mdc mode-2 の原則に従い、長期的な利益を優先した決定である。
