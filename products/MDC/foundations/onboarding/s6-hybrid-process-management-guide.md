# s6-overlay + Supervisord + Process-Compose ハイブリッドプロセス管理ガイド

このドキュメントでは、Monolithic DevContainer環境におけるプロセス管理のアーキテクチャ、設計思想、そして各ツールの使い方と使い分けについて説明します。

---

## 1. プロセス管理アーキテクチャの概要

本DevContainer環境では、以下のハイブリッド構成でコンテナ内のプロセスを管理しています。

```
PID 1: s6-overlay (init + プロセス監視)
  ├─ s6-svscan (サービススキャナー)
  │   ├─ docker-entrypoint (初期化スクリプト・oneshot)
  │   │   └─ Supervisord/Process-Compose 設定の検証とフォールバック
  │   │
  │   ├─ supervisord (longrun・常時起動)
  │   │   ├─ [inet_http_server] → Web UI (port 9001)
  │   │   ├─ code-server (必須プロセス)
  │   │   └─ その他の安定稼働プロセス
  │   │
  │   └─ process-compose (longrun・オプション起動)
  │       ├─ TUI (port 8080 API)
  │       ├─ 開発中のサービス (例: vite dev server)
  │       └─ 実験的プロセス
  │
  └─ zombie reaping (ゾンビプロセス回収)
```

### 各ツールの役割

*   **s6-overlay**:
    *   コンテナのPID 1として動作し、ゾンビプロセスの回収、プロセスの監視、自動再起動を担当します。
    *   SupervisordやProcess-Composeがクラッシュしても、s6-overlayが自動的に再起動するため、**コンテナ自体が停止することはありません。**
    *   開発者は通常、s6-overlayを直接操作することはほとんどありません。
*   **Supervisord**:
    *   安定稼働が求められる基盤プロセス（`code-server`、データベースなど）を管理します。
    *   Web UIを提供し、ブラウザ経由でプロセスの状態確認や操作が可能です。
    *   設定ファイルは`workloads/supervisord/project.conf`です。
*   **Process-Compose**:
    *   開発中に頻繁に起動・停止・再起動する開発用プロセス（フロントエンドのDevサーバー、APIサーバー、`difit`など）を管理します。
    *   ターミナル上でリッチなTUIを提供し、素早くプロセスを操作できます。
    *   設定ファイルは`workloads/process-compose/project.yaml`です。

---

## 2. プロセス管理のワークフロー

### コンテナ起動時

1.  **s6-overlayがPID 1として起動**し、サービスの監視を開始します。
2.  **`docker-entrypoint`サービスが実行**されます。
    *   このスクリプトは、`workloads/supervisord/project.conf`および`workloads/process-compose/project.yaml`の存在と構文を検証します。
    *   検証に成功した場合、これらの実運用設定ファイルへのシンボリックリンクを`/etc/supervisor/supervisord.conf`および`/etc/process-compose/process-compose.yaml`に作成します。
    *   **検証に失敗した場合（設定ファイルが見つからない、または構文エラー）**、最小限のプロセス（`code-server`のみ）が定義された**`seed.conf`**、またはプレースホルダーのみの**`seed.yaml`**へフォールバックします。
3.  **`supervisord`サービスが起動**します（`docker-entrypoint`サービス完了後）。
    *   `project.conf`または`seed.conf`に従って、管理対象プロセスを起動します。
    *   通常、`code-server`が自動起動します。
4.  **`process-compose`サービスが起動**します（`docker-entrypoint`サービス完了後）。
    *   `project.yaml`または`seed.yaml`に従って、管理対象プロセスを起動します。`project.yaml`の設定によっては自動起動しないこともあります。

---

## 3. 各ツールの操作方法と使い分け

### 3.1 Supervisord

安定稼働する基盤プロセスを管理し、Web UIで全体の状態を把握するのに適しています。

*   **Web UIでの操作**:
    1.  ブラウザで `http://localhost:9001` にアクセスします。
    2.  デフォルトのユーザー名 `admin`、パスワード `admin` でログインします。
    3.  プロセス一覧の確認、起動・停止・再起動、ログの確認が可能です。
*   **CLIでの操作 (コンテナ内)**:
    ```bash
    # プロセス状態の確認
    supervisorctl status
    # 特定のプロセスを起動/停止/再起動
    supervisorctl start code-server
    supervisorctl stop difit
    supervisorctl restart your-service
    # 設定ファイルの変更をSupervisordに読み込ませる
    supervisorctl reread
    # 変更をSupervisordに適用する
    supervisorctl update
    ```
*   **Supervisord自体の再起動**:
    `project.conf`を編集し、Supervisord自体に設定変更を反映させたい場合、`s6-overlay`の恩恵により安全にSupervisordサービスを再起動できます。
    ```bash
    s6-svc -t /run/service/supervisord
    ```
    **※この操作を行っても、コンテナ自体は停止しません。**

### 3.2 Process-Compose

開発中のプロセスを柔軟に管理し、TUIで素早く操作・ログ確認するのに適しています。

*   **TUIの起動 (コンテナ内)**:
    Process-Composeサービスを起動します。
    ```bash
    s6-svc -u /run/service/process-compose
    ```
    ターミナルにProcess-ComposeのTUIが表示されます。
*   **TUIでの操作**:
    *   `Tab`: プロセス一覧とログ表示の切り替え
    *   `↑`/`↓`: プロセス選択
    *   `s`: 選択したプロセスを起動 (Start)
    *   `r`: 選択したプロセスを再起動 (Restart)
    *   `k`: 選択したプロセスを停止 (Kill)
    *   `l`: 選択したプロセスのログを表示
    *   `q`または`Ctrl+C`: TUIを終了します。
*   **Process-Compose自体の再起動**:
    `project.yaml`を編集し、Process-Compose自体に設定変更を反映させたい場合も、`s6-overlay`の恩恵により安全に再起動できます。
    ```bash
    s6-svc -t /run/service/process-compose
    ```
    **※この操作を行っても、コンテナ自体は停止しません。**

### 3.3 使い分けガイドライン

| 用途 | 推奨ツール | 理由 |
|------|-----------|------|
| **`code-server`** | Supervisord | 開発環境の基盤であり、常時安定稼働が求められるため。Web UIで監視。 |
| **データベース (PostgreSQL, Redisなど)** | Supervisord | 安定稼働が求められるミドルウェアのため。 |
| **`difit`** | Process-Compose | 開発中に起動・停止する機会が多い開発支援ツールのため。TUIでの素早い操作に適しています。 |
| **フロントエンド `vite dev server`** | Process-Compose | ホットリロードなど、開発中のフィードバックが頻繁に発生するため。TUIでのログ確認に適しています。 |
| **バックエンド APIサーバー** | Process-Compose | ホットリロード、デバッグなど、開発中のプロセス操作が多いため。 |
| **実験的プロセス** | Process-Compose | 一時的に試したいプロセスやスクリプトのため。YAMLで手軽に定義できます。 |
| **プロセス管理ツール自身 (`supervisord`, `process-compose`)** | s6-overlay | PID 1としてこれらを監視・自動再起動するため。 |

---

## 4. フォールバック時の対処法

`docker-entrypoint.sh`による設定ファイル検証の結果、`workloads/supervisord/project.conf`または`workloads/process-compose/project.yaml`に問題がある場合、コンテナは以下のような挙動を示します。

1.  **コンテナは停止しません**。
2.  問題のあった設定は無視され、**最小限の設定 (`seed.conf`/`seed.yaml`) でプロセス管理ツールが起動します。**
    *   `supervisord`の場合、`code-server`のみが起動します。
    *   `process-compose`の場合、プレースホルダープロセスのみが起動します。
3.  コンテナのログ (`docker logs <container_name>`) に、**フォールバックモードになった旨の警告メッセージ**と、**修正方法**が表示されます。

### 復旧手順

1.  **コンテナのログを確認**: `docker logs <container_name>` を実行し、どの設定ファイルでエラーが発生したかを確認します。
2.  **設定ファイルを修正**: 警告メッセージに示されたパス (`workloads/supervisord/project.conf` または `workloads/process-compose/project.yaml`) のファイルを修正します。
    *   構文エラーがないか、必要なセクションが欠けていないかなどを確認してください。
3.  **プロセス管理ツールを再起動**:
    *   `supervisord`の設定を修正した場合: `s6-svc -t /run/service/supervisord`
    *   `process-compose`の設定を修正した場合: `s6-svc -t /run/service/process-compose`
    *   **※これらをコンテナ内で実行すると、修正された設定が読み込まれ、意図したプロセスが起動します。**

---

## 5. 設計思想：堅牢性と柔軟性の両立

このハイブリッドプロセス管理アーキテクチャは、以下の設計思想に基づいています。

*   **PID 1の保護**: コンテナの安定性を最優先し、いかなるプロセス管理ツールの問題でもコンテナが落ちないようにします。
*   **開発体験の向上**: 開発者がプロセス管理の複雑さに煩わされることなく、コード開発に集中できるようにします。
*   **堅牢なフォールバック**: 設定ミスがあってもコンテナが停止せず、デバッグ可能な最小限の環境を提供します。
*   **ツールの選択肢**: 開発者の好みやユースケースに合わせて、Web UIとTUIの最適なツールを選択できるようにします。
*   **スケーラビリティ**: 将来的に新たなサービスやプロセスが追加された場合でも、容易に管理下に置ける柔軟性を提供します。

---
