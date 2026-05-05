# Architecture Diagrams: Call Remote Server LLM Bridge

## 1. システム全体構成図 (System Overview & Deployment)
GitHub（マスター設定）と Slack（指示・制御）の責務分離による全体構成。

```mermaid
graph TD
    User((User / Admin))
    
    subgraph "Local Devices (Mac / Smartphone)"
        Portal[Bridge Portal<br/>Slack App]
    end

    subgraph "Internet - Configuration Layer"
        GitHubRepo["GitHub Repository<br/>(.github/servers.json)<br/>Master Config<br/>+ git history"]
    end

    subgraph "Internet - Control Layer"
        SlackHub["Slack Channels<br/>Command Inbox<br/>+ Thread-based Dialog"]
    end

    subgraph "Remote Server A"
        SAMA[SAM]
        AgentA[Claude Code]
    end

    subgraph "Remote Server B"
        SAMB[SAM]
        AgentB[Claude Code]
    end

    User -- "1. Update Master Config" --> GitHubRepo
    Portal -- "2. Pull Server Definitions" --> GitHubRepo
    
    SAMA -- "A. Pull My HWID & Identity" --> GitHubRepo
    SAMA -- "B. Poll Command Threads" --> SlackHub
    
    SAMB -- "A. Pull My HWID & Identity" --> GitHubRepo
    SAMB -- "B. Poll Command Threads" --> SlackHub
    
    Portal -- "3. Post Commands & Reply to Results" --> SlackHub
```

## 2. コンポーネント詳細図 (Component Diagram)
GitHub（Master Config）と Slack（Command Inbox）による責務分離構成。

```mermaid
graph TD
    subgraph "Bridge Portal (Slack App)"
        UI["UI: Server List<br/>+ Command Interface"]
        SlackClient[Slack Bot Client]
    end

    subgraph "GitHub Repository (Configuration)"
        Master["Master Config<br/>servers.json"]
        GitHistory["Git History<br/>(Audit Log)"]
    end

    subgraph "Slack Channels (Command Hub)"
        CommandInbox["Command Inbox<br/>(Multiple Channels)"]
        Threads["Thread-based Dialog<br/>(Commands & Results)"]
    end

    subgraph "Any Remote Server (Generic SAM)"
        LocalID["HWID<br/>(Hardware Auth ID)"]
        SAM[Server Agent Manager]
        AA[Agent Adapter]
        Agent[LLM Agent]
    end

    UI -- "1. Load Server Definitions" --> Master
    SlackClient -- "2. Post Commands in Threads" --> Threads

    SAM -- "A. Fetch Identity by HWID" --> Master
    SAM -- "B. Poll Command Threads" --> Threads
    SAM -- "C. Cache Locally" --> LocalID
    
    SAM <--> AA <--> Agent
    AA -- "D. Stream Results to Thread" --> Threads
    Threads -. "Monitor Results" .- UI
    
    Master -- "Git Track" --> GitHistory
```

## 3. シーケンス図 (Sequence Diagram)
GitHub で Master Config を管理し、Slack でコマンド実行・対話するフロー。

```mermaid
sequenceDiagram
    actor U as User (Admin)
    participant G as GitHub Repo<br/>Master Config
    participant P as Bridge Portal<br/>(Slack App)
    participant Slack as Slack Channels
    participant S as SAM<br/>(Remote Server)

    Note over U,G: 1. Master Config 管理
    U->>G: Update servers.json (add/modify server)
    Note right of G: git history に記録

    Note over S,G: 2. SAM のアイデンティティ確認
    S->>G: Fetch Master Config
    Note right of S: HWID で自分のスレッドチャンネルを特定
    
    Note over P,G: 3. Portal のサーバー一覧表示
    P->>G: Pull Master Config
    Note left of P: UI に available servers を表示

    Note over P,Slack: 4. コマンド依頼・実行フロー
    P->>Slack: Post command in thread (target: gpu-srv-1)
    S->>Slack: Poll thread messages
    S->>S: Run LLM Agent in new session
    S->>Slack: Reply in thread with result
    
    Note over P,Slack: 5. 対話的な継続実行
    P->>Slack: Reply to result with additional command
    S->>Slack: Fetch reply (same thread)
    S->>S: Continue agent session
    S->>Slack: Reply with next result
```
