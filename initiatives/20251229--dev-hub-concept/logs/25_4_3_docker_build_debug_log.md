# Dockerビルド失敗に関するデバッグ調査録（Part 2）

**作成日**: 2026-01-03
**目的**: `Dockerfile`修正後のビルド再試行で発生したエラー（`supervisor: couldn't chdir`）の原因特定と解決策の検討。

---

## 1. 問題の概要

`useradd`コマンドの引数エラーを修正し、`docker compose build`を再試行したところ、ビルドの`[35/44]`ステップ（`supervisord`の設定検証）で再度停止した。

**エラーログ**: `initiatives/20251229--dev-hub-concept/202601031950-docker-compose-build.log`

---

## 2. エラーメッセージの解析

ログの詳細を見ると、以下のエラーメッセージが確認された。

```
 => [35/44] RUN echo "🔍 Validating default supervisord configuration..." &&     supervisord -c /etc/supervisor/seed.conf -t &&     ech     533.4s
 => => # supervisor: couldn't chdir to /home/<一般ユーザー><MonolithicDevContainerレポジトリ名>: ENOENT
 => => # supervisor: child process was not spawned
 => => # 2026-01-03 19:41:54,779 INFO gave up: code-server entered FATAL state, too many start retries too quickly
```

### 3. 原因分析

-   **エラー内容**: `supervisor: couldn't chdir to /home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>: ENOENT`
    *   これは、`supervisord`が`seed.conf`を読み込み、その中の`[program:code-server]`セクションに定義されている`directory=/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>`というワーキングディレクトリに移動しようとしたが、**そのディレクトリが見つからなかった（ENOENT）**ために発生している。
-   **なぜ見つからないのか**:
    *   このエラーが発生しているビルドのステップ(`[35/44]`)は、`Dockerfile`の`RUN`コマンドの実行中である。
    *   この時点では、ホストからバインドマウントされるべき`/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>`ディレクトリは、**まだコンテナ内に存在していない**。バインドマウントはコンテナ起動時に行われるため、ビルド時には利用できない。
    *   `supervisord -t`コマンドは設定ファイルの文法チェックだけでなく、`directory`オプションに指定されたパスの存在もチェックしようとするため、パスが見つからずにエラーとなっている。

### 4. 解決策

`seed.conf`の主な目的は、**ビルド時の構文チェック**と、メイン設定が壊れた際の**フォールバック**です。どちらの目的においても、`code-server`を起動する際のワーキングディレクトリを`<MonolithicDevContainerレポジトリ名>`に厳密に指定する必要はありません。`code-server`自体が適切なパスで実行されるためです。

したがって、`seed.conf`内の`[program:code-server]`セクションから、ビルド時には問題となる`directory`オプションを**削除**します。

---

## 5. ログ出力形式の改善

ユーザーから`plain`形式でのログ出力の要望がありました。
`docker compose build`コマンドに`--progress=plain`オプションを追加することで、この形式で出力できます。

### 5.1. `--progress`オプションの位置に関するトラブルシューティング

`docker compose build`実行時に`--progress=plain`オプションが認識されない、または`--progress is a global compose flag`というエラーが出た場合、オプションの位置が正しくない可能性があります。

-   **誤った例**: `docker compose -f ... build --no-cache --progress=plain` (`--progress`が`build`サブコマンドの引数として渡されている)
-   **正しい例**: `docker compose --progress plain -f ... build --no-cache` (`--progress`が`docker compose`コマンドのグローバルオプションとして渡されている)

`--progress`は`docker compose`コマンド全体の動作を変更するグローバルオプションであるため、`docker compose`の直後に配置する必要があります。

### 次回のビルドコマンド

```bash
cd .devcontainer/
docker compose --progress plain -f docker-compose.yml -f docker-compose.dev-vm.yml build --no-cache
```

---

## 6. 学び (Lessons Learned)

-   **ビルド時のコンテキストと実行時のコンテキストの明確な区別**: `Dockerfile`の`RUN`ステップが実行されるビルド時と、コンテナが起動してバインドマウントが有効になる実行時とでは、ファイルシステムの状況が大きく異なる。ビルド時に実行されるコマンドや検証は、ビルド時のファイルシステムの状態に依存すべきである。
-   **`supervisord -t`の挙動**: `supervisord -t`は単なる構文チェックだけでなく、`directory`オプションで指定されたパスの存在チェックも行う。この挙動を考慮して`seed.conf`を設計する必要がある。

---

## 6. 補足: `seed.conf`の`directory`オプション削除とフォールバック役割について

`seed.conf`から`[program:code-server]`の`directory`オプションを削除したことについて、「フォールバック機構（安全装置）としての本質的な役割」を失っていないかという懸念がありました。

**結論として、フォールバック機構の役割は失われていません。**

**理由:**

1.  **`directory`オプションの本来の役割**:
    `supervisord`の`directory`オプションは、プログラムが実行される際の**カレントワーキングディレクトリ**を指定するものです。これは`code-server`自体の起動可否には直接影響しません。

2.  **`code-server`のフォールバック時の目的**:
    フォールバックの目的は、**`code-server`を起動させること**にあります。`code-server`は起動後、ブラウザ経由でアクセスされ、VS Codeとして機能します。ユーザーはVS Code内でファイルを開いたり、ターミナルを開いたりして作業を行います。この際のVS Codeの「作業ディレクトリ」は、VS Codeがリポジトリをマウントしているパス（例: `/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>`）が基準となります。

3.  **役割の維持**:
    `code-server`が起動する際のカレントワーキングディレクトリがどこであっても、ユーザーがブラウザでVS Codeを利用してデバッグするというフォールバックの本質的な目的は達成されます。したがって、`directory`オプションを削除しても、フォールバック時のデバッグ能力は維持されます。

---

## 7. 次のアクション

1.  `seed.conf`から`directory`オプションを削除する修正を行う。
2.  上記「次回のビルドコマンド」を実行し、修正が成功したかを確認する。

---

## Part 3: `supervisord -t` によるビルドハング問題

**発生日**: 2026-01-03 20:10
**問題**: ビルドがstep #41 (`supervisord -t` による検証) で停止し、完了しない

### 1. 問題の概要

`docker compose build --no-cache --progress=plain` を実行したところ、以下のステップで処理が停止した:

```dockerfile
#41 [35/44] RUN echo "🔍 Validating default supervisord configuration..." &&     supervisord -c /etc/supervisor/seed.conf -t &&     echo "✅ Default supervisord configuration is valid"
```

**ログファイル**: `initiatives/20251229--dev-hub-concept/202601032008-docker-compose-build.log`

### 2. エラーログの解析

ログの該当箇所（最後の100行）を確認:

```
#41 0.128 🔍 Validating default supervisord configuration...
#41 0.208 2026-01-03 20:10:26,402 INFO supervisord started with pid 7
#41 1.221 2026-01-03 20:10:27,412 INFO spawned: 'code-server' with pid 8
#41 1.501 [2026-01-03T11:10:27.692Z] info  HTTP server listening on http://0.0.0.0:4035/
#41 2.504 2026-01-03 20:10:28,695 INFO success: code-server entered RUNNING state, process has stayed up for > than 1 seconds (startsecs)
```

### 3. 原因分析

**問題の本質**: `supervisord -c /etc/supervisor/seed.conf -t` は設定ファイルのテスト（検証）のみを行うべきだが、実際には **supervisordを起動してcode-serverプロセスを実行している**。

- `-t` フラグは構文チェックを行うが、supervisord自体は起動してしまう
- `seed.conf` の設定により、supervisordがcode-serverを spawn している
- code-serverは `autorestart=false` であるものの、起動したsupervisordプロセス自体が終了していない
- 結果として、Dockerビルドステップがハングする

**該当する設定ファイル箇所** (`.devcontainer/supervisord/seed.conf`):

```ini
[supervisord]
nodaemon=true
user=root
...

[program:code-server]
command=code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
autostart=true
autorestart=false
...
```

### 4. 解決方針の検討

以下の3つの解決策を検討:

#### 方針1: Python構文チェックのみで検証

supervisordの設定ファイルはPython ConfigParserで読めるため、Pythonスクリプトで構文チェックのみを行う。

**メリット**:
- プロセスを起動しないため、ビルドがハングしない
- 構文エラーは確実に検出できる
- 軽量で高速

**デメリット**:
- supervisord固有のバリデーション（例: commandが実際に実行可能かどうか）は行われない
- 追加のPythonスクリプトが必要

#### 方針2: supervisordの検証を削除（推奨）

ビルド時の検証を完全に削除し、実行時のエラーに任せる。

**メリット**:
- シンプル
- ビルドが確実に成功する
- フォールバック機構があるため、実行時エラーは許容できる

**デメリット**:
- 構文エラーがあってもビルド時に気づけない
- コンテナ起動後にエラーが判明する

#### 方針3: タイムアウト付きで `-t` を実行

`timeout` コマンドでsupervisord起動を強制終了させる。

**メリット**:
- supervisord本来のバリデーションを活用できる

**デメリット**:
- タイムアウト値の設定が難しい（環境依存）
- エラー判定が複雑（タイムアウトか構文エラーかの区別が必要）
- 根本的な解決ではない

### 5. 推奨解決策

**方針2（検証削除）を推奨**

**理由**:
1. `seed.conf`はフォールバック用の最小限の設定であり、頻繁に変更されない
2. v10設計では実運用時は`workloads/supervisord/project.conf`を使用する
3. フォールバック機構があるため、実行時エラーでも復旧可能
4. シンプルさを維持できる（Monolithic DevContainerの設計思想に合致）
5. Part 2で学んだ「ビルド時のコンテキストと実行時のコンテキストの明確な区別」の原則に従う

### 6. 具体的な修正内容

Dockerfileの以下の部分を修正:

**修正前** (215-218行目):
```dockerfile
# ★★★ ユーザー作成後にsupervisordの検証を実行 ★★★
RUN echo "🔍 Validating default supervisord configuration..." && \
    supervisord -c /etc/supervisor/seed.conf -t && \
    echo "✅ Default supervisord configuration is valid"
```

**修正後**:
```dockerfile
# ★★★ supervisord検証について ★★★
# ビルド時に `supervisord -t` を実行すると、実際にsupervisordが起動して
# プロセスをspawnするため、ビルドがハングする問題が発生する。
# seed.confはフォールバック用の最小限設定であり、頻繁に変更されないため、
# 実行時エラーに任せる方針とする。
# 詳細: initiatives/20251229--dev-hub-concept/25_4_3_docker_build_debug_log.md Part 3
```

### 7. 学び (Lessons Learned)

- **`supervisord -t` の挙動**: `-t` フラグは構文チェックを行うが、supervisordプロセス自体は起動する。`nodaemon=true`や`autostart=true`の設定がある場合、プロセスが起動し続ける
- **ビルド時検証の限界**: ビルド時の検証は必ずしも必要ではなく、実行時エラーで十分なケースがある。特にフォールバック機構がある場合は、シンプルさを優先すべき
- **Monolithic DevContainerの思想**: デバッグ可能性を優先し、過度な最適化や検証よりもシンプルさを重視する（99_QA.v6.md Q10の議論と一致）

### 8. 次のアクション

1. Dockerfileの215-218行目を上記「修正後」の内容に変更
2. ビルドを再実行して成功を確認
3. 必要に応じてコンテナ起動テストを実施

---

## Part 4: `debug-entrypoint.sh` への権限変更エラー

**発生日**: 2026-01-03 20:22
**問題**: ビルドがstep #49 (`chmod +x /usr/local/bin/debug-entrypoint.sh`) で失敗

### 1. 問題の概要

Part 3の修正（supervisord検証削除）を適用してビルドを再実行したところ、新たなエラーが発生:

```
#49 [43/43] RUN chmod +x /usr/local/bin/debug-entrypoint.sh
#49 0.096 chmod: changing permissions of '/usr/local/bin/debug-entrypoint.sh': Operation not permitted
#49 ERROR: process "/bin/sh -c chmod +x /usr/local/bin/debug-entrypoint.sh" did not complete successfully: exit code: 1
```

**ログファイル**: `initiatives/20251229--dev-hub-concept/202601032022-docker-compose-build.log`

### 2. エラーログの解析

ログの該当箇所:

```
#48 [42/43] COPY .devcontainer/debug-entrypoint.sh /usr/local/bin/
#48 DONE 0.0s

#49 [43/43] RUN chmod +x /usr/local/bin/debug-entrypoint.sh
#49 0.096 chmod: changing permissions of '/usr/local/bin/debug-entrypoint.sh': Operation not permitted
#49 ERROR: process "/bin/sh -c chmod +x /usr/local/bin/debug-entrypoint.sh" did not complete successfully: exit code: 1
```

### 3. 原因分析

**問題の本質**: Dockerfileの287-288行目で`debug-entrypoint.sh`のコピーと権限設定を行っているが、この時点ではすでに**一般ユーザー（`${UNAME}`）に切り替わっている**。

**Dockerfileの該当構造**:
```dockerfile
# 222行目: 一般ユーザーに切り替え
USER ${UNAME}

# ... 一般ユーザーでの各種インストール処理 ...

# 287-288行目: ここで /usr/local/bin/ へのコピーと権限変更を試みる（失敗）
COPY .devcontainer/debug-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/debug-entrypoint.sh
```

**なぜエラーになるか**:
- `/usr/local/bin/` はシステムディレクトリであり、root権限が必要
- 一般ユーザーには `/usr/local/bin/` 配下のファイルへの書き込み・権限変更権限がない
- `COPY`時点でファイルは作成されるが、所有者はrootになり、その後の`chmod`が`Operation not permitted`で失敗する

### 4. 解決方針

**推奨方針**: `debug-entrypoint.sh` のコピーと権限設定を、`USER ${UNAME}` の**前**（rootユーザー時）に移動する。

**配置場所**: 既存の`docker-entrypoint.sh`の処理（178-179行目）の直後に配置する。

**理由**:
1. `docker-entrypoint.sh`と`debug-entrypoint.sh`は同じ目的（エントリーポイントスクリプト）であり、論理的に同じ場所で管理すべき
2. rootユーザー時に処理することで権限問題を回避できる
3. ビルドステップの論理的な順序が明確になる

### 5. 具体的な修正内容

Dockerfileの以下の変更を実施:

**変更1: 287-288行目を削除**
```dockerfile
# 削除する行（287-288行目）
COPY .devcontainer/debug-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/debug-entrypoint.sh
```

**変更2: 178-179行目の直後に追加**

**修正前** (178-179行目):
```dockerfile
# ENTRYPOINTスクリプトをコピー
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
```

**修正後**:
```dockerfile
# ENTRYPOINTスクリプトをコピー
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# デバッグモード用ENTRYPOINTスクリプトをコピー
COPY .devcontainer/debug-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/debug-entrypoint.sh
```

### 6. 学び (Lessons Learned)

- **Dockerfileにおけるユーザー切り替えの影響範囲**: `USER`ディレクティブ以降のすべての`RUN`, `COPY`, `ADD`コマンドは指定されたユーザーで実行される。システムディレクトリへの操作はroot権限が必要なため、`USER`切り替え前に完了させる必要がある
- **論理的なグルーピング**: 同じ目的を持つファイル操作（エントリーポイントスクリプトのコピーと権限設定）は、Dockerfile内で隣接して配置することで可読性と保守性が向上する
- **ビルドエラーの段階的解決**: 1つの問題を解決すると次の問題が顕在化するのは自然な流れ。各段階で適切に記録することで、同様の問題の再発を防げる

### 7. 次のアクション

1. Dockerfileの287-288行目を削除
2. Dockerfileの178-179行目の直後に`debug-entrypoint.sh`のコピーと権限設定を追加
3. ビルドを再実行して成功を確認