---
inclusion: always
---

# Rules - commit-messages-guidelines(コミットメッセージ作成指針)

- このファイルが読み込まれたら「commit-message-guideline.mdcを読み込みました！」と作業着手前にユーザーに必ず伝えてください。

--

## 基本ルール
- prefixをつけること
- prefixは以下から選ぶこと:
  - `docs`: ドキュメントの変更
  - `ci`: CI関連の変更
  - `chore`: 雑務的な変更
  - `feat`: 新機能の追加
  - `refactor`: リファクタリング
  - `build`: ビルドシステムの変更
  - `perf`: パフォーマンス改善
  - `style`: コードスタイルの変更
  - `test`: テストの追加・修正
- コミットメッセージは英語で作成すること
- 必ず3つの候補を作成し、各候補にメリット・デメリットを日本語で添えること
- その候補の中から最適なものを選んでコミットメッセージとすること
- なぜそれが最適化をしっかりとユーザーに伝えること

## メッセージフォーマット
```
${prefix}: ${title}

${body}
```

### フォーマット詳細
- シンプルなプレーンテキストであること
- 1行目: `${prefix}: ${title}`形式でタイトルを記述
- 2行目: 必ず空行とする
- 3行目以降: 本文を記述
  - 変更の理由（Why）を必ず含める
  - ただし、"Why:"という書き出しは使用しない

## 候補作成例

変更内容：AIアシスタントの行動指針を追加した場合

候補1:
```
docs: add AI assistant behavioral guidelines

Define core principles and specific guidelines for AI assistant behavior.
This helps maintain consistency in AI responses and prevents common mistakes
in command execution, especially for Docker operations.
```
メリット：
- 変更の目的と効果が明確
- ドキュメントの性質を正確に表現
デメリット：
- 技術的な詳細が少ない

候補2:
```
feat: implement AI assistant guidelines system

Create .ai directory with guidelines.md to establish systematic approach
for AI assistant behavior. This provides a reusable framework for
maintaining consistent AI responses across different operations.
```
メリット：
- システムとしての側面を強調
- 構造的な変更であることが分かる
デメリット：
- 機能追加というよりドキュメント追加の性質が強い

候補3:
```
chore: set up AI assistant documentation structure

Establish .ai directory and initial guidelines document to standardize
AI assistant behavior patterns. This creates a foundation for future
additions to AI behavioral rules.
```
メリット：
- 将来の拡張性を示唆
- セットアップ作業の性質を表現
デメリット：
- 重要度が低く見える可能性がある 
