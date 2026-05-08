# Detailed Design: Call Remote Server LLM Bridge

## 1. コンポーネントと具体的技術のマッピング

抽象設計で定義したコンポーネントに対し、具体的なツール・ライブラリ・実装方針を以下のように決定する。

| 抽象コンポーネント | 具体的な技術・ツール | 役割と選定理由 |
| :--- | :--- | :--- |
| **Bridge Portal** | **Slack App (Bolt for JS)** | ユーザーが日常的に使うスマホ・PCの窓口。スレッド対話、プッシュ通知、スラッシュコマンドを標準活用。 |
| **Relay Hub** | **Slack API (Threads/History)** | 指示とログを保持する中継所。既読・未読管理やスレッド管理の自前実装を不要にするため採用。 |
| **Master Config Repository** | **GitHub (.github/servers.json)** | サーバー定義（HWID、論理名、役割）を永続保存。git history により完全な監査ログを実現。 |
| **SAM (Manager)** | **Node.js (TypeScript)** | サーバー常駐プロセス。`systemd` により管理。Slack API を定期ポーリングする。 |
| **Agent Adapter** | **Claude Agent SDK (TS)** | Claude Code のセッション管理を SDK 経由で直接制御。CLI パースの複雑さを回避。 |
| **Fallback Adapter** | **node-pty** | SDK 非対応エージェント（Gemini CLI 等）向けの PTY エミュレーション。 |

## 2. Agent セッション管理 (Agent Session Management)

### 2.1 セッションのライフサイクル (via Claude Agent SDK)

本システムでは、Claude Agent SDK の **Session** 機能を活用し、Slack スレッドと Agent セッションを 1:1 で対応させる。

```typescript
import { ClaudeSDKClient } from "@anthropic-ai/agent-sdk";

// 1. セッションの開始
const session = await client.sessions.create({
  purpose: "Fix express server bugs"
});
const sessionId = session.id; // Slackスレッドに記録

// 2. セッションの再開 (Resume)
const resumedSession = await client.sessions.retrieve(sessionId);
await resumedSession.execute({ query: "New command from Slack" });
```

### 2.2 セッション ID の保存方法 (Slack Plan Agnostic)

Slack のプラン（無料/有料）に関わらず動作させるため、以下の優先順位で ID を記録する。

1. **第1候補: スレッド先頭メッセージへの追記 (Primary)**:
   - スレッドの親メッセージ（最初の指示）に対し、SAM が `Session ID: [id]` という内容をスレッド内返信の 1 通目として固定的に投稿する。
2. **第2候補: Thread metadata (Optional)**:
   - 有料プラン（Business+）の場合に限り、API 経由で metadata フィールドに session_id を格納する。

## 3. コンフィグと運用の具体化 (Operational Details)

### 3.1 HWID (Hardware ID) の生成
サーバーを一意に識別するための HWID は、以下のロジックで生成する。

- **ソース**: Linux の `/etc/machine-id`
- **生成方法**: `SHA256(/etc/machine-id + "llm-bridge-salt")`
- **意図**: ハードウェアの不変性と、ハブ上での匿名性（機密保持）を両立させる。

### 3.2 Slack App 設定 (OAuth Scopes)
SAM が動作するために必要な最小スコープ：
- `chat:write`: ログや進捗の投稿
- `channels:history`: 指示の取得
- `groups:history`: プライベートチャンネルでの動作
- `reactions:read`: 承認ボタン等の検知（将来用）

### 3.3 SAM のデプロイ (systemd)
シンプルかつ堅牢な運用のための `systemd` ユニットファイル例：

```ini
[Unit]
Description=Server Agent Manager for LLM Bridge
After=network.target

[Service]
Type=simple
User=sam-user
WorkingDirectory=/opt/llm-bridge
EnvironmentFile=/opt/llm-bridge/.env
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## 4. データ構造と通信プロトコル (Data Schema)

リレー・ハブ（Slack）上を流れるメッセージのJSON構造案。

### 4.1 指示 (Command Message)
```json
{
  "target_id": "gpu-srv-1",
  "thread_id": "slack_thread_ts_123456",
  "type": "COMMAND",
  "action": "EXECUTE",
  "content": "Add a new endpoint to the express server"
}
```

## 5. エラーハンドリングと制限 (Error Handling)

- **Rate Limits**: 
  - Slack API (Tier 3): 10秒ポーリングで十分安全。
  - GitHub API: SAM 起動時と設定変更時のみアクセスするため、上限に達する可能性は低い。
- **Retry Logic**: 
  - ネットワーク断時は 30 秒間隔で指数バックオフを伴う再試行を行う。
  - 重大なエラー（Auth Error 等）時は SAM を停止し、systemd の再起動を待つ。
