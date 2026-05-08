# 実装レディネス分析: Call Remote Server LLM Bridge

## 結論

設計の方向性・アーキテクチャは明確だが、**実装に着手するにはいくつかの重要な未決定事項がある**。
特に「Claude Code の CLI/SDK 仕様と設計の乖離」が最大の課題。

---

## 🔴 Critical — 実装開始をブロックする問題

### 1. Claude Code の CLI 仕様が設計と大きく異なる

DESIGN.md のコード例:
```typescript
// 設計書の記載
const agentProcess = spawn('claude-code', ['--json'], { ... });
// session_id を stdout から正規表現でパース
// --resume sessionId で再開
```

**実際の Claude Code CLI（2026年5月時点）:**
- コマンド名は `claude`（`claude-code` ではない）
- セッション再開は `claude -r "<session-id>" "query"`
- SDK モード（非対話）は `claude -p "query"`
- さらに **Claude Agent SDK**（TypeScript/Python）が存在し、プログラマティックにセッション管理が可能
  - `ClaudeSDKClient` で session_id の取得・resume・fork が標準サポート
  - https://code.claude.com/docs/en/agent-sdk/sessions.md

**影響**: Agent Adapter のコード例は全面的に書き直しが必要。node-pty による PTY 制御よりも、**Agent SDK を直接使う方が遥かにシンプルかつ堅牢**になる可能性が高い。

→ **要決定**: node-pty + CLI か、Agent SDK（TypeScript/Python）か。設計アプローチの根幹に関わる。

### 2. Slack App のセットアップ情報が未定義

実装を始めるには以下が必要:
- **どの Slack ワークスペース**を使うか
- Slack App の作成手順（api.slack.com での App 設定）
- 必要な **OAuth Scopes**（`channels:history`, `chat:write`, `reactions:read` 等の具体リスト）
- Bot Token / Signing Secret の取得・保管方法
- **Slack のプラン**（後述の metadata 問題に影響）

### 3. Master Config を置く GitHub リポジトリが未指定

`.github/servers.json` をどこに置くか:
- `tabelog/developer_productivity` 内?
- 専用の新規リポジトリ?
- `hagevvashi-info/hagevvashi.info-dev-hub`?

→ これが決まらないと GitHub API の呼び出し先が定まらない。

---

## 🟡 Major — 実装中に判断が必要になる問題

### 4. HWID（ハードウェアID）の具体的な生成方法が未定義

設計書では `0x123abc456def` のようなIDが例示されているが:
- 何を元に生成するか（MAC address? `/etc/machine-id`? 手動設定の UUID?）
- 生成コマンド・手順がない
- セキュリティ的に適切な値の選定基準がない

### 5. Slack thread metadata は有料プラン（Business+）が必要

設計書ではセッション ID の保存に「Thread metadata（推奨）」を挙げているが:
- Slack の `metadata` フィールドは **Business+ 以上のプラン**でないと使えない
- 無料/Pro プランの場合は**代替案 B（pinned message or スレッド先頭メッセージ）**で実装する必要がある
- どのプランを使うか未決定

### 6. SAM のデプロイ・運用方式が未定義

- プロセス管理: systemd? Docker? pm2? supervisor?
- ログ管理: stdout → ファイル? journald?
- 自動再起動の仕組み
- 設定ファイルの場所（`.env` のパス等）

### 7. Portal のコマンドインターフェース詳細が未定義

- スラッシュコマンドの定義（`/bridge run gpu-srv-1 ...`? `/stop`?）
- サーバー選択の UX（Block Kit のドロップダウン? モーダル?）
- 承認フロー（FR-5）の具体的な UI（ボタン? リアクション?）

### 8. エラーハンドリング戦略が未定義

- Slack API レートリミット（Tier 3: 50+/min）への対処
- GitHub API レートリミット（5000 req/h authenticated）への対処
- ネットワーク障害時のリトライロジック（指数バックオフ? 最大回数?）

---

## 🟢 Ready — 実装可能な部分

| 項目 | 状態 |
|---|---|
| 全体アーキテクチャ（Hub-and-Spoke） | 明確 |
| コンポーネント責務分離（Portal / Hub / SAM） | 明確 |
| データスキーマ（Command / Control メッセージ JSON） | 定義済み |
| Master Config スキーマ（servers.json） | 定義済み |
| 通信パターン（10-30秒ポーリング） | 決定済み |
| セキュリティモデル（トークン認証 + HTTPS） | 方針決定済み |
| 中断（STOP）の段階的処理フロー | 方針決定済み |
| セッションのライフサイクル（Slack thread ↔ Agent session 1:1対応） | 方針決定済み |

---

## 推奨アクション（実装着手前に決めるべきこと）

| # | 要決定事項 | 推奨 |
|---|---|---|
| 1 | Agent Adapter を node-pty + CLI で作るか、Agent SDK で作るか | **Agent SDK (TypeScript)** を推奨。セッション管理が標準サポートされており、PTY パースの複雑さを回避できる |
| 2 | 使用する Slack ワークスペースとプラン | → ユーザーが決定 |
| 3 | Master Config の GitHub リポジトリ | → ユーザーが決定 |
| 4 | HWID の生成方法 | `/etc/machine-id` + SHA256 ハッシュを推奨（Linux前提） |
| 5 | SAM のデプロイ方式 | systemd + `.env` を推奨（シンプルさ優先の設計思想に合致） |
| 6 | developer_productivity 内の配置場所 | `products/` 配下に新規ディレクトリ（例: `products/llm-bridge/`） |

---

## developer_productivity リポジトリとの適合性

`~/repos/developer_productivity` は以下の構造:
- `products/` — prep-station, dish-up, MDC 等のプロダクトが配置済み
- `projects/` — イニシアチブ（設計ドキュメント等）が配置
- `.devcontainer/` — Docker ベースの開発環境

**配置案**:
- 設計ドキュメント → `projects/various/initiatives/20260505--call-remote-server-llm/`（移動 or シンボリックリンク）
- 実装コード → `products/llm-bridge/` に新規作成（TypeScript / Node.js プロジェクト）
