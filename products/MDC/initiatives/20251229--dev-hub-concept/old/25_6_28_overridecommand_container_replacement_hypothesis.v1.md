# overrideCommandによるコンテナ置き換え問題の仮説立案

**作成日**: 2026-01-12
**関連ドキュメント**:
- [25_6_24_devcontainer_existing_container_connection.md](./25_6_24_devcontainer_existing_container_connection.md)
- [25_6_27_supervisord_verification_tracker.md](../resolved/25_6_27_supervisord_verification_tracker.md)

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
    "overrideCommand": false
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
Docker ComposeがVSCodeのコンテナと`./bin/dc`のコンテナを**別の定義**として認識し、コンテナを再作成している。

### 技術的な詳細

#### VSCode起動時のCOMMAND
VSCode DevContainerは、`overrideCommand: false`設定を無視して独自のラッパースクリプトを追加する:
```bash
/bin/sh -c 'echo Container started
 trap "exit 0" 15
 /usr/local/share/docker-init.sh
 exec "$@"
 while sleep 1 & wait $!; do :; done' - /init
```

実質的には最後に`exec /init`を実行するが、Docker ComposeはCOMMAND文字列全体を比較する。

**出典**:
- 実測値: [25_6_27 - パターン2検証結果](../resolved/25_6_27_supervisord_verification_tracker.md#パターン2-コンテナ削除--vscode起動--bindc起動)より、`docker ps`で確認した実際のCOMMAND
- 検証結果: [25_6_29 - 仮説1検証](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)により、`docker-from-docker` feature削除後もVSCodeがCOMMANDを上書きすることが判明

**重要な発見**: `/usr/local/share/docker-init.sh`は`docker-from-docker` featureが追加するスクリプトだが、**このスクリプトの実行自体はVSCode DevContainerのCOMMAND上書き動作の一部**である。featureを削除してもVSCodeは同様の形式でCOMMANDを上書きする（仮説1検証結果より）

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
| **`command`** | docker-compose.ymlで未定義 → Dockerfile ENTRYPOINT `/init` | **1回目**: VSCode DevContainerが上書き `/bin/sh -c ...`<br>**2回目**: docker-compose.ymlで未定義 → Dockerfile ENTRYPOINT `/init` | ❌ |
| **`environment`** | `UNAME=<一般ユーザー>`, `MDC_REPO_ROOT=dev-hub` | `UNAME=<一般ユーザー>`, `MDC_REPO_ROOT=dev-hub` + VSCodeが追加する環境変数 | ⚠️ |
| **`volumes`** | `../:/home/<一般ユーザー>/dev-hub`, `repos:/home/.../repos` | 同左 + VSCodeのmounts設定 | ⚠️ |
| **`ports`** | `4035:4035`, `8035:8035`, `9001:9001`, `8080:8080` | 同左 | ✅ |
| **`networks`** | デフォルト（docker-compose.ymlで未定義） | 同左 | ✅ |
| **プロジェクト名** | `<docker-composeプロジェクト名>` | 同左 | ✅ |

**検証による重要な発見**:

仮説1の検証（[25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)）により、以下が判明:
- `docker-from-docker` featureを**削除しても**、VSCodeは依然としてCOMMANDを `/bin/sh -c 'echo Co…` に上書き
- つまり、**`docker-from-docker` featureが原因ではなく、VSCode DevContainer自体がCOMMANDを上書きしている**

この事実から、上記表の「VSCode DevContainerが上書き」という表現が正確である。

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
   - docker-compose.ymlの定義 + VSCode DevContainerが追加設定を適用
   - **VSCode DevContainer自体が`command`を上書き** → `/bin/sh -c 'echo Container started...' - /init`
     - 仮説1検証により、`docker-from-docker` featureの有無に関わらず上書きされることが確認済み
     - `devcontainer.json`の`overrideCommand: false`設定も無視される
   - VSCodeが環境変数やボリュームを追加（`mounts`設定）
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
- **パターン2が失敗する理由**: VSCodeが**新規コンテナを作成**し、その際にCOMMANDを上書き。その後bin/dcが「定義と異なる」と判断して再作成
- **パターン4が成功する理由**: bin/dcが**先にコンテナを作成**済み。VSCodeは既存コンテナを検出して**接続のみ**行うため、コンテナを再作成しない
- **鍵となる違い**: VSCodeが**コンテナを作成するか**（パターン2）、**既存コンテナに接続するか**（パターン4）の違い

**不一致の根本原因**:

パターン1では、Docker Composeが**同じdocker-compose.yml定義**を2回使用するため、期待される状態が完全に一致する。

パターン2では、VSCodeが**docker-compose.ymlに加えて追加設定を適用**するため、既存コンテナの状態がdocker-compose.ymlの定義と乖離する。その後bin/dcがdocker-compose.ymlのみで起動すると、Docker Composeは「定義が変わった」と判断してコンテナを再作成する。

##### より正確な表現

以下の項目が**docker-compose.ymlファイル内で定義されている場合**、それらが比較される:

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

本プロジェクトのdocker-compose.ymlには`command`フィールドが**定義されていない**ため、DockerfileのENTRYPOINTが使用される。VSCode DevContainerがコンテナを起動すると、`overrideCommand: false`設定にかかわらず、Dockerコンテナレベルで**実際のCOMMAND**が上書きされる。

**docker-compose.ymlにcommandを定義しても解決しない**:
仮説3検証（[25_6_29 - A-3](./25_6_29_overridecommand_verification_tracker.md#a-3-仮説3検証---docker-composeymlにcommand明示)）において、`services.dev.command: /init`を明示的に追加したが、VSCodeは依然として`/bin/sh -c 'echo Co…`を使用し、コンテナ起動に失敗した。これは、VSCode DevContainerが**docker-compose.ymlのcommand設定より後**にCOMMANDを上書きするためである。

つまり、以下の優先順位となる:
1. **最優先**: VSCode DevContainerのCOMMAND上書き（`/bin/sh -c ...`）
2. docker-compose.ymlの`command`設定（`/init`）← 無視される
3. DockerfileのENTRYPOINT（`/init`）

この**「docker-compose.ymlの定義から期待されるCOMMAND」と「実際に実行中のコンテナのCOMMAND」の不一致**により、Docker Composeがコンテナを再作成する。

**検証による確認**:
- 仮説1検証（[25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)）: `docker-from-docker` featureを削除してもVSCodeがCOMMANDを上書き
- 仮説2検証（[25_6_29 - A-2](./25_6_29_overridecommand_verification_tracker.md#a-2-仮説2検証---devcontainerjsonにcommand明示)）: `devcontainer.json`に`command`を追加しても上書きされる
- 仮説3検証（[25_6_29 - A-3](./25_6_29_overridecommand_verification_tracker.md#a-3-仮説3検証---docker-composeymlにcommand明示)）: `docker-compose.yml`に`command`を追加してもVSCodeが上書き、コンテナ起動失敗

**参考資料**:
- Docker Compose FAQ: [Why do my services take 10 seconds to recreate or stop?](https://docs.docker.com/compose/faq/#why-do-my-services-take-10-seconds-to-recreate-or-stop)
- Docker Compose仕様: [Compose Specification - services top-level element](https://github.com/compose-spec/compose-spec/blob/master/spec.md#services-top-level-element)

### 根本原因（検証済み）
`devcontainer.json`の`overrideCommand: false`設定が、VSCode DevContainer自体によって無視されている。

#### overrideCommandの意図
- `overrideCommand: false`: docker-compose.ymlのcommandを保持する
- `overrideCommand: true`: VSCodeがカスタムコマンドで上書きする

**出典**:
- Dev Container仕様: [devcontainer.json reference - overrideCommand](https://containers.dev/implementors/json_reference/#general-properties)
  > "overrideCommand: Tells VS Code whether it should run /bin/sh -c "while sleep 1000; do :; done" when starting the container instead of the container's default command. Defaults to true when using an image Dockerfile and false when using Docker Compose."

**重要な発見**: 公式仕様によると、Docker Composeモードでは`overrideCommand`のデフォルトは**false**。しかし、本プロジェクトでは明示的に`false`を設定しているにもかかわらず、VSCodeがコマンドを上書きしている。

#### 実際の動作（検証済み）
仮説1の検証（[25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)）により、以下が確定:

1. **`docker-from-docker` featureを削除しても**、VSCodeは依然としてCOMMANDを `/bin/sh -c 'echo Co…` に上書きする
2. **VSCode DevContainer自体**が`overrideCommand: false`設定を無視してCOMMANDを上書きしている
3. 仮説2・3検証により、`devcontainer.json`や`docker-compose.yml`に`command`を明示しても上書きされることが確認済み

**参考情報**:
- docker-from-docker feature実装: [devcontainers/features - docker-in-docker](https://github.com/devcontainers/features/tree/main/src/docker-in-docker)
  > このfeatureはDockerソケットマウントとラッパースクリプト（`/usr/local/share/docker-init.sh`）を提供するが、COMMAND上書き自体はfeatureではなくVSCode DevContainerが行う

**検証により判明した事実**:
- COMMAND上書きの原因: **VSCode DevContainer自体** (featureではない)
- `overrideCommand: false`が無視される理由: VSCode DevContainerの実装上の制限または仕様
- 解決には: VSCode側の設定では対処できない可能性が高く、別のアプローチ（仮説7以降）が必要

---

## 4. 仮説

### 仮説1: docker-from-docker featureがoverrideCommandを無視している ❌ 不採用
**内容**: VSCodeの`docker-from-docker` featureが、コンテナ起動時に独自のラッパースクリプトを強制的に追加し、`overrideCommand: false`設定を無視している。

**根拠**:
- VSCode起動時のCOMMANDに`/usr/local/share/docker-init.sh`が含まれる
- これは`docker-from-docker` featureが追加するスクリプト
- `overrideCommand: false`を設定しても、この動作が変わらない

**検証方法**: `docker-from-docker` featureを一時的に無効化し、COMMANDが`/init`になるか確認

**検証結果**: ❌ **不採用** (2026-01-12実施)
- featureを削除しても、VSCodeは依然としてCOMMANDを `/bin/sh -c 'echo Co…` に上書き
- **VSCode DevContainer自体**が原因であり、featureは無関係
- 詳細: [25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)

### 仮説2: devcontainer.jsonのcommandプロパティで明示的に指定すれば回避できる
**内容**: `devcontainer.json`に`command`プロパティを明示的に設定することで、docker-compose.ymlのcommandと一致させられる。

**根拠**:
- VSCodeのドキュメントに`command`プロパティが存在する
- Docker Composeモードでも`command`が使用できる可能性がある

**検証方法**: `devcontainer.json`に`"command": "/init"`を追加して動作確認

### 仮説3: docker-compose.ymlにcommandを明示的に指定すれば統一できる
**内容**: docker-compose.ymlに`command: /init`を明示的に記述することで、Docker ComposeがVSCodeのコンテナを認識しやすくなる。

**根拠**:
- 現在は`command`が未指定（デフォルト動作に依存）
- 明示的に指定すれば、Docker Composeの比較対象が明確になる
- ただし、VSCodeのラッパースクリプトが優先される可能性は残る

**検証方法**: docker-compose.ymlに`command: /init`を追加して、パターン2を再検証

### 仮説4: VSCodeのlifecycleCommandsで起動後にコンテナを再定義できる
**内容**: VSCodeの`postStartCommand`や`postAttachCommand`を使用して、コンテナ起動後に何らかの調整を行う。

**根拠**:
- DevContainer仕様にライフサイクルコマンドが存在する
- 起動後の処理でDocker Composeとの整合性を取れる可能性

**検証方法**: `postStartCommand`でDocker Composeのメタデータを更新するスクリプトを実行

### 仮説5: runArgsでCOMMANDを上書きできる
**内容**: `devcontainer.json`の`runArgs`にコマンド指定オプションを追加することで、VSCode DevContainerのCOMMAND上書きを回避できる。

**根拠**:
- `runArgs`はdocker runの引数を直接制御できる
- `--entrypoint`や`--command`オプションで上書きできる可能性
- 仮説1検証により、問題の原因がfeatureではなくVSCode DevContainer自体と判明したため、より低レイヤーでの制御が必要

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

### 仮説7: runArgsで--entrypointを強制する

**内容**: `devcontainer.json`の`runArgs`に`--entrypoint /init`を追加し、VSCode DevContainerのCOMMAND上書き動作を回避する。

**根拠**:
- `runArgs`はdocker runの引数を直接制御できる
- `--entrypoint`フラグはVSCode DevContainerのCOMMAND上書きより優先される可能性
- 仮説1検証により、VSCode DevContainer自体が原因と判明したため、docker run引数レベルでの制御が必要

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

**懸念点**:
- docker-from-docker featureの初期化スクリプト（`/usr/local/share/docker-init.sh`）が実行されない可能性
- Dockerソケットマウントは`volumes`設定で行われるため機能するはずだが、feature固有の権限設定が失われる可能性

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
- docker-from-docker featureのentrypoint上書きが問題の根本原因と推測
- ソケットマウントだけでDocker操作は可能

**検証済み**: ❌ **仮説1で既に検証済み・不採用** (2026-01-12)
- docker-from-docker featureを削除しても、**VSCode DevContainer自体**がCOMMANDを上書き
- featureは原因ではなかった
- 詳細: [25_6_29 - A-1](./25_6_29_overridecommand_verification_tracker.md#a-1-仮説1検証---docker-from-docker-feature無効化)

**重要な発見**:
- COMMAND上書きの真の原因は、featureではなく**VSCode DevContainerの動作そのもの**
- featureの有無に関わらず、VSCodeは`overrideCommand: false`を無視してCOMMANDを上書きする

### 仮説10: VSCode側でコンテナを作らず、bin/dcで先に起動してからVSCodeで接続

**内容**: パターン4（bin/dc起動 → VSCode起動）を標準ワークフローとして採用する。

**アプローチ**:
1. 開発開始時に`./bin/dc up -d`を必ず実行
2. その後、VSCodeで "Reopen in Container"
3. VSCodeは既存コンテナに接続（新規作成しない）

**根拠**:
- パターン4は既に成功している（検証済み）
- VSCodeは既存コンテナを検出すると、それを使用する

**出典**: [25_6_27 - パターン4検証結果](../resolved/25_6_27_supervisord_verification_tracker.md#パターン4-コンテナ削除--bindc起動--vscode起動)

**メリット**:
- 技術的な回避策が不要
- 既存の設定で動作する
- bin/dcとVSCodeの両方で使える

**デメリット**:
- 開発者が手順を覚える必要がある
- VSCode単独での起動ができない（柔軟性の低下）

---

## 5. パターン比較分析

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
2. **一貫性**: bin/dcはdocker-compose.ymlだけを使用（外部ツールによる上書きなし）
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
2. **VSCode DevContainer自体によるCOMMAND上書き**: `overrideCommand: false`やdocker-compose.ymlの設定を無視
   - 仮説1検証により、`docker-from-docker` featureを削除しても上書きされることが確認済み
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
- **パターン2**: VSCodeが**コンテナを新規作成** → COMMANDを上書き → bin/dcが再作成
- **パターン4**: VSCodeが**既存コンテナに接続** → COMMANDそのまま → 成功

### パターン比較まとめ

| 観点 | パターン1<br>（bin/dc → bin/dc） | パターン2<br>（VSCode → bin/dc） | パターン4<br>（bin/dc → VSCode） |
|------|---------------------------|---------------------------|---------------------------|
| **結果** | ✅ 成功<br>（同じコンテナ維持） | ❌ 失敗<br>（コンテナ置き換え） | ✅ 成功<br>（同じコンテナ維持） |
| **COMMAND** | 常に `/init` | VSCode: `/bin/sh -c ...`<br>bin/dc: `/init` | 常に `/init` |
| **VSCodeの動作** | VSCode未使用 | **新規コンテナ作成**<br>→ COMMAND上書き | **既存コンテナに接続**<br>→ COMMAND維持 |
| **設定の一貫性** | 完全一貫<br>（docker-compose.ymlのみ） | 不一貫<br>（VSCodeが追加設定） | 完全一貫<br>（bin/dcの設定を維持） |
| **外部ツールの影響** | なし | VSCode DevContainer自体が<br>設定を上書き | なし<br>（VSCodeは接続のみ） |
| **COMMAND上書きの原因** | 上書きなし | VSCode DevContainer<br>（`overrideCommand: false`を無視） | 上書きなし<br>（VSCodeは接続のみ） |
| **コンテナ作成者** | bin/dc | VSCode → bin/dcが再作成 | bin/dc（VSCodeは接続のみ） |

**重要な洞察**:
- **成功パターン（1, 4）の共通点**: どちらもVSCodeが**コンテナを新規作成しない**
  - パターン1: VSCode未使用
  - パターン4: VSCodeは既存コンテナに接続のみ
- **失敗パターン（2）の特徴**: VSCodeが**コンテナを新規作成**し、その際にCOMMANDを上書き
- **解決策の方向性**:
  - VSCodeに**コンテナを作成させない**（仮説10: パターン4を標準化）
  - または、VSCodeのCOMMAND上書きを**低レベルで阻止**（仮説7: runArgs）

---

## 6. 検証方法

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
- **重要**: 仮説1検証により、このfeature自体はCOMMAND上書きの原因ではないことが確認済み
  - COMMAND上書きは**VSCode DevContainer自体**が行う
  - featureを削除してもVSCodeは同様にCOMMANDを上書きする

---

**最終更新**: 2026-01-12
**ステータス**: 仮説立案完了、検証待ち
**次のアクション**: 検証トラッカーを作成し、仮説1から順に検証を実施
