# ドキュメント索引

## 概要

このディレクトリには go-tty-from-queue プロジェクトの設計ドキュメント、アーキテクチャ分析、および決定記録がステータス別に整理されています。

---

## 📋 ドキュメント カテゴリ

### ✅ 解決済み（Resolved）
完了した分析と決定。これらはシステムの現在の状態を定義します。

- **[QUEUE_MESSAGE_FLOW_SPECIFICATION.md](./resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md)**
  - Slack → エージェント → Slack へのメッセージフロー仕様
  - 内容：Y のポストが処理されるか？（現状：GAS フィルタリングのみ、リスクあり）
  - ステータス：user_id 追加が必要な設計課題を特定

- **[LOCK_RESPONSIBILITY_ANALYSIS.md](./resolved/LOCK_RESPONSIBILITY_ANALYSIS.md)**
  - セッション管理におけるロック所有権と責務の分析
  - 確認事項：Safe/Unsafe メソッドがロック セマンティクスを正しく実装
  - ステータス：設計は堅牢、変更不要

- **[ATOMICITY_AND_LOCK_OWNERSHIP.md](./resolved/ATOMICITY_AND_LOCK_OWNERSHIP.md)**
  - アトミシティの粒度と設計トレードオフの深掘り分析
  - 説明：Lock/Unlock を分離する理由（ロック時間最小化）
  - ステータス：設計の根拠が文書化済み

- **[API_DESIGN_COMPLEXITY_ANALYSIS.md](./resolved/API_DESIGN_COMPLEXITY_ANALYSIS.md)**
  - Manager インターフェース複雑性の分析（Safe/Unsafe メソッド）
  - トレードオフ：シンプル性 vs パフォーマンス vs 制御
  - ステータス：複雑性はパフォーマンス向上により正当化

- **[COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md](./resolved/COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md)**
  - 隠蔽ロック → 明示的ロックによる複雑性増加の測定
  - 定量化：学習時間 10 倍だが安全性により正当化
  - ステータス：トレードオフが承認済み

---

### 🔄 提案中（Proposed）
レビュー中の設計提案。改善または変更を提案します。

（現在は空）

---

### ⏳ 廃棄済み（Outdated）
廃棄または問題のある設計を説明するドキュメント。歴史的背景のため保持。

- **[CURRENT_ENTRY_SCHEMA.md](./outdated/CURRENT_ENTRY_SCHEMA.md)**
  - 記述対象：現在の Entry 構造体（user_id なし）
  - 問題点：ユーザー識別がない、単一障害点フィルタリング
  - 廃棄日：2026-05-17（設計ギャップを特定）
  - 参照：QUEUE_ENTRY_SCHEMA_DESIGN.md 参照

---

### 📌 承認済み（Accepted）
承認され実装準備完了した決定。

- **[QUEUE_ENTRY_SCHEMA_DESIGN.md](./accepted/QUEUE_ENTRY_SCHEMA_DESIGN.md)**
  - **内容：** Queue Entry 構造体に `user_id` フィールドを追加する詳細設計
  - **根拠：** go-tty-from-queue 側での Y フィルタリング（多層防御）、完全な監査証跡
  - **実装範囲：** GAS + go-tty-from-queue の両方の変更が必要
  - **ステータス：** 承認完了、実装待機中
  - **承認日：** 2026-05-17
  - **優先度：** 高（無限ループリスク対策）

---

## 🎯 クイックナビゲーション

### トピック別

**セッション管理とロック**
- 最初に読む：[LOCK_RESPONSIBILITY_ANALYSIS.md](./resolved/LOCK_RESPONSIBILITY_ANALYSIS.md)
- 次に：[ATOMICITY_AND_LOCK_OWNERSHIP.md](./resolved/ATOMICITY_AND_LOCK_OWNERSHIP.md)
- 詳細：[API_DESIGN_COMPLEXITY_ANALYSIS.md](./resolved/API_DESIGN_COMPLEXITY_ANALYSIS.md)

**メッセージフローとアーキテクチャ**
- 最初に読む：[QUEUE_MESSAGE_FLOW_SPECIFICATION.md](./resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md)
- 承認済み修正設計：[QUEUE_ENTRY_SCHEMA_DESIGN.md](./accepted/QUEUE_ENTRY_SCHEMA_DESIGN.md)
- 廃棄済み：[CURRENT_ENTRY_SCHEMA.md](./outdated/CURRENT_ENTRY_SCHEMA.md)

**複雑性と保守性**
- 概要：[COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md](./resolved/COMPLEXITY_AND_LEARNING_COST_ANALYSIS.md)
- API 詳細：[API_DESIGN_COMPLEXITY_ANALYSIS.md](./resolved/API_DESIGN_COMPLEXITY_ANALYSIS.md)

---

## 📊 決定ステータス サマリー

| トピック | ステータス | 必要な処置 |
|---|---|---|
| ロック セマンティクス | ✅ 解決済み | なし（設計が堅牢） |
| セッション アトミシティ | ✅ 解決済み | なし（意図した設計） |
| API 複雑性 | ✅ 解決済み | README に文書化 ✓ |
| キュー メッセージフロー | ✅ 解決済み | Y フィルタリング リスク対策 |
| **キュー スキーマ（user_id）** | 🔄 **提案中** | **決定が必要** |

---

## 🔗 関連情報

- **ソースコード：** internal/ ディレクトリ構造はパッケージ境界に対応
- **README：** [../../README.md](../../README.md) - プロジェクト概要と使用方法
- **Git 履歴：** 実装の決定については commit を確認

---

## 📝 ドキュメント保守

- **最終更新：** 2026-05-17
- **レビュー周期：** 大きな変更の前
- **担当者：** アーキテクチャ レビュー チーム
- **更新プロセス：** 新しいドキュメントを適切なカテゴリ（proposed/resolved/outdated/accepted）に追加

---

## ご質問？

以下のドキュメントを参照してください：
- **ロック機構はどう動く？** → LOCK_RESPONSIBILITY_ANALYSIS.md
- **なぜメソッドが Safe/Unsafe？** → API_DESIGN_COMPLEXITY_ANALYSIS.md
- **システムは Y のポストでループしないか？** → QUEUE_MESSAGE_FLOW_SPECIFICATION.md
- **どう修正する？** → QUEUE_ENTRY_SCHEMA_DESIGN.md（accepted/）
