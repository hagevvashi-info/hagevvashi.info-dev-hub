# s6-rc サービスが登録されていない問題の調査と分析

**作成日**: 2026-01-04
**発生状況**: DevContainer ビルド後、セクションD検証時
**前提**: `25_6_3_docker_entrypoint_fix_implementation_tracker.md` のセクションA-Cは完了済み

---

## 1. 問題の発生経緯

### 1.1 実施した作業

`25_6_3_docker_entrypoint_fix_implementation_tracker.md` に従い、以下を完了:

- **セクションA**: s6-rc.d サービス定義の修正（type, up, user登録）
- **セクションB**: デバッグログの追加
- **セクションC**: git commit と PR作成

### 1.2 発生した問題

DevContainer 再ビルド後、セクションD-2 の検証コマンドを実行:

```bash
<一般ユーザー>@8c255c35141f:~/hagevvashi.info-dev-hub$ s6-rc -d list | grep docker-entrypoint
bash: s6-rc: command not found
```

**エラー**: `s6-rc: command not found`

---

## 2. 調査結果

### 2.1 PID 1 の確認

```bash
$ ps -p 1 -o comm=
s6-svscan
```

**結果**: ✅ s6-overlay は正常に動作している（PID 1 は `s6-svscan`）

### 2.2 s6-overlay のインストール確認

```bash
$ ls -la /init
-rwxr-xr-x 1 root root 1012 Nov 21  2023 /init

$ ls -la /command/ | head -5
lrwxrwxrwx 1 root root    44 Nov 21  2023 background -> ../package/admin/execline/command/background
lrwxrwxrwx 1 root root    42 Nov 21  2023 backtick -> ../package/admin/execline/command/backtick
...
```

**結果**: ✅ s6-overlay はインストールされている

### 2.3 PATH の確認

```bash
$ echo $PATH
/home/<一般ユーザー>/.cursor-server/bin/.../bin/remote-cli:/home/<一般ユーザー>/.tfenv/bin:/home/<一般ユーザー>/.asdf/bin:/home/<一般ユーザー>/.asdf/shims:/home/<一般ユーザー>/.local/bin:...(略)...:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

**観察**: `/command` が PATH に含まれていない

**補足調査**:
```bash
$ ls -la /usr/bin/s6-rc
ls: cannot access '/usr/bin/s6-rc': No such file or directory

$ which s6-rc
which: no s6-rc in (PATH...)
```

`/usr/bin` にもシンボリックリンクが存在しない。これは `s6-overlay-symlinks-arch.tar.xz` がインストールされていないため。

### 2.4 s6-rc コマンドの存在確認

```bash
$ find /command -name "s6-rc" 2>/dev/null
/command/s6-rc
```

**結果**: ✅ `/command/s6-rc` は存在する（PATH の問題）

### 2.5 フルパスで s6-rc を実行

```bash
$ /command/s6-rc -d list
s6rc-oneshot-runner
s6rc-fdholder
fix-attrs
legacy-cont-init
legacy-services

$ /command/s6-rc -d list | grep docker-entrypoint
(出力なし)
```

**問題**: ❌ `docker-entrypoint`、`supervisord`、`process-compose` のどれも登録されていない

### 2.6 s6-rc コンパイル済みデータベースの確認

```bash
$ ls -la /run/s6/db/servicedirs/
drwxr-xr-x 3 <一般ユーザー> dialout 100 Jan  4 19:55 s6rc-fdholder
drwxr-xr-x 3 <一般ユーザー> dialout 100 Jan  4 19:55 s6rc-oneshot-runner
```

**問題**: ❌ カスタムサービスがコンパイル済みデータベースに含まれていない

### 2.7 s6-overlay サービスソースディレクトリの確認

```bash
$ ls -la /etc/s6-overlay/s6-rc.d/
drwxr-xr-x 4 root root 4096 Nov 21  2023 .
drwxr-xr-x 3 root root 4096 Nov 21  2023 ..
drwxr-xr-x 3 root root 4096 Nov 21  2023 user
drwxr-xr-x 3 root root 4096 Nov 21  2023 user2

$ ls -la /etc/s6-overlay/s6-rc.d/user/contents.d/
(空ディレクトリ)
```

**問題**: ❌ `/etc/s6-overlay/s6-rc.d/user/contents.d/` が空（カスタムサービスが存在しない）

### 2.8 誤ったコピー先の確認

```bash
$ ls -la /etc/s6-rc.d/
(存在するが、s6-overlayはこのディレクトリを参照しない)
```

---

## 3. 根本原因の特定

### 3.1 Dockerfile の問題箇所

`.devcontainer/Dockerfile` の118行目:

```dockerfile
# s6-rc service definitions
COPY .devcontainer/s6-rc.d /etc/s6-rc.d
RUN find /etc/s6-rc.d -name "run" -exec chmod +x {} \;
```

**問題**: コピー先が `/etc/s6-rc.d` になっているが、s6-overlay v3 は **`/etc/s6-overlay/s6-rc.d/`** を参照する。

### 3.2 s6-overlay v3 のディレクトリ構造

s6-overlay v3 では、カスタムサービス定義は以下のディレクトリに配置する必要がある:

```
/etc/s6-overlay/s6-rc.d/
├── user/
│   └── contents.d/
│       ├── docker-entrypoint  # ← サービスを登録
│       ├── supervisord        # ← サービスを登録
│       └── process-compose    # ← サービスを登録
├── docker-entrypoint/
│   ├── type
│   ├── up
│   └── dependencies.d/
├── supervisord/
│   ├── type
│   ├── run
│   └── dependencies.d/
└── process-compose/
    ├── type
    ├── run
    └── dependencies.d/
```

**参考**: [s6-overlay documentation - Customizing s6-overlay behaviour](https://github.com/just-containers/s6-overlay#customizing-s6-overlay-behaviour)

### 3.3 なぜ問題が見逃されたか

1. **実装トラッカーの完了基準が不十分**:
   - `25_4_2_v10_implementation_tracker.md` Phase 1 には「s6-rc -d list でサービスが認識される」という動作確認基準が含まれていなかった
   - ファイルをコピーしただけで「完了」とマークされた

2. **検証プロセスの欠如**:
   - ビルド時に `s6-rc -d list` で確認していれば、この問題は早期に発見できた
   - Dockerfile に検証ステップが含まれていない

3. **ドキュメント参照不足**:
   - s6-overlay の公式ドキュメントを十分に確認せず、推測でディレクトリパスを決定した可能性

---

## 4. 仮説: なぜ `/etc/s6-rc.d` にコピーしてしまったのか

### 仮説1: s6-overlay v2 との混同

s6-overlay v2 では `/etc/services.d/` を使用していたが、v3 では `/etc/s6-overlay/s6-rc.d/` に変更された。v2 のドキュメントやサンプルを参考にした可能性がある。

### 仮説2: ディレクトリ名の類推

`s6-rc` というコマンド名から、`/etc/s6-rc.d/` というディレクトリ名を類推した可能性がある。実際には `/etc/s6-overlay/` 配下に配置する必要がある。

### 仮説3: テンプレートやサンプルコードの誤用

他のプロジェクトのDockerfileをコピーした際、s6-overlayのバージョンが異なり、ディレクトリパスが古いままだった可能性がある。

---

## 5. 解決のアプローチ

### アプローチ1: Dockerfile のコピー先を修正（最小修正）

**変更内容**:

```dockerfile
# 修正前
COPY .devcontainer/s6-rc.d /etc/s6-rc.d
RUN find /etc/s6-rc.d -name "run" -exec chmod +x {} \;

# 修正後
COPY .devcontainer/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN find /etc/s6-overlay/s6-rc.d -name "run" -exec chmod +x {} \; && \
    find /etc/s6-overlay/s6-rc.d -name "up" -exec chmod +x {} \;
```

**利点**:
- 最小限の変更で問題を解決
- v10 設計に準拠

**欠点**:
- 検証ステップが含まれていないため、同様の問題が再発する可能性

---

### アプローチ2: 最小修正 + ビルド時検証（推奨）

**変更内容**:

```dockerfile
# s6-rc service definitions
COPY .devcontainer/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN find /etc/s6-overlay/s6-rc.d -name "run" -exec chmod +x {} \; && \
    find /etc/s6-overlay/s6-rc.d -name "up" -exec chmod +x {} \;

# Validate s6-rc service definitions
# Note: s6-overlay compiles services at runtime, so we validate source structure here
RUN echo "🔍 Validating s6-rc service definitions..." && \
    # Check that user bundle exists
    test -d /etc/s6-overlay/s6-rc.d/user || { echo "❌ user bundle not found"; exit 1; } && \
    # Check that each service in user/contents.d has a corresponding service directory
    for service in $(ls /etc/s6-overlay/s6-rc.d/user/contents.d/ 2>/dev/null || true); do \
        if [ ! -d "/etc/s6-overlay/s6-rc.d/$service" ]; then \
            echo "❌ Service directory for '$service' not found in /etc/s6-overlay/s6-rc.d/"; \
            exit 1; \
        fi; \
        if [ ! -f "/etc/s6-overlay/s6-rc.d/$service/type" ]; then \
            echo "❌ Service '$service' missing type file"; \
            exit 1; \
        fi; \
        TYPE=$(cat /etc/s6-overlay/s6-rc.d/$service/type); \
        if [ "$TYPE" = "oneshot" ] && [ ! -x "/etc/s6-overlay/s6-rc.d/$service/up" ]; then \
            echo "❌ Oneshot service '$service' missing executable 'up' script"; \
            exit 1; \
        fi; \
        if [ "$TYPE" = "longrun" ] && [ ! -x "/etc/s6-overlay/s6-rc.d/$service/run" ]; then \
            echo "❌ Longrun service '$service' missing executable 'run' script"; \
            exit 1; \
        fi; \
        echo "✅ Service '$service' validated"; \
    done && \
    echo "✅ All s6-rc service definitions are valid"
```

**利点**:
- ビルド時に早期エラー検出（Fail Fast）
- 実装トラッカーの完了基準（「s6-rc -d list でサービスが認識される」）を間接的に保証
- 同様の問題の再発を防止

**欠点**:
- Dockerfile が長くなる
- 検証ロジックの保守が必要

---

### アプローチ3: 最小修正 + ビルド後検証スクリプト

**変更内容**:

1. Dockerfile でコピー先を修正（アプローチ1と同じ）
2. `.devcontainer/scripts/validate-s6-services.sh` を作成
3. devcontainer.json の `postCreateCommand` で検証スクリプトを実行

**利点**:
- ビルド後の実行時に検証
- 検証ロジックが分離されてメンテナンスしやすい

**欠点**:
- ビルド時にエラーを検出できない（コンテナ起動後に失敗する）

---

### アプローチ4: 最小修正 + 実装トラッカー更新

**変更内容**:

1. Dockerfile でコピー先を修正（アプローチ1と同じ）
2. `25_4_2_v10_implementation_tracker.md` Phase 1 の完了基準を更新:

```markdown
### Phase 1: s6-overlay導入（PID 1変更）
- [x] Dockerfileにs6-overlayをインストールし、ENTRYPOINTを`/init`に変更
- [x] `.devcontainer/s6-rc.d/` にサービス定義を作成
- [x] Dockerfileで `/etc/s6-overlay/s6-rc.d/` にコピー
  - 完了基準:
    - [ ] コピー先が `/etc/s6-overlay/s6-rc.d/` である
    - [ ] ビルド後、`/command/s6-rc -d list` にカスタムサービスが含まれる
  - 確認者: ________________
```

**利点**:
- プロセス改善により同様の問題を防止
- 実装トラッカーの信頼性向上

**欠点**:
- 人的ミスの可能性は残る

---

## 6. 推奨する解決策

**アプローチ2（最小修正 + ビルド時検証）** を推奨します。

**理由**:
1. **Fail Fast**: ビルド時にエラーを検出し、問題を早期に発見
2. **Gemini のフィードバックに対応**: 「再発防止策の自動化」を実現
3. **実装トラッカーの完了基準を自動保証**: 「s6-rc -d list でサービスが認識される」をビルド時に間接的に検証

---

## 7. 追加の考察

### 7.1 PATH の問題と s6-overlay の設計思想

#### 公式ドキュメントの調査結果

s6-overlay の公式ドキュメント ([GitHub](https://github.com/just-containers/s6-overlay)) によると:

> **"it is normally not needed, all the scripts are accessible via the PATH environment variable"**

この記述は、**s6-overlay 内部のサービススクリプト実行時**における PATH 設定を指しており、エンドユーザーの対話シェルでの実行を保証するものではありません。

#### s6-overlay-symlinks の役割

- **パッケージ名**: `s6-overlay-symlinks-arch.tar.xz`
- **機能**: `/usr/bin` に s6 コマンドのシンボリックリンクを作成
- **必須性**: **任意（オプション）** - 公式に "normally not needed" と明記
- **必要なケース**: 古いスクリプトで `#!/usr/bin/execlineb` のような絶対パスを使用している場合

#### 一般的な使用方法

1. **サービス定義ファイル内**: shebang で `#!/command/execlineb -P` のようにフルパス指定（推奨）
2. **対話的な実行**: 本来想定されていない（主にシステム管理用）

#### 対処方法の選択肢

| 方法 | 実装 | 推奨度 | 理由 |
|------|------|--------|------|
| **A. フルパス指定** | `/command/s6-rc -d list` | ★★★ | s6-overlay の設計思想に沿っており、追加のインストール不要 |
| B. symlinks インストール | Dockerfile に `s6-overlay-symlinks-arch.tar.xz` 追加 | ★★☆ | 対話的な実行が頻繁な場合は便利だが、今回は不要 |
| C. PATH に `/command` 追加 | `.bashrc` に `export PATH="/command:$PATH"` | ★☆☆ | 一般的ではなく、s6-overlay の設計意図と異なる |

**推奨**: **方法A（フルパス指定）** を採用し、検証コマンドを `/command/s6-rc` に統一する。

### 7.2 実装トラッカーへの影響

`25_6_3_docker_entrypoint_fix_implementation_tracker.md` セクションD の検証コマンドをすべて `/command/s6-rc` のフルパス形式に修正する必要があります:

```bash
# 修正前
s6-rc -d list | grep docker-entrypoint
s6-rc -d status docker-entrypoint

# 修正後
/command/s6-rc -d list | grep docker-entrypoint
/command/s6-rc -d status docker-entrypoint
```

この変更は、s6-overlay の設計思想に沿った正しい使用方法であり、`command not found` エラーを回避します。

---

## 8. 次のアクション

1. **即時実施**:
   - [ ] Dockerfile の118行目を `/etc/s6-overlay/s6-rc.d/` に修正
   - [ ] ビルド時検証スクリプトを追加（アプローチ2）
   - [ ] DevContainer を再ビルド

2. **ドキュメント更新**:
   - [ ] `25_6_3_docker_entrypoint_fix_implementation_tracker.md` の検証コマンドをフルパス（`/command/s6-rc`）に更新
   - [ ] `25_4_2_v10_implementation_tracker.md` Phase 1 の完了基準を更新

3. **検証実施**（Dockerfile修正後）:
   - [ ] `/command/s6-rc -d list | grep docker-entrypoint` が成功
   - [ ] `/command/s6-rc -d status docker-entrypoint` が `up` を返す
   - [ ] シンボリックリンクが正しく作成される

4. **git commit と PR更新**:
   - [ ] Dockerfile の修正をコミット
   - [ ] 既存の PR (#12) に追加コミットとしてプッシュ

---

## 9. 参考資料

- [s6-overlay GitHub - Customizing s6-overlay behaviour](https://github.com/just-containers/s6-overlay#customizing-s6-overlay-behaviour)
- [s6-overlay v3 Migration Guide](https://github.com/just-containers/s6-overlay/blob/master/MOVING-TO-V3.md)
- [25_0_process_management_solution.v10.md](25_0_process_management_solution.v10.md) - v10 設計
- [25_6_3_docker_entrypoint_fix_implementation_tracker.md](25_6_3_docker_entrypoint_fix_implementation_tracker.md) - 実装トラッカー

---

## 10. 教訓

### 10.1 今回の問題から学んだこと

1. **ドキュメント参照の重要性**: 公式ドキュメントを十分に確認せず、推測でディレクトリパスを決定すると、このような問題が発生する
2. **ビルド時検証の必要性**: ファイルをコピーするだけでなく、実際に動作するかを検証するステップが必要
3. **実装トラッカーの完了基準**: 「ファイル存在」だけでなく「動作確認」を含める必要がある

### 10.2 Gemini のフィードバックとの関連

この問題は、Gemini が指摘した以下の弱点を改めて浮き彫りにしました:

- **ツッコミ1（実装トラッカー機能不全）**: Phase 1 が「完了」だったが、実際には `/etc/s6-rc.d` という誤ったディレクトリにコピーされていた
- **ツッコミ4（再発防止の甘さ）**: ビルド時検証がないため、同様の問題が発生した

**今回の対応（アプローチ2）は、Gemini のフィードバックに沿った改善策です。**

---

**この問題は、s6-overlay v3 のディレクトリ構造を正しく理解していなかったことに起因します。ビルド時検証を導入することで、同様の問題の再発を防ぎます。**
