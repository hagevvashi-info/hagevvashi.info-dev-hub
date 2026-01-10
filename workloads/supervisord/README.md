# Supervisord Project Configuration (`project.conf`)

このディレクトリには、Monolithic DevContainer環境におけるSupervisordの実運用設定ファイル `project.conf` が配置されています。
このファイルを編集することで、安定稼働が求められるサービス（code-serverなど）や、difitなどの開発ツールをSupervisordの管理下に置くことができます。

---

## 1. `project.conf` の編集ガイド

`project.conf`はSupervisordの標準的なINI形式で記述されます。
`[program:your_service_name]`セクションを追加・編集することで、Supervisordが管理するプロセスを定義します。

### よく使う設定項目

*   **`command`**: 実行するコマンド。フルパスで指定することを推奨します。
*   **`user`**: プロセスを実行するユーザー。通常は`<一般ユーザー>`などの非rootユーザーを指定します。
*   **`directory`**: プロセスが実行されるワーキングディレクトリ。
*   **`autostart`**: `true`にするとSupervisord起動時に自動的にプロセスを開始します。
*   **`autorestart`**: `true`にするとプロセスが異常終了した場合に自動的に再起動します。開発環境ではエラーを見たい場合が多いため、`false`に設定することも検討してください。
*   **`priority`**: プロセス起動・停止の優先順位。数値が小さいほど優先度が高いです。
*   **`environment`**: プロセス固有の環境変数を設定します。
*   **`stdout_logfile` / `stderr_logfile`**: プロセスの標準出力/エラー出力のログファイルパス。`/dev/stdout`や`/dev/stderr`に設定すると、Dockerのログとして集約されます。

### 例

```ini
[program:your-custom-service]
command=/usr/local/bin/your-command --arg1 value
user=<一般ユーザー>
directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/repos/your-project
autostart=true
autorestart=false # エラーを見たいので自動再起動しない
environment=YOUR_ENV_VAR="some_value"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

---

## 2. 設定変更後の反映方法

`project.conf`を編集しただけでは、Supervisordに設定が反映されません。以下のいずれかの方法で変更を反映させる必要があります。

### 方法1: `supervisorctl` コマンドを使用（推奨）

新しいプログラムを追加したり、既存プログラムの`command`以外の設定を変更した場合に推奨される方法です。

```bash
# 設定ファイルの変更をSupervisordに読み込ませる
supervisorctl reread

# 変更をSupervisordに反映させる（新規プロセスが追加/変更される）
supervisorctl update

# 特定のプロセスを再起動して設定を適用
# supervisorctl restart your-service-name
```
`reread`で新しい設定を検出し、`update`でその設定を適用します。

### 方法2: `s6-svc` コマンドでSupervisordサービスを再起動

`command`の変更など、`supervisorctl reread/update`では反映されない変更や、Supervisord自体を完全に再起動したい場合に有効です。

```bash
# Supervisordサービスを再起動します
# s6-overlayがPID 1を保護しているため、コンテナは停止しません。
s6-svc -t /run/service/supervisord
```
このコマンドはSupervisordサービスを停止・開始しますが、コンテナ自体は停止しませんので、安心して実行できます。

---

## 3. Process-Compose との使い分け

SupervisordとProcess-Composeは、それぞれ異なる得意分野を持つプロセス管理ツールです。適切に使い分けることで、開発効率を最大化できます。

| 観点 | Supervisord | Process-Compose |
|------|-------------|-----------------|
| **管理対象** | 安定稼働が必要なプロセス（code-server, DBなど） | 開発中に頻繁に起動・停止・再起動するプロセス（Webサーバー, APIサーバー, テストなど） |
| **UI** | Web UI (http://localhost:9001) | ターミナルUI (TUI) |
| **設定形式** | INI形式 | YAML形式 (docker-composeライク) |
| **自動再起動** | `autorestart=true` で設定可能（ただし開発中は`false`推奨） | YAMLで設定可能 |
| **特性** | 堅牢性、永続性 | 開発中の柔軟性、高速なフィードバック |

### 推奨される使い分け

*   **Supervisordで管理すべきプロセス**:
    *   `code-server`: 開発環境の基盤であり、常に起動しているべきサービス。
    *   データベース（PostgreSQL, Redisなど）: 安定稼働が求められるミドルウェア。
    *   Supervisord自体やProcess-Composeサービスなど、他のプロセス管理ツールの基盤となるもの。
*   **Process-Composeで管理すべきプロセス**:
    *   `difit`: 開発中に頻繁に起動・停止する開発支援ツール。
    *   フロントエンドの`vite dev server`や、バックエンドのAPIサーバー（ホットリロード対象）。
    *   一時的に実行するスクリプトや実験的なサービス。
    *   依存関係をYAMLで定義したいマイクロサービス群。

---

詳細なアーキテクチャやガイドラインは `foundations/onboarding/s6-hybrid-process-management-guide.md` を参照してください。
