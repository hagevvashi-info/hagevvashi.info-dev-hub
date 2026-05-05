# Architecture Diagrams: Call Remote Server LLM Bridge

## 1. システム全体構成図 (System Overview & Deployment)
ネットワーク隔離を越えて、複数の「個性あるサーバー」を指名操作する全体像。

```mermaid
graph TD
    subgraph "Local Devices (Mac / Smartphone)"
        Portal[Bridge Portal]
    end

    subgraph "Internet (Public Relay)"
        Hub[Relay Hub / Shared Registry & Queues]
    end

    subgraph "Remote Server A (Role: GPU Machine)"
        ConfigA[Local Config: ID='gpu-srv']
        SAMA[SAM]
        AgentA[Claude Code]
    end

    subgraph "Remote Server B (Role: Storage Server)"
        ConfigB[Local Config: ID='file-srv']
        SAMB[SAM]
        AgentB[Claude Code]
    end

    Portal -- "1. Discovery (Who is online?)" --> Hub
    Portal -- "2. Dispatch (To 'gpu-srv')" --> Hub

    SAMA -- "A. Heartbeat (I am 'gpu-srv')" --> Hub
    SAMA -- "B. Fetch Commands for 'gpu-srv'" --> Hub

    SAMB -- "A. Heartbeat (I am 'file-srv')" --> Hub
    SAMB -- "B. Fetch Commands for 'file-srv'" --> Hub

    SAMA <--> AgentA
    SAMB <--> AgentB
```

## 2. コンポーネント詳細図 (Component Diagram)
ソフトウェア内部の責務と、論理サーバー名（Logical ID）によるフィルタリングの仕組み。

```mermaid
graph TD
    subgraph "Bridge Portal"
        UI[UI: Server Selector]
        Client[Hub Client]
    end

    subgraph "Relay Hub (Single Source of Truth)"
        Registry{{Shared Server Registry}}
        Queues[(Command Queues per ID)]
        Logs[(Execution Logs)]
    end

    subgraph "Any Remote Server (Generic SAM)"
        Config[Local Config: LOGICAL_SERVER_NAME]
        SAM[Server Agent Manager]
        AA[Agent Adapter / PTY]
        Agent[LLM Agent]
    end

    UI -- "1. Get Active Roles" --> Registry
    UI -- "2. Select 'GPU-Box'" --> Client
    Client -- "3. Push Command" --> Queues

    SAM -- "A. Register as LOGICAL_SERVER_NAME" --> Registry
    SAM -- "B. Fetch for LOGICAL_SERVER_NAME" --> Queues

    SAM <--> AA <--> Agent
    AA -- "C. Stream Logs" --> Logs
    Logs -. Read .- UI
```

## 3. シーケンス図 (Sequence Diagram)
...（以下、前回のシーケンス図を維持）


```mermaid
sequenceDiagram
    participant U as Bridge Portal (Local)
    participant R as Shared Registry (Hub)
    participant I as Server Inbox (Hub)
    participant S as SAM (Remote Server)
    participant A as LLM Agent

    Note over S,R: 1. サーバーの存在証明 (Heartbeat)
    S->>R: Update My Status (ID: 'gpu-server', Status: 'Ready')
    
    Note over U,R: 2. サーバー発見 (Discovery)
    U->>R: Fetch Active Server Roles
    R-->>U: List: ['gpu-server', 'storage-box']
    
    Note over U,I: 3. 指示の投函 (Command Submission)
    U->>I: Post Command (Target: 'gpu-server', Action: 'Fix Bug')
    
    Note over S,I: 4. 指示の取得 (Polling)
    S->>I: Fetch My Inbox (Target: 'gpu-server')
    I-->>S: Found: 'Fix Bug'
    
    Note over S,A: 5. 実行とフィードバック (Execution)
    S->>A: Start Agent
    loop Processing
        A->>S: Logs/Thoughts
        S->>I: Update Thread Logs
        I-->>U: Sync View
    end
```
