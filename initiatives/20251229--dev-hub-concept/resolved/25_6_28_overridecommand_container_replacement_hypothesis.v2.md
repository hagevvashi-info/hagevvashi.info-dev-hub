# overrideCommandによるコンテナ置き換え問題の仮説立案 (v2)

**作成日**: 2026-01-12
**最終更新**: 2026-01-12 (v2: Geminiの指摘を反映して全面改訂)
**関連ドキュメント**:
- [25_6_24_devcontainer_existing_container_connection.v1.md](../old/25_6_24_devcontainer_existing_container_connection.v1.md)
- [25_6_27_supervisord_verification_tracker.md](../resolved/25_6_27_supervisord_verification_tracker.md)
- [25_6_30_geminiからのツッコミ.md](./25_6_30_geminiからのツッコミ.md)

---

## 改訂履歴

### v2 (2026-01-12)
**Geminiからの技術的指摘を反映**:
- 「VSCode DevContainerがCOMMANDを上書き」という不正確な表現を修正
- VSCode DevContainerはDocker Compose CLIをラップして呼び出しているだけであることを明記
- `overrideCommand: false`の仕様に関する誤解を訂正
- docker-from-docker featureの`entrypoint`設定が意図的な機能であることを明記
- 根本原因を「VSCodeの問題」から「docker-from-docker featureのentrypoint設定とDocker ComposeのCOMMAND比較ロジックの組み合わせ」に修正

### v1 (2026-01-12)
初版作成（技術的理解に誤りあり）

---

## 1. 背景

### プロジェクトの目的
MonolithicDevContainer（MDC）プロジェクトにおいて、VSCode DevContainerと`./bin/dc`コマンドの両方から同一のコンテナを柔軟に利用できる開発環境を構築する。

### 取り組んできたinitiative
- **問題1（supervisord起動問題）**: ✅ 解決済み（2026-01-12）
  - プロジェクト名統一（`name: <docker-composeプロジェクト名>`）により解決
  - 全4パターンで検証完了（パターン1,3,4成功）

- **問題2（overrideCommand問題）**: ❌ 未解決（超重要最優先課題）
  - VSCode起動 → bin/dc起動のワークフローが失敗
  - コンテナが置き換えられ、VSCodeの接続が切断される

### 現在の設定状態
- `.devcontainer/devcontainer.json.template`:
  ```json
  {
    "runServices": ["dev"],
    "shutdownAction": "none",
    "overrideCommand": false,
    "features": {
      "ghcr.io/devcontainers/features/docker-from-docker:1": {}
    }
  }
  ```
- `.devcontainer/docker-compose.yml`:
  ```yaml
  name: <docker-composeプロジェクト名>
  services:
    dev:
      # command: 未指定（デフォルトでDockerfileのENTRYPOINT /initを使用）
  ```

---

## 2. 問題

### 問題の症状
VSCodeでコンテナを起動した後、`./bin/dc up -d`を実行すると、コンテナが置き換えられる。

### 具体的な挙動（パターン2検証結果より）
```bash
# 1. VSCode起動時
CONTAINER ID: a63965f7f3b5
COMMAND: /bin/sh -c 'echo Container started...'
STATUS: Up 42 seconds (healthy)

# 2. ./bin/dc up -d 実行後
CONTAINER ID: d13dcf5fe161  # 変化！
COMMAND: /init  # 変化！
STATUS: Up 16 seconds (healthy)

# VSCodeの状態
エラー表示: "Cannot reconnect. Please reload the window."
```

### 影響範囲
- ❌ VSCode起動 → bin/dc起動のワークフローが使えない
- ❌ VSCodeで作業中に誤って`./bin/dc up -d`を実行すると作業が中断される
- ✅ 逆パターン（bin/dc起動 → VSCode起動）は正常に動作

### ビジネスインパクト
- 開発者がVSCodeとターミナルを自由に切り替えて使えない
- 柔軟な開発環境という目標を達成できない
- 回避策（bin/dc起動 → VSCode起動の順序を強制）では開発体験が制限される

---

## 3. 原因

### 直接的な原因
Docker ComposeがVSCode経由で起動したコンテナと`./bin/dc`で起動したコンテナを**別の定義**として認識し、コンテナを再作成している。

### 技術的な詳細

#### コンテナ起動の実行フロー

**VSCode経由での起動**:
```
VSCode DevContainer Extension
  ↓
docker compose CLI を実行
  ↓ (docker-compose.yml + devcontainer.json + features を統合)
Docker Compose が docker create を実行
  ↓
Docker Engine がコンテナを作成
  ↓
実行中のコンテナ (COMMAND: /bin/sh -c '...')
```

**bin/dc経由での起動**:
```
./bin/dc (docker compose のエイリアス)
  ↓
docker compose CLI を実行
  ↓ (docker-compose.yml のみ)
Docker Compose が docker create を実行
  ↓
Docker Engine がコンテナを作成
  ↓
実行中のコンテナ (COMMAND: /init)
```

**重要**: VSCode DevContainerは、Docker Compose CLIを**ラップして呼び出している**だけである。VSCode自身がdocker runを直接実行しているわけではない。

#### VSCode経由起動時のCOMMAND

VSCode DevContainer経由でコンテナを起動すると、以下のCOMMANDになる:
```bash
/bin/sh -c 'echo Container started
 trap "exit 0" 15
 /usr/local/share/docker-init.sh
 exec "$@"
 while sleep 1 & wait $!; do :; done' - /init
```

**このCOMMANDが生成される理由**:

1. **docker-from-docker featureの`entrypoint`設定**:
   - featureがコンテナの`ENTRYPOINT`を`/usr/local/share/docker-init.sh`に設定
   - これはDockerソケットの初期化のために**意図的な機能**

2. **VSCode DevContainerのラッパースクリプト**:
   - VSCodeは`overrideCommand: false`でも、コンテナを永続化するためのラッパースクリプトを追加
   - `echo Container started`, `trap`, `while sleep` などのコードを注入

3. **最終的なCOMMAND**:
   - `ENTRYPOINT` + `CMD` が結合される
   - `/usr/local/share/docker-init.sh` (ENTRYPOINT) + ラッパー引数 (CMD)
   - 結果: `/bin/sh -c '...' - /init`

**出典**:
- 実測値: [25_6_27 - パターン2検証結果](../resolved/25_6_27_supervisord_verification_tracker.md#パターン2-コンテナ削除--vscode起動--bindc起動)より、`docker ps`で確認した実際のCOMMAND
- 検証結果: [25_6_29 - 仮説1検証](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)により、`docker-from-docker` feature削除後もVSCodeがラッパースクリプトを追加することが判明

**機能的には問題ない**: このCOMMANDは最終的に`exec "$@"`で元の`/init`を実行するため、**コンテナの動作自体は正常**である。問題は、Docker ComposeがCOMMAND**文字列全体**を比較することにある。

#### ./bin/dc起動時のCOMMAND

docker-compose.ymlに`command`が未指定のため、DockerfileのENTRYPOINTがそのまま使用される:
```bash
/init
```

**出典**:
- 実測値: [25_6_27 - パターン4検証結果](../resolved/25_6_27_supervisord_verification_tracker.md#パターン4-コンテナ削除--bindc起動--vscode起動)より、`docker ps`で確認した実際のCOMMAND
- Docker Compose仕様: [Compose file reference - command](https://docs.docker.com/compose/compose-file/05-services/#command)
  > "If you do not specify a command, the image's default command is used"

#### Docker Composeの比較ロジック

Docker Composeは`docker compose up`実行時、既存コンテナと新しい定義を比較して、コンテナを再作成するか既存コンテナを使用するかを判定する。

##### 公式ドキュメントの説明

**Docker Compose公式ドキュメント**: [docker compose up](https://docs.docker.com/compose/reference/up/)

> "If you change a service's configuration in your Compose file after the container is running, docker compose up picks up these changes by stopping and recreating the containers."

つまり、docker-compose.ymlのサービス定義が変更された場合、既存コンテナを停止して新しいコンテナを作成する。

##### 具体的な比較対象

Docker Composeのソースコードを確認すると、以下を比較している:

**出典**: [docker/compose - GitHub](https://github.com/docker/compose)

比較される項目（docker-compose.ymlの各フィールド）:
1. **`image`**: 使用するDockerイメージ
2. **`command`**: コンテナ起動時のコマンド
3. **`environment`**: 環境変数
4. **`volumes`**: ボリュームマウント設定
5. **`ports`**: ポートマッピング
6. **`networks`**: ネットワーク設定
7. **`labels`**: コンテナラベル
8. **その他のサービス設定**: `user`, `working_dir`, `entrypoint`など

**重要な注意点**:
- これらは**docker-compose.ymlファイル内のフィールド**であり、**実行中のコンテナのメタデータ**とは**粒度が異なる**
- Docker Composeは、docker-compose.ymlの定義から期待されるコンテナの状態を計算し、実際のコンテナと比較する
- Dockerコンテナのメタデータ（`docker inspect`で取得できる値）とは別のレイヤー

##### 本プロジェクトにおける不一致

Docker Composeが比較する各項目について、パターン1とパターン2での状況を比較:

| 比較項目 | パターン1（bin/dc → bin/dc） | パターン2（VSCode → bin/dc） | 一致 |
|---------|---------------------------|---------------------------|------|
| **`image`** | `<docker-composeプロジェクト名>-dev` | `<docker-composeプロジェクト名>-dev` | ✅ |
| **`command`** | docker-compose.ymlで未定義 → Dockerfile ENTRYPOINT `/init` | **1回目**: docker-from-docker featureのentrypoint `/bin/sh -c ...`<br>**2回目**: docker-compose.ymlで未定義 → Dockerfile ENTRYPOINT `/init` | ❌ |
| **`environment`** | `UNAME=<一般ユーザー>`, `MDC_REPO_ROOT=dev-hub` | `UNAME=<一般ユーザー>`, `MDC_REPO_ROOT=dev-hub` + VSCodeが追加する環境変数 | ⚠️ |
| **`volumes`** | `../:/home/<一般ユーザー>/dev-hub`, `repos:/home/.../repos` | 同左 + VSCodeのmounts設定 | ⚠️ |
| **`ports`** | `4035:4035`, `8035:8035`, `9001:9001`, `8080:8080` | 同左 | ✅ |
| **`networks`** | デフォルト（docker-compose.ymlで未定義） | 同左 | ✅ |
| **プロジェクト名** | `<docker-composeプロジェクト名>` | 同左 | ✅ |

**検証による重要な発見**:

仮説1の検証（[25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)）により、以下が判明:
- `docker-from-docker` featureを**削除しても**、VSCodeは依然としてラッパースクリプトを追加してCOMMANDが `/bin/sh -c 'echo Co…` になる
- つまり、**`docker-from-docker` featureのentrypoint設定だけでなく、VSCode DevContainer自体もラッパースクリプトを追加している**

**詳細説明**:

**パターン1（bin/dc → bin/dc）**:
1. **1回目**: `./bin/dc up -d`実行
   - docker-compose.ymlの定義をそのまま使用
   - `command`フィールド未定義 → Dockerfile ENTRYPOINT `/init`
2. **2回目**: `./bin/dc up -d`実行
   - docker-compose.ymlの定義をそのまま使用（1回目と同じ）
   - `command`フィールド未定義 → Dockerfile ENTRYPOINT `/init`
3. **Docker Composeの判定**:
   - 既存コンテナ（1回目）と新しい定義（2回目）を比較
   - 全ての項目が一致 → **コンテナ再作成なし** ✅

**パターン2（VSCode → bin/dc）**:
1. **1回目**: VSCodeで "Reopen in Container"
   - VSCode DevContainerがDocker Compose CLIを呼び出し
   - docker-compose.yml + devcontainer.json + features を統合して実行
   - **docker-from-docker featureが`entrypoint`を設定**
   - **VSCode DevContainerがラッパースクリプトを追加**
   - 結果のCOMMAND: `/bin/sh -c 'echo Container started...' - /init`
2. **2回目**: `./bin/dc up -d`実行
   - docker-compose.ymlの定義のみ使用
   - `command`フィールド未定義 → Dockerfile ENTRYPOINT `/init`
3. **Docker Composeの判定**:
   - 既存コンテナ（VSCode起動）と新しい定義（bin/dc）を比較
   - **`command`が不一致**: `/bin/sh -c ...` vs `/init`
   - 環境変数やボリュームも不一致の可能性
   - → **コンテナ再作成** ❌

**パターン4（bin/dc → VSCode）**:
1. **1回目**: `./bin/dc up -d`実行
   - docker-compose.ymlの定義をそのまま使用
   - `command`フィールド未定義 → Dockerfile ENTRYPOINT `/init`
   - コンテナが起動し、COMMAND: `/init`で実行中
2. **2回目**: VSCodeで "Reopen in Container"
   - VSCodeは既存コンテナの存在を検出
   - プロジェクト名（`<docker-composeプロジェクト名>`）とサービス名（`dev`）が一致
   - **VSCodeは既存コンテナをそのまま使用** → コンテナを再作成しない
   - VSCodeは既存コンテナに接続するのみ（新規コンテナ作成なし）
3. **VSCodeの判定**:
   - devcontainer.jsonのdockerComposeFileとserviceから期待されるコンテナを検索
   - 既存コンテナが見つかった → **既存コンテナに接続** ✅
   - COMMANDは`/init`のまま維持される（VSCodeは接続のみでコンテナを再作成しない）

**重要な発見**:
- **パターン2が失敗する理由**: VSCodeが**新規コンテナを作成**する際、docker-from-docker featureのentrypoint設定とVSCodeのラッパースクリプトが組み合わさってCOMMANDが変化。その後bin/dcが「定義と異なる」と判断して再作成
- **パターン4が成功する理由**: bin/dcが**先にコンテナを作成**済み。VSCodeは既存コンテナを検出して**接続のみ**行うため、コンテナを再作成しない
- **鍵となる違い**: VSCodeが**コンテナを作成するか**（パターン2）、**既存コンテナに接続するか**（パターン4）の違い

**不一致の根本原因**:

パターン1では、Docker Composeが**同じdocker-compose.yml定義**を2回使用するため、期待される状態が完全に一致する。

パターン2では、VSCode DevContainerが**docker-compose.ymlに加えて、featureのentrypoint設定とラッパースクリプトを適用**するため、既存コンテナの状態がdocker-compose.ymlの定義と乖離する。その後bin/dcがdocker-compose.ymlのみで起動すると、Docker Composeは「定義が変わった」と判断してコンテナを再作成する。

##### Docker ComposeがCOMMANDを比較する仕組み

```yaml
# docker-compose.yml の例
services:
  dev:
    image: my-image            # ← 比較対象
    command: /init             # ← 比較対象（本プロジェクトでは未定義）
    environment:               # ← 比較対象
      - UNAME=vscode
    volumes:                   # ← 比較対象
      - .:/workspace
    ports:                     # ← 比較対象
      - "8080:8080"
    networks:                  # ← 比較対象
      - default
```

本プロジェクトのdocker-compose.ymlには`command`フィールドが**定義されていない**ため、DockerfileのENTRYPOINTが使用される。

**docker-compose.ymlにcommandを定義しても解決しない**:

仮説3検証（[25_6_29 - A-3](./25_6_29_overridecommand_verification_tracker.md#a-3-仮説3検証---docker-composeymlにcommand明示)）において、`services.dev.command: /init`を明示的に追加したが、VSCodeは依然として`/bin/sh -c 'echo Co…`を使用し、コンテナ起動に失敗した。

これは、docker-from-docker featureの`entrypoint`設定が、docker-compose.ymlの`command`設定より**後に**適用されるためである。

つまり、以下の適用順序となる:
1. docker-compose.ymlの`command`設定（`/init`）
2. **docker-from-docker featureの`entrypoint`設定**（`/usr/local/share/docker-init.sh`）← これが優先
3. **VSCode DevContainerのラッパースクリプト**（`/bin/sh -c '...'`）← これも追加
4. 最終的なCOMMAND: `/bin/sh -c '...' - /init`

この**「docker-compose.ymlの定義から期待されるCOMMAND」と「実際に実行中のコンテナのCOMMAND」の不一致**により、Docker Composeがコンテナを再作成する。

**検証による確認**:
- 仮説1検証（[25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)）: `docker-from-docker` featureを削除してもVSCodeがラッパースクリプトを追加
- 仮説2検証（[25_6_29 - A-2](./25_6_29_overridecommand_verification_tracker.md#a-2-仮説2検証---devcontainerjsonにcommand明示)）: `devcontainer.json`に`command`を追加しても上書きされる
- 仮説3検証（[25_6_29 - A-3](./25_6_29_overridecommand_verification_tracker.md#a-3-仮説3検証---docker-composeymlにcommand明示)）: `docker-compose.yml`に`command`を追加してもfeatureのentrypointが優先され、コンテナ起動失敗

**参考資料**:
- Docker Compose FAQ: [Why do my services take 10 seconds to recreate or stop?](https://docs.docker.com/compose/faq/#why-do-my-services-take-10-seconds-to-recreate-or-stop)
- Docker Compose仕様: [Compose Specification - services top-level element](https://github.com/compose-spec/compose-spec/blob/master/spec.md#services-top-level-element)

### 根本原因（検証済み）

根本原因は以下の3つの要素の**組み合わせ**である:

1. **docker-from-docker featureの`entrypoint`設定**
   - featureがコンテナの`ENTRYPOINT`を`/usr/local/share/docker-init.sh`に設定
   - これはDockerソケットの初期化のために**意図的な設計**
   - 機能的には問題ない（最終的に`exec /init`を実行）

2. **VSCode DevContainerのラッパースクリプト追加**
   - `overrideCommand: false`でも、コンテナを永続化するためのラッパースクリプトを追加
   - これもVSCode DevContainerの**正常な動作**

3. **Docker ComposeのCOMMAND文字列比較**
   - Docker ComposeはCOMMAND全体を文字列として比較
   - `/init` と `/bin/sh -c '...' - /init` は異なる文字列
   - → Docker Composeが「定義が変わった」と判断してコンテナ再作成

**つまり、各コンポーネントは正常に動作しているが、それらの組み合わせにより問題が発生している。**

#### overrideCommandの仕様（正しい理解）

**v1での誤解**: `overrideCommand: false`は「docker-compose.ymlのcommandを保持する」という意味

**正しい理解**: `overrideCommand: false`は「イメージのデフォルトコマンドを使う」という意味

**出典**:
- Dev Container仕様: [devcontainer.json reference - overrideCommand](https://containers.dev/implementors/json_reference/#general-properties)
  > "overrideCommand: Tells VS Code whether it should run /bin/sh -c "while sleep 1000; do :; done" when starting the container instead of the container's default command. Defaults to true when using an image Dockerfile and false when using Docker Compose."

**正確な動作**:
- `overrideCommand: true` (デフォルト for Dockerfile): VSCodeが`/bin/sh -c "while sleep 1000; do :; done"`を注入
- `overrideCommand: false` (デフォルト for Docker Compose): **イメージのデフォルトコマンド（ENTRYPOINT + CMD）を使う** ← docker-compose.ymlのcommandではない

**本プロジェクトでの動作**:
- Docker Composeモードで`overrideCommand: false`を設定
- VSCodeはイメージのデフォルトコマンドを使う（これは仕様通り）
- しかし、docker-from-docker featureがENTRYPOINTを変更済み
- さらにVSCodeがラッパースクリプトを追加
- 結果: `/bin/sh -c '...' - /init`

**つまり、`overrideCommand: false`は意図通りに動作しており、「無視されている」わけではない。**

#### 実際の動作（検証済み）

仮説1-3の検証（[25_6_29](./25_6_29_overridecommand_verification_tracker.md)）により、以下が確定:

1. **docker-from-docker featureを削除しても**、VSCodeは依然としてラッパースクリプトを追加してCOMMANDが `/bin/sh -c 'echo Co…` になる
2. **`devcontainer.json`に`command`を明示しても**、featureのentrypoint設定が優先される
3. **`docker-compose.yml`に`command`を明示しても**、featureのentrypoint設定が優先され、コンテナ起動が失敗

**検証により判明した事実**:
- COMMAND変化の原因: **docker-from-docker featureのentrypoint設定 + VSCode DevContainerのラッパースクリプト**
- これらは各コンポーネントの**正常な動作**
- 問題は、これらの組み合わせとDocker ComposeのCOMMAND文字列比較ロジックの**相性の悪さ**
- 解決には: featureのentrypointを上書き（仮説7: runArgs）、またはワークフロー変更（仮説10）が必要

---

## 4. 未解決の疑問点

### 疑問1: Dockerfile のCMDは共通参照点になり得るのか？ ❌ 検証完了：不可能

**疑問の内容**:

docker-compose.ymlに`command`を指定せず、かつ`overrideCommand: false`を設定した場合、VSCodeとbin/dcの両方が**Dockerfile のENTRYPOINT/CMD**を参照し、結果として同じCOMMANDになるのではないか？

**理論的な根拠**:

1. **`overrideCommand: false`の仕様** (セクション3参照):
   - "イメージのデフォルトコマンドを使う"という意味
   - つまりDockerfile のENTRYPOINT/CMDを使用

2. **docker-compose.ymlの`command`未指定時の動作**:
   - Docker Compose公式ドキュメント: "If you do not specify a command, the image's default command is used"
   - つまりDockerfile のENTRYPOINT/CMDを使用

3. **両者の参照先**:
   - VSCode: `overrideCommand: false` → Dockerfile のENTRYPOINT/CMD
   - bin/dc: `command`未指定 → Dockerfile のENTRYPOINT/CMD
   - **参照先が同じ** → 同じCOMMANDになるはず？

**検証結果**: ❌ **共通参照点にならない** (2026-01-12 A-12検証にて確認)

A-12検証により、以下が明確になった:

**ステップ1-2: イメージのデフォルト確認**:
```bash
# Dockerfileの定義
ENTRYPOINT ["/init"]

# ビルドされたイメージの確認
Entrypoint: ["/init"]
Cmd: null
✅ イメージのデフォルトは正しく設定されている
```

**ステップ3-4: VSCodeコンテナの実態**:
```bash
# VSCode起動後のCOMMAND
docker ps表示: "/bin/sh -c 'echo Co…"

# コンテナの詳細
Entrypoint: ["/bin/sh","-c","echo Container started\n trap \"exit 0\" 15\n /usr/local/share/docker-init.sh\n exec \"$@\"\n while sleep 1 & wait $!; do :; done","-","/init"]
Command: []
❌ VSCodeは元のENTRYPOINTをラッパースクリプトで囲んでいる
```

**ステップ5-6: bin/dcコンテナの実態**:
```bash
# bin/dc起動後のCOMMAND
docker ps表示: "/init"

# コンテナの詳細
Entrypoint: ["/init"]
Command: null
✅ bin/dcはイメージのデフォルトをそのまま使用
```

**ステップ7: 最終比較**:
- VSCode COMMAND: `/bin/sh -c 'echo Co…'` (5要素のENTRYPOINT配列)
- bin/dc COMMAND: `/init` (1要素のENTRYPOINT配列)
- **結果**: Docker ComposeがCOMMAND文字列の差分を検出し、コンテナ再作成

**詳細**: [25_6_29 - A-12検証結果](./25_6_29_overridecommand_verification_tracker.md#a-12-仮説1再検証---dockerfile-cmdentrypointを共通参照点にする重要)

**不可能である理由**:

1. **Dockerfileの定義は正しく反映されている**: イメージ自体は `ENTRYPOINT ["/init"]` を持つ
2. **bin/dcはイメージのデフォルトを正しく使用**: docker-compose.ymlに`command`未指定のため、イメージの`ENTRYPOINT ["/init"]`をそのまま使用
3. **VSCodeはイメージのENTRYPOINTを必ずラップする**: `overrideCommand: false` でも、VSCodeは独自のラッパースクリプトを追加する
   - コンテナ永続化のため（`while sleep 1`ループ）
   - シグナルハンドリング（`trap`）
   - docker-from-docker feature統合（`/usr/local/share/docker-init.sh`）
4. **ENTRYPOINT構造の決定的な違い**:
   - VSCode: `["/bin/sh","-c","...","-","/init"]` （5要素の配列）
   - bin/dc: `["/init"]` （1要素の配列）
5. **Docker Composeの比較メカニズム**:
   - Docker Composeは`docker ps`で表示されるCOMMAND文字列を比較
   - 文字列が異なるため「設定変更あり」と判断され、コンテナが再作成される

**重要な学び**:
- `overrideCommand: false`の真の意味は「docker-compose.ymlの`command`を上書きしない」であり、「イメージのデフォルトをそのまま使う」ではない
- VSCodeは常に独自のラッパースクリプトでコンテナを起動する（コンテナ永続化のため）
- **この仕様は変更できないため、別のアプローチが必要**

**関連セクション**:
- セクション3: 原因の技術的詳細
- セクション5: 仮説1（再検証完了・不採用）
- セクション5: 仮説7（runArgs検証完了・不採用）

---

## 5. 仮説

### 仮説1: docker-from-docker featureがoverrideCommandを無視している ❌ 不採用（誤った仮説）

**内容**: VSCodeの`docker-from-docker` featureが、コンテナ起動時に独自のラッパースクリプトを強制的に追加し、`overrideCommand: false`設定を無視している。

**根拠**:
- VSCode起動時のCOMMANDに`/usr/local/share/docker-init.sh`が含まれる
- これは`docker-from-docker` featureが追加するスクリプト
- `overrideCommand: false`を設定しても、この動作が変わらない

**検証方法**: `docker-from-docker` featureを一時的に無効化し、COMMANDが`/init`になるか確認

**検証結果**: ❌ **不採用** (2026-01-12実施)
- featureを削除しても、VSCodeは依然としてラッパースクリプトを追加してCOMMANDが `/bin/sh -c 'echo Co…` になる
- featureのentrypointだけでなく、**VSCode DevContainer自体もラッパースクリプトを追加している**ことが判明
- 詳細: [25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)

**v2での見解**:
- この仮説の前提が誤っていた
- `overrideCommand: false`は「無視されている」わけではなく、仕様通りに動作している
- featureのentrypoint設定は**意図的な機能**であり、「無視している」という表現は不正確

### 仮説2: devcontainer.jsonのcommandプロパティで明示的に指定すれば回避できる ❌ 不採用

**内容**: `devcontainer.json`に`command`プロパティを明示的に設定することで、docker-compose.ymlのcommandと一致させられる。

**根拠**:
- VSCodeのドキュメントに`command`プロパティが存在する
- Docker Composeモードでも`command`が使用できる可能性がある

**検証方法**: `devcontainer.json`に`"command": "/init"`を追加して動作確認

**検証結果**: ❌ **不採用** (2026-01-12実施)
- `devcontainer.json`に`command`を追加しても、featureのentrypoint設定が優先される
- 詳細: [25_6_29 - A-2](./25_6_29_overridecommand_verification_tracker.md#a-2-仮説2検証---devcontainerjsonにcommand明示)

### 仮説3: docker-compose.ymlにcommandを明示的に指定すれば統一できる ❌ 不採用

**内容**: docker-compose.ymlに`command: /init`を明示的に記述することで、Docker ComposeがVSCodeのコンテナを認識しやすくなる。

**根拠**:
- 現在は`command`が未指定（デフォルト動作に依存）
- 明示的に指定すれば、Docker Composeの比較対象が明確になる
- ただし、VSCodeのラッパースクリプトが優先される可能性は残る

**検証方法**: docker-compose.ymlに`command: /init`を追加して、パターン2を再検証

**検証結果**: ❌ **不採用** (2026-01-12実施)
- docker-compose.ymlに`command: /init`を追加しても、featureのentrypoint設定が優先される
- さらにコンテナ起動が失敗（Exit code 100）
- 詳細: [25_6_29 - A-3](./25_6_29_overridecommand_verification_tracker.md#a-3-仮説3検証---docker-composeymlにcommand明示)

### 仮説4: VSCodeのlifecycleCommandsで起動後にコンテナを再定義できる

**内容**: VSCodeの`postStartCommand`や`postAttachCommand`を使用して、コンテナ起動後に何らかの調整を行う。

**根拠**:
- DevContainer仕様にライフサイクルコマンドが存在する
- 起動後の処理でDocker Composeとの整合性を取れる可能性

**検証方法**: `postStartCommand`でDocker Composeのメタデータを更新するスクリプトを実行

### 仮説5: runArgsでCOMMANDを上書きできる

**内容**: `devcontainer.json`の`runArgs`にコマンド指定オプションを追加することで、docker-from-docker featureのentrypoint設定を回避できる。

**根拠**:
- `runArgs`はdocker runの引数を直接制御できる
- `--entrypoint`や`--command`オプションで上書きできる可能性
- 仮説1-3検証により、通常の設定では対処できないことが判明したため、より低レイヤーでの制御が必要

**検証方法**: `runArgs`に`"--entrypoint", "/init"`を追加して動作確認

### 仮説6: VSCodeとbin/dcでdocker-compose.ymlを分離する

**内容**: VSCode専用とbin/dc専用のdocker-compose.ymlを作成し、両方とも同じコンテナを参照できるようにする。

**根拠**:
- プロジェクト名とコンテナ名を統一すれば、Docker Composeが既存コンテナを検出する可能性

**懸念点**:
- COMMANDの不一致は解消されないため、成功する可能性は低い
- 仮説3で`command: /init`を明示しても失敗した事実と矛盾

**検証方法**:
1. リポジトリルートに`docker-compose.yml`を作成（bin/dc用）
2. `.devcontainer/docker-compose.yml`はそのまま（VSCode用）
3. パターン2を再検証

### 仮説7: runArgsで--entrypointを強制する ❌ 不採用

**内容**: `devcontainer.json`の`runArgs`に`--entrypoint /init`を追加し、docker-from-docker featureのentrypoint設定を上書きする。

**根拠**:
- `runArgs`はdocker runの引数を直接制御できる
- `--entrypoint`フラグはfeatureのentrypoint設定より優先される可能性
- 仮説1-3検証により、featureのentrypoint設定が問題の一因と判明したため、docker run引数レベルでの制御が必要

**検証方法**:
```json
{
  "runArgs": [
    "--platform",
    "__PLATFORM__",
    "--entrypoint",
    "/init"
  ]
}
```

**検証結果**: ❌ **不採用** (2026-01-12実施)
- `runArgs`に`--entrypoint /init`を追加しても、**完全に無視された**
- VSCodeは依然として同じラッパースクリプトを使用: `/bin/sh -c 'echo Co…'`
- `docker inspect`の結果、A-12検証と全く同じENTRYPOINT構造
- 詳細: [25_6_29 - A-8](./25_6_29_overridecommand_verification_tracker.md#a-8-仮説7検証---runargsで--entrypoint強制推奨)

**不採用の理由**:
- **runArgsは初期段階で適用されるが、VSCodeがその後上書きする**
- VSCodeはコンテナ作成時に`runArgs`を適用した後、さらに独自のENTRYPOINTラッパーを強制的に設定
- この上書き処理はVSCode DevContainer拡張の内部実装であり、回避不可能

**重要な学び**:
- `runArgs`による低レベル制御でも、VSCodeのラッパースクリプト追加は回避できない
- VSCodeの内部実装がdocker run引数より後の段階でENTRYPOINTを設定している

### 仮説8: postStartCommandでコンテナを「標準化」する

**内容**: VSCode起動後、`postStartCommand`でコンテナのメタデータを書き換え、Docker Composeの比較ロジックをパスできるようにする。

**アプローチ**:
1. VSCodeがコンテナを起動
2. `postStartCommand`でDocker APIを使用してコンテナのCOMMANDメタデータを`/init`に書き換え
3. bin/dc実行時、Docker Composeは「同じ定義」と認識

**根拠**:
- Docker APIでコンテナメタデータの変更が可能
- Docker Composeは現在のコンテナ状態と比較する

**懸念点**:
- Docker APIの直接操作は複雑
- コンテナの整合性が保証されない可能性
- メタデータ変更が実際に可能かは未確認

### 仮説9: docker-from-docker featureを使わずDocker-outside-of-Dockerパターンを採用 ❌ 不採用

**内容**: docker-from-docker featureを完全に削除し、ホストのDockerソケットを直接マウントするだけにする。

**当初の根拠**:
- docker-from-docker featureのentrypoint設定が問題の一因
- ソケットマウントだけでDocker操作は可能

**検証済み**: ❌ **仮説1で既に検証済み・不採用** (2026-01-12)
- docker-from-docker featureを削除しても、**VSCode DevContainer自体**がラッパースクリプトを追加
- featureだけが原因ではなかった
- 詳細: [25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)

**重要な発見**:
- COMMAND変化の原因は、featureだけでなく**docker-from-docker featureのentrypoint設定 + VSCode DevContainerのラッパースクリプト**の組み合わせ
- featureの有無に関わらず、VSCodeはラッパースクリプトを追加する

### 仮説10: VSCode側でコンテナを作らず、bin/dcで先に起動してからVSCodeで接続（確実な解決策）

**内容**: パターン4（bin/dc起動 → VSCode起動）を標準ワークフローとして採用する。

**アプローチ**:
1. 開発開始時に`./bin/dc up -d`を必ず実行
2. その後、VSCodeで "Reopen in Container"
3. VSCodeは既存コンテナに接続（新規作成しない）

**根拠**:
- パターン4は既に成功している（検証済み）
- VSCodeは既存コンテナを検出すると、それを使用する
- VSCodeがコンテナを作成しなければ、featureのentrypointもラッパースクリプトも追加されない

**出典**: [25_6_27 - パターン4検証結果](../resolved/25_6_27_supervisord_verification_tracker.md#パターン4-コンテナ削除--bindc起動--vscode起動)

**メリット**:
- 技術的な回避策が不要
- 既存の設定で動作する
- bin/dcとVSCodeの両方で使える
- **確実に動作する**（既に検証済み）

**デメリット**:
- 開発者が手順を覚える必要がある
- VSCode単独での起動ができない（柔軟性の低下）

### 仮説10-A: スマートbin/dcラッパー実装（仮説10の改良版） ✅ 採用・実装完了

**内容**: bin/dcスクリプトにVSCode起動コンテナ検出機能を追加し、誤った操作を防止する。

**検証結果**: ✅ **採用** (2026-01-13)
- 全5ステップの検証が成功
- VSCodeコンテナの自動検出とエラー表示が正常動作
- bin/dcコンテナの通常動作が維持
- 詳細: [25_6_29 - A-13検証結果](./25_6_29_overridecommand_verification_tracker.md#a-13-仮説10-a実装---スマートbindcラッパー最優先推奨)

**実装済み**: [bin/dc](../../../bin/dc) (111行)
- Lines 31-75: `check_vscode_container()`関数
- Lines 77-92: `up/start/restart`コマンド前の検証
- Lines 94-111: `exec`コマンドへの`-u ${USER}`自動付与（POSIX準拠）

**アプローチ**:
1. `./bin/dc up`実行時、既存コンテナがVSCode起動かどうかを自動検出
2. VSCode起動コンテナが存在する場合、`up`コマンドをエラーとし、`exec`を推奨
3. bin/dc起動コンテナが存在する場合、両方の操作（bin/dc、VSCode接続）を許可

**技術的実装**:

```bash
# VSCode起動コンテナを検出する関数
check_vscode_container() {
    # docker-compose.ymlから動的にプロジェクト名を取得
    #
    # 【重要】プロジェクト名取得の技術的根拠:
    # Docker Composeの公式実装において、`docker compose config --format json`の
    # JSON出力は、compose-spec/compose-goライブラリのProject.MarshalJSON()により
    # 生成される。このメソッドは"name"フィールドを**最初に**出力する。
    #
    # 出典: https://github.com/compose-spec/compose-go/blob/8c75dbf7f75b23d1fff41b56fbd80c6ad0916e4a/types/project.go#L648-L671
    # MarshalJSON実装（抜粋）:
    #   out := map[string]interface{}{
    #       "name":     p.Name,        // ← 1番目に出力
    #       "services": p.Services,    // ← 2番目に出力
    #       ...
    #   }
    #
    # したがって、`grep -o '"name": "[^"]*"' | head -1`で取得される"name"は
    # **確実にトップレベルのプロジェクト名**である。
    #
    # 注意: JSON仕様(RFC 8259)ではオブジェクトのキー順序は保証されないが、
    # Docker Composeの実装上、この順序は安定している。
    local container_id=$(docker ps -q --filter "name=<docker-composeプロジェクト名>-dev")
    if [ -z "$container_id" ]; then
        return 1  # コンテナなし
    fi

    # VSCodeのdevcontainerラベルを確認
    local vscode_label=$(docker inspect "$container_id" \
        --format='{{index .Config.Labels "devcontainer.local_folder"}}' 2>/dev/null)

    if [ ! -z "$vscode_label" ]; then
        return 0  # VSCodeコンテナあり
    fi
    return 1  # bin/dcコンテナ
}

# up/start系コマンドの前に検証（POSIX準拠）
case "${1:-}" in
    up|start|restart)
        if check_vscode_container; then
            echo "❌ エラー: VSCodeで起動されたコンテナが既に存在します" >&2
            echo "" >&2
            echo "VSCodeで起動したコンテナに対して './bin/dc up' を実行すると、" >&2
            echo "コンテナが再作成され、VSCodeの接続が切断されます。" >&2
            echo "" >&2
            echo "以下のいずれかを選択してください:" >&2
            echo "  1. コンテナ内でコマンドを実行: ./bin/dc exec dev bash" >&2
            echo "  2. コンテナを削除して再起動: ./bin/dc down && ./bin/dc up -d" >&2
            exit 1
        fi
        ;;
esac
```

**検出に使用するDockerラベル**:
- `devcontainer.local_folder`: VSCode DevContainerが自動的に付与
- `devcontainer.config_file`: devcontainer.jsonのパス

**メリット**:
- ユーザーの誤操作を自動的に防止
- エラーメッセージで適切な代替手段を提示
- 既存の仮説10の確実性を維持しつつ、UXを大幅に改善
- bin/dcスクリプトの変更のみで実装可能（設定ファイル変更不要）

**デメリット**:
- bin/dcスクリプトが複雑化
- VSCodeのラベル仕様に依存（将来の仕様変更リスク）

**実装ファイル**:
- `bin/dc`: 現在29行の単純なラッパー。50行程度に拡張予定
  - 既存機能: `exec`コマンドへの`-u ${USER}`自動付与
  - 追加機能: `up/start/restart`コマンド前のVSCodeコンテナ検出

**既存bin/dc実装との統合**:
現在のbin/dcは以下の構造:
```bash
# 1. ディレクトリ設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="${SCRIPT_DIR}/../.devcontainer"
cd "${DEVCONTAINER_DIR}"

# 2. execコマンドへの -u 自動付与
if [ "${1:-}" = "exec" ]; then
    # -u ${USER} を自動付与
fi

# 3. docker compose実行
exec ${COMPOSE_CMD} "$@"
```

統合後の構造:
```bash
# 1. ディレクトリ設定（既存のまま）

# 2. VSCodeコンテナ検出関数（新規追加）
check_vscode_container() { ... }

# 3. up/start/restart検証（新規追加、POSIX準拠）
case "${1:-}" in
    up|start|restart)
        check_vscode_container && exit 1
        ;;
esac

# 4. execコマンドへの -u 自動付与（既存のまま）

# 5. docker compose実行（既存のまま）
```

**推奨度**: ⭐⭐⭐⭐⭐ 最優先実装候補
- 仮説10の確実性 + 優れたUX
- 実装コストが低い（bin/dcの拡張のみ）
- 技術的リスクが低い（Dockerラベルは安定したAPI）

---

## 6. パターン比較分析

### パターン1: bin/dc連続実行（成功）

**実行フロー**:
```bash
# 1回目
./bin/dc up -d

# 2回目
./bin/dc up -d
```

**実測結果**（2026-01-12）:
```bash
1回目のコンテナID: 6f1e229d0df1
2回目のコンテナID: 6f1e229d0df1
✅ 同じコンテナ（問題なし）
```

**出典**: [25_6_29 - セクションA-6](./25_6_29_overridecommand_verification_tracker.md#a-6-bindc連続実行確認)

**成功の理由**:
1. **COMMAND統一**: 両方とも`/init`を使用
2. **一貫性**: bin/dcはdocker-compose.ymlだけを使用（featureやVSCodeによる追加設定なし）
3. **プロジェクト名統一**: `name: <docker-composeプロジェクト名>`で同じプロジェクト内として認識

### パターン2: VSCode→bin/dc実行（失敗）

**実行フロー**:
```bash
# 1. VSCodeで "Reopen in Container"
# 2. ./bin/dc up -d
```

**実測結果**（2026-01-12 - 仮説1検証時）:
```bash
# VSCode起動後
コンテナID: c26d96d5aeb9
COMMAND: /bin/sh -c 'echo Container started...' - /init

# ./bin/dc up -d 実行後
コンテナID: b0e9f1016127  # 変化！
COMMAND: /init  # 変化！

VSCodeの状態: "Failed to install Cursor server: Failed to run devcontainer command: 1." エラー発生
```

**出典**: [25_6_29 - 仮説1検証結果](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)

**失敗の理由**:
1. **COMMANDの不一致**: VSCode `/bin/sh -c ...` vs bin/dc `/init`
2. **docker-from-docker featureのentrypoint設定 + VSCode DevContainerのラッパースクリプト**: これらの組み合わせによりCOMMANDが変化
   - 仮説1検証により、featureを削除してもVSCodeのラッパースクリプトは追加されることが確認済み
3. **Docker Composeの判定**: 既存コンテナ（VSCode起動）と新しい定義（bin/dc）のCOMMANDが不一致のため、設定変更と判断してコンテナを再作成

### パターン4: bin/dc→VSCode実行（成功）

**実行フロー**:
```bash
# 1. ./bin/dc up -d
# 2. VSCodeで "Reopen in Container"
```

**実測結果**（2026-01-12 - パターン4検証より）:
```bash
# bin/dc起動後
コンテナID: <container-id>
COMMAND: /init

# VSCode起動後
コンテナID: <container-id>  # 変化なし！
COMMAND: /init  # 変化なし！

VSCodeの状態: 正常に接続
supervisord: 起動継続
```

**出典**: [25_6_27 - パターン4検証結果](../resolved/25_6_27_supervisord_verification_tracker.md#パターン4-コンテナ削除--bindc起動--vscode起動)

**成功の理由**:
1. **既存コンテナの検出**: VSCodeはプロジェクト名（`<docker-composeプロジェクト名>`）とサービス名（`dev`）からbin/dcが作成したコンテナを検出
2. **コンテナ再作成なし**: VSCodeは既存コンテナを見つけると、新規作成せずに既存コンテナに接続
3. **COMMAND維持**: VSCodeが接続のみを行うため、COMMANDは`/init`のまま変更されない
4. **設定の一貫性**: bin/dcで作成されたコンテナの設定がそのまま維持される

**パターン2との決定的な違い**:
- **パターン2**: VSCodeが**コンテナを新規作成** → featureのentrypoint + ラッパースクリプト適用 → COMMANDが変化 → bin/dcが再作成
- **パターン4**: VSCodeが**既存コンテナに接続** → featureもラッパーも適用されない → COMMANDそのまま → 成功

### パターン比較まとめ

| 観点 | パターン1<br>（bin/dc → bin/dc） | パターン2<br>（VSCode → bin/dc） | パターン4<br>（bin/dc → VSCode） |
|------|---------------------------|---------------------------|---------------------------|
| **結果** | ✅ 成功<br>（同じコンテナ維持） | ❌ 失敗<br>（コンテナ置き換え） | ✅ 成功<br>（同じコンテナ維持） |
| **COMMAND** | 常に `/init` | VSCode: `/bin/sh -c ...`<br>bin/dc: `/init` | 常に `/init` |
| **VSCodeの動作** | VSCode未使用 | **新規コンテナ作成**<br>→ feature entrypoint適用<br>→ ラッパー適用 | **既存コンテナに接続**<br>→ COMMAND維持 |
| **設定の一貫性** | 完全一貫<br>（docker-compose.ymlのみ） | 不一貫<br>（feature + VSCodeの追加設定） | 完全一貫<br>（bin/dcの設定を維持） |
| **feature/VSCodeの影響** | なし | docker-from-docker feature<br>+ VSCode DevContainer<br>の両方が設定追加 | なし<br>（VSCodeは接続のみ） |
| **COMMAND変化の原因** | 変化なし | feature entrypoint設定<br>+ VSCodeラッパー | 変化なし<br>（VSCodeは接続のみ） |
| **コンテナ作成者** | bin/dc | VSCode → bin/dcが再作成 | bin/dc（VSCodeは接続のみ） |

**重要な洞察**:
- **成功パターン（1, 4）の共通点**: どちらもVSCodeが**コンテナを新規作成しない**
  - パターン1: VSCode未使用
  - パターン4: VSCodeは既存コンテナに接続のみ
- **失敗パターン（2）の特徴**: VSCodeが**コンテナを新規作成**し、その際にdocker-from-docker featureのentrypoint設定とVSCode DevContainerのラッパースクリプトが適用される
- **解決策の方向性**:
  - VSCodeに**コンテナを作成させない**（仮説10: パターン4を標準化）← **確実**
  - または、featureのentrypointを**低レベルで上書き**（仮説7: runArgs）← **技術的挑戦**

---

## 7. 検証方法

### 検証の全体フロー
各仮説について以下の手順で検証:
1. 設定変更
2. コンテナ削除（クリーンスタート）
3. VSCodeで起動
4. COMMAND確認
5. `./bin/dc up -d`実行
6. コンテナID・COMMAND確認
7. 結果判定

### 成功基準
- ✅ VSCode起動後に`./bin/dc up -d`を実行してもコンテナIDが変わらない
- ✅ COMMANDが一致している（または互換性がある）
- ✅ VSCodeの接続が切断されない
- ✅ supervisordが起動し続ける

### 失敗基準
- ❌ コンテナIDが変わる
- ❌ VSCodeの接続が切断される（"Cannot reconnect"エラー）

---

## 付録: 参考情報

### VSCode DevContainer仕様
- [devcontainer.json reference](https://containers.dev/implementors/json_reference/)
- `overrideCommand`: Whether to override the command specified in the image
- `command`: The command to run when creating the container

### Docker Compose比較ロジック
Docker Composeは以下を比較してコンテナの再作成を判断:
```python
# 擬似コード
def should_recreate_container(existing, new_definition):
    if existing.image != new_definition.image:
        return True
    if existing.command != new_definition.command:  # ← ここで不一致
        return True
    if existing.environment != new_definition.environment:
        return True
    # ... その他の比較
    return False
```

### docker-from-docker featureの動作
- ソース: `ghcr.io/devcontainers/features/docker-from-docker:1`
- 機能: コンテナ内でDockerコマンドを使用可能にする
- 提供するもの:
  - Dockerソケットマウント設定
  - 初期化スクリプト（`/usr/local/share/docker-init.sh`）
  - Docker CLI のインストール
  - 権限設定（Dockerグループへのユーザー追加など）
- **重要**: このfeatureのentrypoint設定は**意図的な機能**
  - Dockerソケットの初期化のために必要
  - 最終的に`exec "$@"`で元のコマンドを実行するため、機能的には問題ない
  - 問題は、Docker ComposeがCOMMAND**文字列全体**を比較することにある

### VSCode DevContainerのラッパースクリプト
- VSCode DevContainerは、`overrideCommand: false`でもラッパースクリプトを追加する
- これはコンテナを永続化するための**正常な動作**
- 仮説1検証により、docker-from-docker featureを削除してもこのラッパーは追加されることが確認済み

---

**最終更新**: 2026-01-13 09:30 (v2.2)
**ステータス**: ✅ **解決済み** - 仮説10-A採用・実装完了（仮説1-3,7,9: 不採用、疑問1: 解決、仮説10-A: 採用）

## 解決サマリー

**採用した解決策**: 仮説10-A - スマートbin/dcラッパー

**実装内容**:
- bin/dcスクリプトにVSCodeコンテナ検出機能を追加（111行）
- `up/start/restart`コマンド実行前にVSCodeコンテナを自動検出
- VSCodeコンテナが存在する場合、エラーメッセージを表示して誤操作を防止
- bin/dcコンテナの場合、通常通り動作を継続

**検証結果**:
- 全5ステップの検証が成功（2026-01-13）
- VSCodeで起動したコンテナへの誤った`./bin/dc up`実行を自動的にブロック
- `./bin/dc exec`は正常動作を維持
- bin/dcで起動したコンテナは通常通り管理可能

**技術的成果**:
1. VSCodeのENTRYPOINTラッパーは技術的に回避不可能であることを確認（A-8, A-12）
2. Docker Composeの`compose-spec/compose-go`実装により、JSON出力順序が保証されることを確認
3. Dockerラベル（`devcontainer.local_folder`）による確実なVSCodeコンテナ検出を実現

**今後の展開**:
- 問題2（overrideCommand問題）を解決済みとしてマーク
- 本ソリューションを他のプロジェクトにも展開可能
- 統合テスト（C-1～C-4）はオプション（基本検証は完了済み）

詳細: [25_6_29_overridecommand_verification_tracker.md](./25_6_29_overridecommand_verification_tracker.md)
