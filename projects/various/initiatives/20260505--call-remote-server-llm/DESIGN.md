# Detailed Design: Call Remote Server LLM Bridge

## 1. コンポーネントと具体的技術のマッピング

抽象設計で定義したコンポーネントに対し、具体的なツール・ライブラリ・実装方針を以下のように決定する。

| 抽象コンポーネント | 具体的な技術・ツール | 役割と選定理由 |
| :--- | :--- | :--- |
| **Bridge Portal** | **Slack App (Bolt for JS)** | ユーザーが日常的に使うスマホ・PCの窓口。スレッド対話、プッシュ通知、スラッシュコマンドを標準活用。 |
| **Relay Hub** | **Slack API (Threads/History)** | 指示とログを保持する中継所。既読・未読管理やスレッド管理の自前実装を不要にするため採用。 |
| **Master Config Repository** | **GitHub (.github/servers.json)** | サーバー定義（HWID、論理名、役割）を永続保存。git history により完全な監査ログを実現。Slack ハブでは 90 日制限のため不採用。 |
| **SAM (Manager)** | **Node.js (TypeScript)** | サーバー常駐プロセス。10-30秒間隔で Slack API を叩き、自分宛てのメンション/メッセージを取得する。 |
| **Agent Adapter** | **node-pty** | LLMエージェントを擬似ターミナル(PTY)で実行。色情報や対話プロンプトを壊さずキャプチャする。 |
| **LLM Agent** | **Claude Code / Gemini CLI** | 実際の作業を実行する自律型エンジニアエージェント。 |

## 2. Agent セッション管理 (Agent Session Management)

### 2.0 セッションのライフサイクル

本システムでは、Claude Code などのエージェントが持つ **session_id** 機能を活用し、Slack スレッドと Agent セッションを 1:1 で対応させる。

```
[Slack Thread ts: 1234567890.123456]
        ↓ (initial command)
[SAM: Launch Claude Code]
        ↓
[Agent Session ID: sess_abc123 returned]
        ↓ (stored in thread)
[User replies in thread]
        ↓
[SAM: `/resume sess_abc123`]
        ↓
[Agent: Previous context restored]
        ↓
[Continue execution with new input]
```

**Key Points**:
- Agent のコンテキスト（ファイル状態、実行結果等）はエージェント自体が session_id で管理
- SAM は session_id の保存・取得のみを責務とする
- スレッド内のメッセージ metadata または pinned message で session_id を記録

### 2.1 セッション ID の保存方法

**オプション A: Thread metadata（推奨）**
```
Slack thread ts: 1234567890.123456
├── metadata: {
│     "session_id": "sess_abc123",
│     "agent": "claude-code",
│     "target_server": "gpu-srv-1"
│   }
└── messages: [...]
```

**オプション B: Thread first message に pin**
```
[First message in thread]
"session_id: sess_abc123"
↓ pin this message
```

---

## 2. データ構造と通信プロトコル (Data Schema)

リレー・ハブ（Slack）上を流れるメッセージのJSON構造案。

### 2.1 指示 (Command Message)
```json
{
  "target_id": "gpu-srv-1",
  "thread_id": "slack_thread_ts_123456",
  "type": "COMMAND",
  "action": "EXECUTE",
  "content": "Add a new endpoint to the express server",
  "options": {
    "agent": "claude-code",
    "cwd": "/home/user/project"
  }
}
```

### 2.2 制御 (Control Message)
```json
{
  "target_id": "gpu-srv-1",
  "type": "CONTROL",
  "action": "STOP", // or "APPROVE"
  "ref_msg_id": "msg_001"
}
```

## 3. コンフィグ管理と所有権 (Config Management & Ownership)

### 3.0 設計判断：Master Config の保存先

#### 設計の意思 (Design Intent)
Master Config（セントラル・レジストリ）は、本システムの「**唯一の真実のソース（Single Source of Truth）**」である。このため、以下の要件が必須：
1. **長期保存**：90日以上の履歴管理
2. **バージョン管理**：いつ誰が何を変更したかの追跡可能性
3. **確実性**：システムの根幹を支えるため、信頼できるインフラが必須

Slack 無料版は 90 日制限のため、単独での運用は不適切。そこで **GitHub リポジトリ** を Master Config の永続保存先とし、Slack は「**指示・制御・ログ・通知**」に特化させることで、両者の強みを活用するハイブリッド構成を採用する。

#### トレードオフの承認 (Trade-offs Accepted)

| トレードオフ | 受け入れ内容 | 対策 |
|---|---|---|
| **GitHub への依存増加** | Master Config 取得に GitHub API が必須 | SAM はローカルキャッシュを保持。GitHub 再接続時に差分更新 |
| **GitHub ダウン時の影響** | Master Config が取得不可 | SAM は最後の正常なキャッシュから継続稼働。通知は Slack 経由 |
| **実装複雑度の増加** | 2つのシステム（GitHub + Slack）の連携が必要 | 責務分離が明確なため、各実装は単純 |

#### 採用された構成

```
┌─────────────────────────────────────────┐
│  GitHub Repository                      │
│  (.github/servers.json)                 │
│  → Master Config 長期保存・バージョン管理 │
└─────────────────────────────────────────┘
           ↑ Pull (定期)
           │
    ┌──────┴────────┐
    │               │
  Portal          SAM
    │               │
    └───────────────┘
           ↓ Read/Write
┌─────────────────────────────────────────┐
│  Slack Channels                         │
│  → 指示・制御・ログ・通知               │
└─────────────────────────────────────────┘
```

### 3.1 セントラル・レジストリによる一元管理
- **管理の所在**: **GitHub リポジトリ** の `.github/servers.json` が全ての真実（名前と役割の定義）を保持する。
- **具体的な実装**: GitHub Repository ファイルで JSON 形式の設定を保存。git history により完全な監査ログが自動保持される。
- **定義方法**: ユーザーがブリッジ・ポータルを通じて、「HWID: 0x123 のサーバーは `gpu-srv-1` という名前で、このプロジェクトを担当する」といった定義を事前に行う。ポータルが GitHub API 経由で設定を更新（Pull Request or Direct Commit）。
- **サーバー側の動作**: 各サーバーの SAM は、起動時に自分の **HWID (Hardware ID / Auth Key)** を提示して GitHub に問い合わせ（Fetch）、「自分は何者として振る舞うべきか」というアイデンティティを取得する。

### 3.2 Master Config スキーマ

**保存先**: GitHub リポジトリ `.github/servers.json`

**形式**: JSON

```json
{
  "version": "1.0",
  "servers": {
    "gpu-srv-1": {
      "hwid": "0x123abc456def",
      "display_name": "GPU Training Server",
      "role": "training",
      "slack_channel_id": "C0123456789",
      "enabled": true
    },
    "home-nas": {
      "hwid": "0x789ghi012jkl",
      "display_name": "Home NAS Storage",
      "role": "storage",
      "slack_channel_id": "C9876543210",
      "enabled": true
    }
  },
  "updated_at": "2026-05-06T10:30:45Z",
  "updated_by": "user@example.com"
}
```

**スキーマ詳細**：
- `hwid`: サーバーの物理的・論理的な不変ID（認証キー）
- `display_name`: ユーザーに表示される名前
- `role`: サーバーの役割（`training`, `storage`, `worker` 等）
- `slack_channel_id`: 指示・結果・対話用のチャンネルID。SAM はこのチャンネルをポーリングし、スレッド単位で依頼を受け取る
- `enabled`: サーバーが有効か無効か

### 3.3 アイデンティティ取得のフロー
1. **HWIDの提示 (SAM side)**: サーバー固有の不変なIDを GitHub API へ送信。
2. **GitHub から Master Config を取得**: GitHub API `GET /repos/{owner}/{repo}/contents/.github/servers.json`
3. **マスター設定の解析**: JSON をパースし、HWID に対応する論理名を検索。
4. **名前の割り当て (GitHub側)**: HWID に対応する論理名（`gpu-srv-1`）を特定。
5. **ポーリング開始**: 取得した論理名に基づいて、Slack で自分専用のインボックス（キュー）の監視を開始する。

### 3.4 API 呼び出し仕様

#### SAM による取得

```typescript
import { Octokit } from "@octokit/rest";

const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN
});

// 1. GitHub から Master Config を取得
const response = await octokit.repos.getContent({
  owner: process.env.GITHUB_OWNER,
  repo: process.env.GITHUB_REPO,
  path: ".github/servers.json"
});

const masterConfig = JSON.parse(
  Buffer.from(response.data.content, "base64").toString()
);

// 2. 自分の HWID でレジストリを検索
const myRole = Object.entries(masterConfig.servers).find(
  ([name, config]) => config.hwid === process.env.HWID
);

const [logicalName, serverConfig] = myRole;
console.log(`My role: ${logicalName}`);

// 3. ローカルキャッシュに保存（GitHub 接続不可時の対策）
fs.writeFileSync(
  path.join(os.homedir(), ".sam", "servers.cache.json"),
  JSON.stringify(masterConfig)
);

// 4. 自分の Slack チャンネルをポーリング開始
const slackChannelId = serverConfig.slack_channel_id;
setInterval(async () => {
  const messages = await slackClient.conversations.history({
    channel: slackChannelId,
    limit: 10
  });
  // スレッドとして新しい指示を取得し処理
}, 10000); // 10秒ごと
```

#### Portal による更新

```typescript
// 1. 現在の Master Config を取得
const response = await octokit.repos.getContent({
  owner: process.env.GITHUB_OWNER,
  repo: process.env.GITHUB_REPO,
  path: ".github/servers.json"
});

const masterConfig = JSON.parse(
  Buffer.from(response.data.content, "base64").toString()
);

// 2. 新しいサーバーを追加
masterConfig.servers['new-server'] = {
  hwid: '0xnewid',
  display_name: 'New Server',
  role: 'worker',
  enabled: true
};

// 3. GitHub にプッシュ（またはコミット）
await octokit.repos.createOrUpdateFileContents({
  owner: process.env.GITHUB_OWNER,
  repo: process.env.GITHUB_REPO,
  path: ".github/servers.json",
  message: "chore: register new server 'new-server'",
  content: Buffer.from(JSON.stringify(masterConfig, null, 2)).toString("base64"),
  sha: response.data.sha  // 競合検出
});
```


## 4. 机上実装：ロジックフロー (Implementation Logic)

### 4.1 アイデンティティの取得
1. SAM起動時、自身の **HWID**（または認証トークン）を提示してリレー・ハブの **セントラル・レジストリ** に問い合わせる。
2. レジストリから自分に割り当てられた `LOGICAL_SERVER_NAME` と役割設定を取得する。
3. 取得した名前でハブへのポーリング（指示待ち）を開始する。

### 3.2 Agent Adapter による Session 管理と I/O リレー (Agent Adapter: Session & I/O Bridge)

#### 初回実行（新セッション作成）
```typescript
// 1. Claude Code を起動（新セッション）
const agentProcess = spawn('claude-code', ['--json'], {
  stdio: ['pipe', 'pipe', 'pipe']
});

const pty = new PTY({
  name: 'xterm-256color',
  cols: 80,
  rows: 24
});

// 2. 初期コマンドを送信
pty.write('add a new endpoint to the express server\n');

// 3. session_id を取得（Agent の出力から解析）
// Claude Code は初回実行時に session_id を stdout に出力
// 例：`Session ID: sess_abc123`
let sessionId = null;
pty.onData((data) => {
  const match = data.toString().match(/Session ID: (sess_[a-z0-9]+)/);
  if (match) {
    sessionId = match[1];
    // session_id を Slack スレッド metadata に保存
    await saveSessionIdToSlackThread(threadTs, sessionId);
  }
});

// 4. 出力を Slack スレッドに返信
pty.onData((data) => {
  bufferOutput += data.toString();
  // 一定時間またはバッファサイズで区切って投稿
  if (bufferOutput.length > 1000 || timeSinceLastPost > 5000) {
    await postToSlackThread(threadTs, bufferOutput);
    bufferOutput = '';
  }
});
```

#### 継続実行（セッション再開）
```typescript
// 1. Slack スレッドから session_id を取得
const sessionId = await getSessionIdFromSlackThread(threadTs);

// 2. Claude Code セッションを再開
const agentProcess = spawn('claude-code', [
  '--resume', sessionId,  // 既存セッションを再開
  '--json'
], {
  stdio: ['pipe', 'pipe', 'pipe']
});

// 3. スレッドの新規返信（追加コマンド）を Agent へ入力
const newCommand = await getLatestReplyFromSlack(threadTs);
pty.write(newCommand + '\n');

// 4. Agent の出力を Slack スレッドに返信（上記と同じ）
```

#### 中断（STOP）の処理
```typescript
// SAM が Slack から STOP 指示を受け取ったら
const stopMessage = await getStopCommandFromSlack(threadTs);

if (stopMessage) {
  // Agent プロセスを強制停止
  agentProcess.kill('SIGINT');  // 1回目：graceful
  setTimeout(() => {
    if (!agentProcess.killed) {
      agentProcess.kill('SIGKILL');  // 2回目：強制
    }
  }, 5000);
  
  // Slack スレッドに中断通知
  await postToSlackThread(threadTs, '⏹ Agent execution stopped by user');
}
```

### 3.3 透過的な入出力リレー (The Bridge Logic)
- **出力のキャプチャ**: `node-pty` の `onData` イベントで流れてくるバイナリ/テキストをバッファリングし、意味のある塊（行単位や数秒ごと）で Slack スレッドに返信（投稿）する。
- **入力の転送**: Slackスレッドにユーザーが返信した内容を、SAMが検知して `pty.write(input + "\n")` でエージェントに流し込む。
- **セッション保持**: session_id により、スレッド内での複数回の実行が同一セッションコンテキストで継続される。

### 3.4 中断 (STOP) の優先処理
1. SAMはエージェントを実行しつつ、並行して「中断フラグ」をチェックし続ける。
2. Slackから `action: STOP` を受信した瞬間、`pty.kill('SIGINT')` を呼び出す。
3. 反応がない場合、段階的に `SIGKILL` へ移行し、プロセスを確実に停止させる。

## 4. セキュリティ設計の実装

### 4.1 認証・認可
- **認証**: Slack の Bot Token および Signing Secret を使用。
- **認可**: サーバー側で、あらかじめ許可した論理ID以外の指示は無視するホワイトリスト制を採用。
- **暗号化**: Slack API (HTTPS) による輸送中の暗号化に依存する。

### 4.2 セッション ID の取り扱い
- **保存**: session_id は Slack スレッド metadata に保存（Slack 暗号化）
- **アクセス制御**: session_id を持つスレッドへのアクセスは、Slack チャンネルのアクセス権限に準ずる
- **有効期限**: session_id の有効期限は Claude Code 側で管理（SAM は無視）
