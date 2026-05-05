# v12 ディレクトリ構造策定戦略

**作成日**: 2026-01-10
**目的**: v11 構造に `bin/` ディレクトリを追加し、v12 として策定する

**関連ドキュメント**:
- `14_詳細設計_ディレクトリ構成.v11.md` - v11 ディレクトリ構造定義
- `25_6_18_devcontainer_scripts_analysis.md` - スクリプト分析結果
- `25_6_16_wrapper_script_strategy.md` - ラッパースクリプト戦略
- `25_6_12_v10_completion_implementation_tracker.md` - 実装トラッカー

---

## 0. 目標

**達成すべきKPI**:
1. ✅ v11 → v12 の明確な変更点の定義
2. ✅ ADR 005 による変更理由の記録
3. ✅ v12 構造ドキュメントの作成
4. ✅ 既存ドキュメントの整合性維持

**スプリント/Qのゴール**:
- v10 実装完成（s6-overlay、USER問題解決）
- アーキテクチャの一貫性維持
- 技術的に正しい構造設計

---

## 1. v11 → v12 の変更内容

### 1.1 変更サマリー

**変更点**: `bin/` ディレクトリの追加

**理由**: 運用ツールスクリプトの配置場所として定義

**影響範囲**:
- v12 構造ドキュメントの作成
- ADR 005 の作成
- 25_6_18、25_6_16、25_6_12 の更新

### 1.2 v11 と v12 の構造比較

#### v11 構造（現行）

```text
${project}-dev-hub/
├── .devcontainer/        # DevContainer設定とビルド準備スクリプト、コンテナ初期化スクリプト、シェル設定
├── foundations/
├── initiatives/
├── members/
├── workloads/            # プロセス管理設定（supervisord, process-compose）
├── repos/
├── workspace.code-workspace
├── .gitignore
└── .env.example
```

#### v12 構造（新規）

```text
${project}-dev-hub/
├── .devcontainer/        # DevContainer設定とビルド準備スクリプト、コンテナ初期化スクリプト、シェル設定
├── bin/                  # ★新設: 運用ツールスクリプト
│   └── dc                # docker compose exec ラッパースクリプト
├── foundations/
├── initiatives/
├── members/
├── workloads/            # プロセス管理設定（supervisord, process-compose）
├── repos/
├── workspace.code-workspace
├── .gitignore
└── .env.example
```

**変更点**: `bin/` ディレクトリとその配下の `dc` スクリプトのみ

---

## 2. v12 で追加される要素

### 2.1 `bin/` ディレクトリ

**目的**: 運用ツールスクリプトの配置場所

**特性**:
- **実行場所**: Host-side
- **実行タイミング**: DevContainer運用時
- **実行者**: 開発者（手動実行）
- **Git管理**: ✅ 管理対象

**配置されるスクリプト**:
- `dc` - docker compose exec ラッパースクリプト（初期配置）
- 将来的な拡張: デバッグヘルパー、ログ集約スクリプト、テストランナー等

### 2.2 `bin/dc` スクリプト

**役割**: docker compose exec に自動的に `-u ${UNAME}` を付与する運用ツール

**実装詳細**: `25_6_16_wrapper_script_strategy.md` を参照

**使用例**:
```bash
# リポジトリルートから
./bin/dc exec dev /bin/bash
# → docker compose -f .devcontainer/docker-compose.yml -f .devcontainer/docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash
```

**技術的な正当性**:
- `.devcontainer/` のスクリプトは「ビルド準備」「コンテナ初期化」
- `bin/` のスクリプトは「運用ツール」
- 役割の明確な分離により、将来の保守性が向上

---

## 3. `.devcontainer/` と `bin/` の役割分離

### 3.1 役割の明確化

#### `.devcontainer/` の役割

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
- `.devcontainer/shell/` 配下のシェル設定ファイル

**共通点**: すべて「DevContainerのビルド・初期化」に関連

---

#### `bin/` の役割（新設）

**カテゴリD: Host-side 運用ツールスクリプト**
- `dc` - docker compose exec ラッパー

**特性**: 「DevContainer運用時」に開発者が手動で実行

**将来の拡張例**:
- `bin/test-runner` - テスト実行ヘルパー
- `bin/debug-helper` - デバッグ支援スクリプト
- `bin/log-aggregator` - ログ集約スクリプト

---

### 3.2 比較表

| 項目 | `.devcontainer/` | `bin/` |
|------|-----------------|--------|
| **実行場所** | Host-side または Container-side | Host-side |
| **実行タイミング** | DevContainer開く**前/中/後** | DevContainer運用**中** |
| **役割** | ビルド準備・初期化・シェル設定 | **運用ツール** |
| **実行頻度** | 初回または構成変更時（低頻度） | 開発作業中（**高頻度**） |
| **DevContainerビルドとの関係** | **必須**（ビルドに関連） | **無関係**（運用時に使用） |
| **スクリプト例** | setup.sh, docker-entrypoint.sh | dc, test-runner |

---

## 4. ADR 005 の内容案

### 4.1 ADR 005: 開発ツールスクリプトの配置場所と v12 構造の策定

**ステータス**: Accepted

**日付**: 2026-01-10

**コンテキスト**:

v10 設計において、docker compose exec に自動的に `-u ${UNAME}` を付与するラッパースクリプト（dc）の配置場所を決定する必要があった。

既存の `.devcontainer/` ディレクトリには以下のスクリプトが存在していた:
- ビルド準備スクリプト: setup.sh, generate-env.sh, validate-config.sh
- コンテナ初期化スクリプト: docker-entrypoint.sh, post-create.sh, debug-entrypoint.sh, s6-entrypoint.sh
- シェル設定ファイル: .devcontainer/shell/ 配下

これらはすべて「DevContainerのビルド・初期化」に関連するスクリプトであり、新規スクリプト（dc）の「運用ツール」という役割とは異なる。

**問題点**:
1. `.devcontainer/` にdcを配置すると、役割が混在する
2. v11 構造に `bin/` ディレクトリが存在しない
3. 将来的な運用ツールの追加を考慮した配置場所が必要

**決定内容**:

**v12 構造を策定し、`bin/` ディレクトリを開発ツールスクリプト（運用時に使用）の配置場所として追加する。**

**構造変更**:
```text
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

**役割の明確化**:
- `.devcontainer/` = ビルド準備・コンテナ初期化・シェル設定
- `bin/` = 運用ツール（DevContainer運用中に開発者が手動で実行）

**代替案**:

**代替案1**: `.devcontainer/dc` に配置
- メリット: v11構造変更不要、ADR不要、即座に実装可能
- デメリット: 役割の混在、発見しにくい、将来的な拡張性が低い、技術的正当性が低い
- 評価: ❌ 技術的に不適切

**代替案2**: `workloads/scripts/dc` に配置
- メリット: v11の `workloads/` 概念に整合
- デメリット: workloads設計意図（プロセス管理設定）とズレ、パスが長い、発見しにくい、workloads役割の曖昧化
- 評価: ❌ 技術的に不適切

**選択理由**:

1. **役割の明確化**
   - `.devcontainer/` = ビルド準備・初期化
   - `bin/` = 運用ツール
   - 明確な責務分離により、将来的な保守性が向上

2. **技術的正当性**
   - `bin/` は開発ツールスクリプトの標準的な配置場所
   - リポジトリ構造の慣習に準拠
   - 他のプロジェクトとの一貫性

3. **将来の拡張性**
   - 他の運用ツール（デバッグヘルパー、ログ集約スクリプト、テストランナー）を統一的に管理可能
   - `.devcontainer/` の肥大化を防止
   - スケーラブルな構造

4. **発見しやすさ**
   - リポジトリルート直下、パスが短い（`./bin/dc` = 8文字）
   - チームメンバーが直感的に見つけられる

5. **保守コスト vs 長期的利益**
   - ADR作成は1回のみのコスト
   - 長期的には統一された構造により保守性向上
   - 技術的負債の回避

**影響**:

1. **v11 → v12 へのバージョンアップ**
   - `14_詳細設計_ディレクトリ構成.v12.md` の作成
   - v11 構造は不変のまま保持

2. **ドキュメント更新**
   - `25_6_18_devcontainer_scripts_analysis.md` の更新（v12 策定に変更）
   - `25_6_16_wrapper_script_strategy.md` の更新（配置場所を `bin/dc` に確定）
   - `25_6_12_v10_completion_implementation_tracker.md` の更新（v12 関連タスク追加）

3. **実装への影響**
   - `bin/` ディレクトリの作成
   - `bin/dc` スクリプトの配置
   - `.gitignore` への追加は不要（Git管理対象）

**参照**:
- `25_6_18_devcontainer_scripts_analysis.md` - スクリプト分析結果
- `25_6_16_wrapper_script_strategy.md` - ラッパースクリプト戦略
- `14_詳細設計_ディレクトリ構成.v11.md` - v11 構造定義

---

## 5. v12 構造ドキュメントの作成内容

### 5.1 ファイル名

`14_詳細設計_ディレクトリ構成.v12.md`

### 5.2 構成

v11 のドキュメントをベースに、以下の変更を加える:

#### セクション1: 概要
- v12 の目的を追記
  - v11 の内容（CLI版AIエージェント対応、ハイブリッドプロセス管理）を継承
  - **新規**: 運用ツールスクリプトの配置場所の明確化

#### セクション2: コンテナ内の全体構造
- `bin/` ディレクトリを追加
  ```text
  /home/<user>/
  ├── ${project}-dev-hub/
  │   ├── .devcontainer/
  │   ├── bin/              # ★v12で追加: 運用ツールスクリプト
  │   ├── foundations/
  │   ├── initiatives/
  │   ├── members/
  │   ├── workloads/
  │   ├── repos/
  │   ├── workspace.code-workspace
  │   ├── .gitignore
  │   └── .env.example
  ```

#### セクション3: `${project}-dev-hub/` の詳細構造
- `bin/` ディレクトリのツリー表記を追加
  ```text
  ${project}-dev-hub/
  ├── .devcontainer/
  ├── bin/                  # ★v12で追加: 運用ツールスクリプト
  │   └── dc                # docker compose exec ラッパー
  ├── foundations/
  ├── initiatives/
  ├── members/
  ├── workloads/
  ├── repos/
  ├── workspace.code-workspace
  ├── .gitignore
  └── .env.example
  ```

#### セクション4（新規）: v12で追加された要素

**4.1 `bin/` ディレクトリ - 運用ツールスクリプト**

**目的**: DevContainer運用時に開発者が手動で実行するツールスクリプトの配置場所

**配置されるスクリプト**:
- `dc` - docker compose exec ラッパースクリプト

**役割の明確化**:
| ディレクトリ | 役割 | 実行タイミング | 例 |
|------------|------|--------------|-----|
| `.devcontainer/` | ビルド準備・コンテナ初期化・シェル設定 | DevContainer開く前/中/後 | setup.sh, docker-entrypoint.sh |
| `bin/` | 運用ツール | DevContainer運用中 | dc, test-runner |

**設計意図**:
- `.devcontainer/` と `bin/` の役割を明確に分離
- 将来的な運用ツールの追加に対応（デバッグヘルパー、ログ集約スクリプト、テストランナー等）
- 標準的な慣習（`bin/` ディレクトリ）に準拠

**技術的な正当性**:
- `bin/` は開発ツールスクリプトの標準的な配置場所
- 役割の明確な分離により、保守性が向上
- 発見しやすく、パスが短い（`./bin/dc` = 8文字）

#### セクション5: 設計判断の記録（ADR）
- ADR 005 を追加
  ```markdown
  | ADR | タイトル | 概要 |
  |-----|---------|------|
  | 001 | Monolithic DevContainer | 組織で1つの巨大なDevContainerを採用 |
  | 002 | Docker Volume Strategy | I/Oパフォーマンスのためのマウント戦略 |
  | 003 | CLI AI Agent Compatibility | CLI版AIエージェント対応のための物理統合 |
  | 004 | Workloads Directory Naming | `workloads/`命名の根拠とK8s用語の採用 |
  | 005 | Development Tools Scripts Placement | 開発ツールスクリプトの配置場所と v12 構造の策定（★v12で追加） |
  ```

#### セクション6: 変更履歴
- v12 の変更内容を追記
  ```markdown
  ### v12 (2026-01-10)
  - **運用ツールスクリプトの配置場所の明確化**: `bin/` ディレクトリを追加
  - **役割の明確な分離**: `.devcontainer/` と `bin/` の役割を定義
  - **ADR 005追加**: 開発ツールスクリプトの配置場所と v12 構造の策定
  - **`bin/dc` スクリプト配置**: docker compose exec ラッパースクリプト
  ```

---

## 6. 実装計画

### Phase 1: ADR 005 作成

**タスク1-1**: ADR 005 ドキュメント作成

**ファイル**: `foundations/adr/005_development_tools_scripts_placement.md`

**内容**: 本ドキュメントのセクション4.1の内容

**完了基準**: ADR 005 が作成され、Git管理対象に追加されている

---

### Phase 2: v12 構造ドキュメント作成

**タスク2-1**: v12 構造ドキュメント作成

**ファイル**: `initiatives/20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v12.md`

**内容**: 本ドキュメントのセクション5.2の内容

**作成方法**:
1. v11 ドキュメント（`14_詳細設計_ディレクトリ構成.v11.md`）をコピー
2. セクション5.2で定義した変更を適用
3. v12 変更履歴を追記

**完了基準**: v12 構造ドキュメントが作成され、v11 との差分が明確に記載されている

---

### Phase 3: 既存ドキュメントの更新

**タスク3-1**: 25_6_18 の更新

**ファイル**: `initiatives/20251229--dev-hub-concept/25_6_18_devcontainer_scripts_analysis.md`

**更新内容**:
- 「v11構造更新」→「v12構造策定」に変更
- 実装計画を v12 作成プロセスに修正
- ADR 005 の内容を「v12構造の策定」に変更

**タスク3-2**: 25_6_16 の確認

**ファイル**: `initiatives/20251229--dev-hub-concept/25_6_16_wrapper_script_strategy.md`

**確認内容**:
- `bin/dc` の記載が正しいか確認（既に正しい）
- スクリプト内の相対パス計算が正しいか確認（既に正しい）

**タスク3-3**: 25_6_12 の更新

**ファイル**: `initiatives/20251229--dev-hub-concept/25_6_12_v10_completion_implementation_tracker.md`

**更新内容**:
- Phase 2-2-1のスクリプト作成タスクに「v12構造（25_6_18、25_6_19に基づく）」を追記
- Phase 3にADR作成タスクを追加
  - Phase 3-5: ADR 005作成
  - Phase 3-6: v12構造ドキュメント作成
  - Phase 3-7: 既存ドキュメント更新（25_6_18、25_6_16、25_6_12）

---

### Phase 4: bin/ ディレクトリと dc スクリプトの作成（mode-3で実施）

**タスク4-1**: bin/ ディレクトリ作成

**コマンド**: `mkdir -p bin`

**完了基準**: `bin/` ディレクトリが作成されている

**タスク4-2**: dc スクリプト作成

**ファイル**: `bin/dc`

**内容**: `25_6_16_wrapper_script_strategy.md` の実装内容

**完了基準**:
- `bin/dc` スクリプトが作成されている
- 実行権限が付与されている（`chmod +x bin/dc`）
- 動作確認が完了している

---

## 7. まとめ

### 7.1 v12 策定の意義

**技術的な正当性**:
1. **役割の明確化** - `.devcontainer/` と `bin/` の責務分離
2. **将来の拡張性** - 運用ツールの統一的な管理
3. **標準的慣習への準拠** - `bin/` ディレクトリの採用
4. **保守性の向上** - 技術的負債の回避

**v11 との関係**:
- v11 構造は不変のまま保持
- v12 として新バージョンを策定
- v11 → v12 の差分が明確

**長期的な利益**:
- 統一された構造
- 拡張性の確保
- チーム全体での運用可能性

---

### 7.2 次のアクション

**mode-2（戦略立案モード）の成果物**:
1. ✅ このドキュメント（25_6_19）の作成
2. ✅ ADR 005 の内容案
3. ✅ v12 構造ドキュメントの内容案
4. ✅ 実装計画の策定

**ユーザーへの確認**:

v12 構造策定の方針で進めてよろしいでしょうか？

承認いただけましたら、以下の順序で実装（mode-3）に移行します:
1. ADR 005 作成
2. v12 構造ドキュメント作成
3. 既存ドキュメント更新（25_6_18、25_6_16、25_6_12）
4. bin/ ディレクトリと dc スクリプトの作成

---

**最終更新**: 2026-01-10T07:00:00+09:00
**ステータス**: ✅ v12 策定戦略完了
**次のアクション**: ユーザーの承認待ち → mode-3で実装開始
