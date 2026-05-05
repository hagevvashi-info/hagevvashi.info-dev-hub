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
    working_dir: "/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/repos/your-project"
    availability:
      restart: "no" # エラーを見たいので自動再起動しない
    environment:
      - YOUR_ENV_VAR=some_value
```

---

## 1.5. 重要: 環境変数の罠 (`${HOME}`問題)

### 問題: ${HOME}が/rootになる（解決済み）

process-composeは`s6-setuidgid`で一般ユーザー（`${UNAME}`）として起動されますが、
`s6-setuidgid`は**UID/GIDのみ変更**し、**HOMEは変更しません**。

そのため、明示的な設定なしでは`${HOME}=/root`のままになります。

**検証結果（2026-01-21）**:
- process-composeプロセス内: `HOME=/root`
- 子プロセス（npm等）内: `HOME=/root`（親の環境変数を継承）

### 影響範囲

以下のようなツールが影響を受けます：
- **npm**: `~/.npm`、`~/.npmrc`など
- **Python**: `~/.cache/`、`~/.local/`など
- **Git**: `~/.gitconfig`など
- あらゆる`${HOME}`や`~`を使うツール

### 解決策（実装済み）

**根本的解決（2026-01-21実装）**:

process-compose起動スクリプト([.devcontainer/s6-rc.d/process-compose/run](../../.devcontainer/s6-rc.d/process-compose/run))で、
明示的に`export HOME=/home/${UNAME}`を設定しています。

これにより、process-composeおよび**全ての子プロセス**で`${HOME}`が正しく使えます。

```bash
# .devcontainer/s6-rc.d/process-compose/run 内
export HOME=/home/${UNAME}
exec s6-setuidgid ${UNAME} /usr/local/bin/process-compose ...
```

**結果**: `${HOME}`や`~`をそのまま使えます：

```yaml
# 良い例（どちらでもOK）
working_dir: "/home/${UNAME}/repos/..."  # ✅ 明示的
working_dir: "${HOME}/repos/..."         # ✅ export HOME のおかげで動作
working_dir: "~/repos/..."               # ✅ export HOME のおかげで動作
```

### 検証方法

`env-validator`プロセスで常時監視しています:

```bash
process-compose -p 4040 process logs env-validator
```

**期待される出力**:
```
=== Environment Variables Validation ===
HOME: /home/<user>
...
✅ HOME is correct
```

**警告が出た場合**:
```
⚠️ WARNING: HOME=/root (expected /home/<user>)
```

この警告が出た場合、起動スクリプトの`export HOME=/home/${UNAME}`が削除されている可能性があります。
即座に[.devcontainer/s6-rc.d/process-compose/run](../../.devcontainer/s6-rc.d/process-compose/run)を確認してください。

### 重要な注意事項

**絶対に削除しないこと**:

起動スクリプトの`export HOME=/home/${UNAME}`を削除すると、以下の問題が発生します：
- npm: `~/.npm`が`/root/.npm`を参照
- Python: `~/.cache`が`/root/.cache`を参照
- Git: `~/.gitconfig`が`/root/.gitconfig`を参照

env-validatorの警告メッセージで即座に検出できますが、**削除しないことが最善です**。

---

## 2. 設定変更後の反映方法

`project.yaml`を編集した後、以下のいずれかの方法で設定を反映できます。

### 方法1: ホットリロード（推奨）

Process-Composeの`project update`コマンドを使用すると、サービスを再起動せずに設定を反映できます:

```bash
process-compose -p ${PROCESS_COMPOSE_PORT} project update -f workloads/process-compose/project.yaml
```

**動作**:
- 実行中のprocess-composeインスタンスに新しい設定を送信
- HTTPサーバー経由で通信するため、プロセスの再起動は不要
- 既に起動中のプロセスは影響を受けません（設定が変更されたプロセスを反映するには個別に再起動が必要な場合があります）

**確認方法**:
```bash
# 設定更新後に状態を確認
process-compose -p ${PROCESS_COMPOSE_PORT} project state
```

### 方法2: サービス再起動

完全な再起動が必要な場合や、ホットリロードで問題が発生した場合は、以下のコマンドでProcess-Composeサービスを再起動できます:

```bash
# Process-Composeサービスを再起動
# s6-overlayがPID 1を保護しているため、コンテナは停止しません
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
