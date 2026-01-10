# Process-Compose Project Configuration (`project.yaml`)

このディレクトリには、Monolithic DevContainer環境におけるProcess-Composeの実運用設定ファイル `project.yaml` が配置されています。
このファイルを編集することで、開発中に頻繁に起動・停止・再起動するサービスや、実験的なプロセスをProcess-Composeの管理下に置くことができます。

---

## 1. `project.yaml` の編集ガイド

`project.yaml`はdocker-composeライクなYAML形式で記述されます。
`processes`セクションに、Process-Composeが管理するプロセスを定義します。

### よく使う設定項目

*   **`command`**: 実行するコマンド。
*   **`working_dir`**: プロセスが実行されるワーキングディレクトリ。
*   **`availability.restart`**: プロセスが終了した場合の再起動ポリシー。`"no"`で自動再起動しない、`"on-failure"`でエラー終了時のみ再起動など。開発中は`"no"`を推奨します。
*   **`depends_on`**: プロセス間の依存関係を定義します。他のプロセスが起動してから開始するなど。
*   **`environment`**: プロセス固有の環境変数を設定します。
*   **`ports`**: コンテナのポートをホストに公開します（SupervisordのWeb UIなど、永続的なサービスはdocker-compose.ymlで公開）。

### 例

```yaml
version: "0.5"

log_location: /tmp/process-compose-${USER}.log
log_level: info

processes:
  your-custom-service:
    command: "npm run dev"
    working_dir: "/home/<一般ユーザー>/hagevvashi.info-dev-hub/repos/your-project"
    availability:
      restart: "no" # エラーを見たいので自動再起動しない
    environment:
      - YOUR_ENV_VAR=some_value
```

---

## 2. 設定変更後の反映方法

`project.yaml`を編集しただけでは、Process-Composeに設定が反映されません。以下のコマンドでProcess-Composeサービスを再起動する必要があります。

```bash
# Process-Composeサービスを再起動します
# s6-overlayがPID 1を保護しているため、コンテナは停止しません。
s6-svc -t /run/service/process-compose
```
このコマンドはProcess-Composeサービスを停止・開始しますが、コンテナ自体は停止しませんので、安心して実行できます。

---

## 3. TUI (ターミナルユーザーインターフェース) の操作

Process-Composeは強力なTUIを提供します。

### TUIの起動

`s6-svc -u /run/service/process-compose` コマンドでProcess-Composeサービスを起動すると、ターミナルにTUIが表示されます。

### 主要なTUIショートカット

*   `Tab`: プロセス一覧とログ表示の切り替え
*   `↑`/`↓`: プロセス選択
*   `s`: 選択したプロセスを起動 (Start)
*   `r`: 選択したプロセスを再起動 (Restart)
*   `k`: 選択したプロセスを停止 (Kill)
*   `l`: 選択したプロセスのログを表示
*   `q`または`Ctrl+C`: TUIを終了します。Process-Composeサービス自体はs6-overlayによって管理されているため、TUIを終了してもプロセスはバックグラウンドで動き続ける場合があります。サービス自体を停止したい場合は`s6-svc -d /run/service/process-compose`を使用します。

---

## 4. Supervisord との使い分け

Process-ComposeとSupervisordは、それぞれ異なる得意分野を持つプロセス管理ツールです。適切に使い分けることで、開発効率を最大化できます。

| 観点 | Process-Compose | Supervisord |
|------|-----------------|-------------|
| **管理対象** | 開発中に頻繁に起動・停止・再起動するプロセス（Webサーバー, APIサーバー, テストなど） | 安定稼働が必要なプロセス（code-server, DBなど） |
| **UI** | ターミナルUI (TUI) | Web UI (http://localhost:9001) |
| **設定形式** | YAML形式 (docker-composeライク) | INI形式 |
| **自動再起動** | YAMLで設定可能 | `autorestart=true` で設定可能 |
| **特性** | 開発中の柔軟性、高速なフィードバック、依存関係定義 | 堅牢性、永続性、基盤プロセス管理 |

### 推奨される使い分け

*   **Process-Composeで管理すべきプロセス**:
    *   `difit`: 開発中に頻繁に起動・停止する開発支援ツール。
    *   フロントエンドの`vite dev server`や、バックエンドのAPIサーバー（ホットリロード対象）。
    *   一時的に実行するスクリプトや実験的なサービス。
    *   依存関係をYAMLで定義したいマイクロサービス群。
*   **Supervisordで管理すべきプロセス**:
    *   `code-server`: 開発環境の基盤であり、常に起動しているべきサービス。
    *   データベース（PostgreSQL, Redisなど）: 安定稼働が求められるミドルウェア。
    *   Supervisord自体やProcess-Composeサービスなど、他のプロセス管理ツールの基盤となるもの。

---

詳細なアーキテクチャやガイドラインは `foundations/onboarding/s6-hybrid-process-management-guide.md` を参照してください。
