# docker-entrypoint のユーザーコンテキスト問題

**作成日**: 2026-01-10
**問題発見**: 2026-01-10T12:20:00+09:00（検証手順実施中）
**ステータス**: 🔴 **未解決** - 解決策の選定が必要

**関連ドキュメント**:
- `25_6_21_verification_procedure.md` - 検証手順（問題発見）
- `25_6_12_v10_completion_implementation_tracker.md` - 実装トラッカー
- `25_0_process_management_solution.v10.md` - v10設計

---

## 1. 問題の概要

### 1-1. 発見された問題

s6-rc サービス定義ファイルをコピーして再ビルドした結果、以下のエラーが発生：

```
s6-rc: info: service docker-entrypoint: starting
s6-envuidgid: fatal: unknown user: ${UNAME}
s6-rc: warning: unable to start service docker-entrypoint: command exited 1
```

### 1-2. 直接的な原因

`.devcontainer/s6-rc.d/docker-entrypoint/up` の実装：

```bash
#!/usr/bin/env bash
# ${UNAME}ユーザーで実行
# docker-entrypoint.sh内の~は${UNAME}のホームディレクトリを指す
exec s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint.sh
```

- `s6-setuidgid "${UNAME}"` はシェルの環境変数展開を期待
- しかし、s6-overlay の oneshot サービスは環境変数を直接渡さない
- 結果、文字列 `"${UNAME}"` がそのままユーザー名として解釈される
- `s6-envuidgid` が `"${UNAME}"` という名前のユーザーを探して失敗

### 1-3. 影響範囲

#### 起動しているもの
- ✅ s6-overlay（PID 1 = s6-svscan）
- ✅ supervisord サービス（s6-supervise として認識されている）
- ✅ process-compose サービス（s6-supervise として認識されている）
- ✅ code-server プロセス（**ただし、`supervisord -t` のテストプロセスが残っているだけ**）

#### 起動していないもの
- ❌ docker-entrypoint oneshot サービス（exit status 1）

#### 実行されていない処理（docker-entrypoint.sh の全フェーズ）
- ❌ **Phase 1**: パーミッション修正（`~/.config`, `~/.local` など）
- ❌ **Phase 2**: Docker socket 調整（`chmod 666 /var/run/docker.sock`）
- ❌ **Phase 3**: Atuin 初期化（`~/.config/atuin/config.toml` 作成）
- ❌ **Phase 4**: supervisord 設定検証とシンボリックリンク作成
- ❌ **Phase 5**: process-compose 設定検証とシンボリックリンク作成

---

## 2. 根本原因の分析

### 2-1. docker-entrypoint.sh の設計上の問題

docker-entrypoint.sh は以下の2種類の操作を含んでいる：

#### A. root 権限が必要な操作
- **Phase 1**: パーミッション修正（`chown -R ${UNAME}:${GNAME} ~/.config`）
- **Phase 2**: Docker socket 調整（`chmod 666 /var/run/docker.sock`）
- **Phase 4**: supervisord 設定のシンボリックリンク作成（`sudo ln -sf`）
- **Phase 5**: process-compose 設定のシンボリックリンク作成（`sudo ln -sf`）

#### B. 一般ユーザーのコンテキストが必要な操作
- **Phase 3**: Atuin 初期化
  - `mkdir -p ~/.config/atuin`（`~` = ユーザーのホームディレクトリ）
  - `cat > ~/.config/atuin/config.toml`

現在の実装では、**どちらのユーザーで実行しても問題が発生する**：

| 実行ユーザー | Phase 1-2, 4-5（root権限必要） | Phase 3（一般ユーザー必要） |
|:---|:---:|:---:|
| **root** | ✅ 成功 | ❌ `/root/.config/atuin` に作成される |
| **${UNAME}** | ❌ 権限エラー | ✅ 成功 |

### 2-2. s6-overlay での環境変数の扱い

s6-overlay v3 では、環境変数は以下の方法で渡される：

1. **`/run/s6/container_environment/` ディレクトリ**
   - docker-compose.yml の `environment` で設定した変数がここに配置される
   - 各サービスは `s6-envdir` や `with-contenv` でこのディレクトリを読み込む

2. **`s6-setuidgid` の制約**
   - `s6-setuidgid` はユーザー名を**文字列リテラル**として受け取る
   - シェルの環境変数展開（`${UNAME}`）は行われない
   - `s6-envuidgid` を使うと `/run/s6/container_environment/` から読み込めるが、ユーザー名として解釈される前提

---

## 3. 解決のアプローチ

### 3-0. 基本方針

**重要**: どちらのアプローチも以下の基本方針に従います：

> **docker-entrypoint に root と一般ユーザー双方の要求を満たす処理をさせない**

現在の docker-entrypoint.sh は以下の相反する要求を同時に満たそうとしており、これが問題の根本原因です：

- **root 権限が必要な操作**: Phase 1-2, 4-5（chown, chmod, ln -sf）
- **一般ユーザーコンテキストが必要な操作**: Phase 3（Atuin 初期化、`~` の解決）

この基本方針に基づき、**どちらか一方の責任のみを docker-entrypoint に持たせる**ことで問題を解決します。

### 3-1. 2つのアプローチ

問題を解決するには、2つの根本的なアプローチがあります：

### アプローチA: 遅延初期化
- **考え方**: ユーザーコンテキスト操作を初回ログイン時に遅延実行
- **docker-entrypoint の役割**: root 権限操作のみに集中
- **ユーザーコンテキスト操作**: .bashrc で初回ログイン時に実行
- **メリット**: シンプル、s6-overlay の環境変数問題を完全に回避
- **デメリット**: Atuin 初期化がコンテナ起動時に完了しない

### アプローチB: 責任分離（コンテナ起動時に完了）
- **考え方**: root 権限操作とユーザーコンテキスト操作を明確に分離し、両方をコンテナ起動時に実行
- **docker-entrypoint の役割**: 適切なユーザーコンテキストで各処理を実行
- **ユーザーコンテキスト操作**: docker-entrypoint 内で sudo または with-contenv を使用
- **メリット**: すべての初期化がコンテナ起動時に完了
- **デメリット**: 実装が複雑、s6-overlay の環境変数展開手法が必要

---

## 4. 具体的な解決策

### 案1: .bashrc 初回ログイン時初期化（アプローチA）

**適用アプローチ**: 遅延初期化

#### 実装方法

**`.devcontainer/s6-rc.d/docker-entrypoint/up`**:
```bash
#!/usr/bin/env bash
# root ユーザーで実行
# Phase 1-2, 4-5 は root 権限が必要
# Phase 3（Atuin 初期化）は .bashrc_custom で実行
exec /usr/local/bin/docker-entrypoint.sh
```

**`.devcontainer/docker-entrypoint.sh`**:
- Phase 3（Atuin 初期化）を削除

**`.devcontainer/shell/.bashrc_custom`**:
- Atuin 設定ファイル初期化ロジックを追加（冪等性あり）
- 初回ログイン時のみ `~/.config/atuin/config.toml` を作成

#### メリット
- ✅ シンプルで理解しやすい
- ✅ s6-overlay の環境変数問題を完全に回避
- ✅ root 権限が必要な Phase 1-2, 4-5 が正常に動作
- ✅ Atuin 初期化は初回ログイン時に確実にユーザーコンテキストで実行
- ✅ 冪等性があり、複数回ログインしても安全

#### デメリット
- ⚠️ Atuin の初期化が初回ログイン時まで遅延される
- ⚠️ 初回ログイン時に若干の遅延が発生する可能性（設定ファイル作成）

#### 品質特性への影響

| 品質特性 | 影響 | 評価 |
|:---|:---|:---:|
| **信頼性** | 冪等性があり、確実に実行される | ✅ 高 |
| **保守性** | シンプルな実装、理解しやすい | ✅ 高 |
| **パフォーマンス** | 初回ログイン時の遅延（軽微） | ⚠️ 中 |
| **セキュリティ** | root で実行するが、必要な範囲のみ | ✅ 中 |

---

### 案2: with-contenv による環境変数展開（アプローチB）

**適用アプローチ**: 責任分離（コンテナ起動時に完了）

#### 実装方法

**`.devcontainer/s6-rc.d/docker-entrypoint/up`**:
```bash
#!/command/with-contenv bash
# with-contenv で /run/s6/container_environment/ の変数を読み込む
exec s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint.sh
```

または

```bash
#!/usr/bin/env bash
# s6-envdir で環境変数ディレクトリを読み込んでから実行
exec s6-envdir /run/s6/container_environment s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint.sh
```

**前提条件**:
- `/run/s6/container_environment/UNAME` ファイルが存在し、`<個別ユーザー名>` という内容が書かれている
- docker-compose.yml の `environment` 設定が正しく s6-overlay に渡されている

#### メリット
- ✅ s6-overlay の標準的な方法
- ✅ 環境変数を正しく扱える
- ✅ 単一のサービスで実装可能

#### デメリット
- ⚠️ `/run/s6/container_environment/` の存在確認が必要
- ⚠️ Phase 3（Atuin 初期化）と root 権限操作の両立問題は未解決

#### 品質特性への影響

| 品質特性 | 影響 | 評価 |
|:---|:---|:---:|
| **信頼性** | 環境変数が正しく渡される前提 | ⚠️ 中 |
| **保守性** | s6-overlay の標準的な方法 | ✅ 高 |
| **パフォーマンス** | 影響なし | ✅ 高 |
| **セキュリティ** | root 権限操作との両立問題 | ⚠️ 中 |

---

### 案3: sudo 使用（アプローチB）

**適用アプローチ**: 責任分離（コンテナ起動時に完了）

#### 実装方法

**`.devcontainer/s6-rc.d/docker-entrypoint/up`**:
```bash
#!/command/with-contenv bash
# 一般ユーザーで実行
exec s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint.sh
```

**`.devcontainer/docker-entrypoint.sh`**:
```bash
# Phase 1: パーミッション修正（root権限必要）
sudo chown -R ${UNAME}:${GNAME} ~/.config

# Phase 2: Docker socket調整（root権限必要）
sudo chmod 666 /var/run/docker.sock

# Phase 3: Atuin初期化（一般ユーザーで実行）
mkdir -p ~/.config/atuin

# Phase 4-5: supervisord/process-compose 設定（root権限必要）
sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"
```

**前提条件**:
- Dockerfile で `${UNAME}` に NOPASSWD sudo 権限を付与（既に実装済み）
- with-contenv で環境変数 `${UNAME}` を展開

#### メリット
- ✅ 単一のスクリプトで全処理を実装
- ✅ Phase 3 が一般ユーザーで実行される
- ✅ 既存の sudo 設定を活用
- ✅ すべての初期化がコンテナ起動時に完了

#### デメリット
- ⚠️ with-contenv が正しく動作する前提（要検証）
- ⚠️ 実装がやや複雑（sudo の多用）

#### 品質特性への影響

| 品質特性 | 影響 | 評価 |
|:---|:---|:---:|
| **信頼性** | NOPASSWD sudo + with-contenv に依存 | ✅ 高 |
| **保守性** | 単一スクリプト、理解しやすい | ✅ 高 |
| **パフォーマンス** | コンテナ起動時に全処理完了 | ✅ 高 |
| **セキュリティ** | sudo 使用、既に設定済み | ✅ 中 |

---

## 5. アーキテクチャパターン（参考）

### パターン: サービス分割

docker-entrypoint を複数のサービスに分割する設計パターン

#### 概要

**目的**: root 権限操作とユーザーコンテキスト操作を明確に分離

**サービス構成**:
1. **docker-entrypoint-root** (oneshot, root で実行)
   - Phase 1-2, 4-5 を実行
2. **docker-entrypoint-user** (oneshot, ${UNAME} で実行)
   - Phase 3 を実行

#### 適用条件

このパターンは **独立した解決策ではありません**。以下のいずれかの具体的な解決策と組み合わせる必要があります：

- **案2（with-contenv）と組み合わせ**: docker-entrypoint-user で with-contenv を使用
- **案3（sudo）と組み合わせ**: docker-entrypoint-user で sudo を使用（ただし、サービス分割の意味が薄い）

#### 実装例（案2との組み合わせ）

**`.devcontainer/s6-rc.d/docker-entrypoint-root/up`**:
```bash
#!/usr/bin/env bash
exec /usr/local/bin/docker-entrypoint-root.sh
```

**`.devcontainer/s6-rc.d/docker-entrypoint-user/up`**:
```bash
#!/command/with-contenv bash
exec s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint-user.sh
```

**`.devcontainer/s6-rc.d/docker-entrypoint-user/dependencies.d/docker-entrypoint-root`**:
- 依存関係を定義（docker-entrypoint-root の完了後に実行）

#### メリット
- ✅ 責任が明確に分離
- ✅ 各サービスが単一責任

#### デメリット
- ❌ 複雑性が増す（2つのスクリプト + 2つのサービス定義 + 依存関係）
- ❌ 案2または案3に依存（独立した解決策ではない）
- ⚠️ ほとんどのケースで過剰設計（案3で十分）

#### 結論

**このパターンは推奨しません**

理由:
- 単一のスクリプトで sudo を使う方がシンプル（案3）
- 複雑性が増すメリットが小さい
- 保守コストが高い

---

## 6. 推奨案の選定

### 6-0. 選定の前提

すべての解決策は以下の基本方針に従います：

> **docker-entrypoint に root と一般ユーザー双方の要求を満たす処理をさせない**

この方針の下で、以下の2つの戦略のいずれかを採用します：

- **アプローチA（遅延初期化）**: docker-entrypoint は root 権限操作のみ、ユーザーコンテキスト操作は .bashrc で実行
- **アプローチB（責任分離）**: docker-entrypoint で適切なユーザーコンテキストを使い分け（sudo または with-contenv）

### 6-1. 各案の比較表

| 案 | アプローチ | 信頼性 | 保守性 | パフォーマンス | セキュリティ | 実装難易度 | 総合評価 |
|:---|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **案1** | 遅延初期化 | ✅ 高 | ✅ 高 | ⚠️ 中 | ✅ 中 | ✅ 低 | ✅ **推奨** |
| **案2** | 責任分離 | ⚠️ 中 | ✅ 高 | ✅ 高 | ⚠️ 中 | ⚠️ 中 | ⚠️ 要検証 |
| **案3** | 責任分離 | ✅ 高 | ✅ 高 | ✅ 高 | ✅ 中 | ⚠️ 中 | ✅ 次点 |

**サービス分割パターン**: ❌ 非推奨（過剰設計、複雑性増大）

### 6-2. 推奨案: 案1（.bashrc 初回ログイン時初期化）

#### 推奨理由

1. **シンプルで理解しやすい**
   - docker-entrypoint.sh は root 権限操作のみに集中
   - Atuin 初期化は .bashrc_custom で完結
   - s6-overlay の環境変数問題を完全に回避

2. **信頼性が高い**
   - 冪等性がある（初回ログイン時のみ実行）
   - 確実にユーザーコンテキストで実行される
   - root 権限操作（Phase 1-2, 4-5）が正常に動作

3. **保守性が高い**
   - 既存の .bashrc_custom のパターンに合致
   - 条件分岐により root ユーザーでのエラーを回避

4. **実装が容易**
   - docker-entrypoint.sh から Phase 3 を削除するだけ
   - .bashrc_custom に冪等な初期化ロジックを追加

#### 実装手順

1. **docker-entrypoint.sh から Phase 3 を削除**
2. **.bashrc_custom に Atuin 初期化ロジックを追加**
3. **s6-rc.d/docker-entrypoint/up を root で実行するように修正**

### 6-3. 次点案: 案3（sudo 使用 + with-contenv）

環境変数展開問題（案2）が解決できた場合、案3も有力な選択肢：

#### メリット
- コンテナ起動時に全処理が完了
- 単一のスクリプトで実装

#### 採用条件
- `/run/s6/container_environment/UNAME` の存在確認が必要
- `with-contenv` の動作検証が必要

---

## 7. 実装計画

### 7-1. 推奨案（案1）の実装

#### ステップ1: docker-entrypoint.sh の修正

**ファイル**: `.devcontainer/docker-entrypoint.sh`

**削除する範囲**: Phase 3（line 67-100）

```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "⏱️  Phase 3: Initializing Atuin configuration for user ${UNAME}..."
# ... (全体を削除)
echo "✅ Atuin initialization complete for ${UNAME}"
```

**修正後のコメント追加**:
```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化（削除）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 注記: Atuin 初期化は .bashrc_custom の初回ログイン時に実行されます
# 理由: docker-entrypoint は root で実行されるため、ユーザーコンテキストでの
#       初期化は .bashrc で行う方が適切
```

#### ステップ2: s6-rc.d/docker-entrypoint/up の修正

**ファイル**: `.devcontainer/s6-rc.d/docker-entrypoint/up`

**修正前**:
```bash
#!/usr/bin/env bash
# ${UNAME}ユーザーで実行
# docker-entrypoint.sh内の~は${UNAME}のホームディレクトリを指す
exec s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint.sh
```

**修正後**:
```bash
#!/usr/bin/env bash
# root ユーザーで実行
# Phase 1-2, 4-5 は root 権限が必要
# Phase 3（Atuin 初期化）は .bashrc_custom で実行
exec /usr/local/bin/docker-entrypoint.sh
```

#### ステップ3: .bashrc_custom の修正

**ファイル**: `.devcontainer/shell/.bashrc_custom`

**追加する位置**: Atuin 初期化の直前（line 17 の前）

**追加内容**:
```bash
# Atuin 初期化（初回ログイン時のみ実行）
if [ ! -f ~/.config/atuin/config.toml ] && command -v atuin >/dev/null 2>&1; then
    echo "Initializing Atuin configuration..."
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin
    cat > ~/.config/atuin/config.toml <<'EOF'
# Atuin設定ファイル（ユーザー用）
sync_address = ""
sync_frequency = "0"
search_mode = "fuzzy"
filter_mode = "host"
filter_mode_shell_up_key_binding = "directory"
style = "compact"
inline_height = 25
show_preview = true
show_help = true
history_filter = []
show_stats = true
timezone = "+09:00"
EOF
fi

# Atuin の初期化（一般ユーザーのみ）
if [ "$(id -u)" -ne 0 ] && command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init bash)"
fi
```

#### メリット
- ✅ シンプルで理解しやすい
- ✅ s6-overlay の環境変数問題を完全に回避
- ✅ root 権限が必要な Phase 1-2, 4-5 が正常に動作
- ✅ Atuin 初期化は初回ログイン時に確実にユーザーコンテキストで実行
- ✅ 初回ログイン時にのみ設定ファイルを作成（冪等性）

#### デメリット
- ⚠️ Atuin の初期化が初回ログイン時まで遅延される
- ⚠️ 初回ログイン時に若干の遅延が発生する可能性（設定ファイル作成）

#### 品質特性への影響

| 品質特性 | 影響 | 評価 |
|:---|:---|:---:|
| **信頼性** | 冪等性があり、確実に実行される | ✅ 高 |
| **保守性** | シンプルな実装、理解しやすい | ✅ 高 |
| **パフォーマンス** | 初回ログイン時の遅延（軽微） | ⚠️ 中 |
| **セキュリティ** | root で実行するが、必要な範囲のみ | ✅ 中 |

---

## 7. 実装計画

### 7-1. 推奨案（案1）の実装

#### ステップ1: docker-entrypoint.sh の修正

**ファイル**: [.devcontainer/docker-entrypoint.sh](.devcontainer/docker-entrypoint.sh)

**削除する範囲**: Phase 3（line 67-100）

```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "⏱️  Phase 3: Initializing Atuin configuration for user ${UNAME}..."
# ... (全体を削除)
echo "✅ Atuin initialization complete for ${UNAME}"
```

**修正後のコメント追加**:
```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 3: Atuin初期化（削除）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 注記: Atuin 初期化は .bashrc_custom の初回ログイン時に実行されます
# 理由: docker-entrypoint は root で実行されるため、ユーザーコンテキストでの
#       初期化は .bashrc で行う方が適切
```

#### ステップ2: s6-rc.d/docker-entrypoint/up の修正

**ファイル**: [.devcontainer/s6-rc.d/docker-entrypoint/up](.devcontainer/s6-rc.d/docker-entrypoint/up)

**修正前**:
```bash
#!/usr/bin/env bash
# ${UNAME}ユーザーで実行
# docker-entrypoint.sh内の~は${UNAME}のホームディレクトリを指す
exec s6-setuidgid "${UNAME}" /usr/local/bin/docker-entrypoint.sh
```

**修正後**:
```bash
#!/usr/bin/env bash
# root ユーザーで実行
# Phase 1-2, 4-5 は root 権限が必要
# Phase 3（Atuin 初期化）は .bashrc_custom で実行
exec /usr/local/bin/docker-entrypoint.sh
```

#### ステップ3: .bashrc_custom の修正

**ファイル**: [.devcontainer/shell/.bashrc_custom](.devcontainer/shell/.bashrc_custom)

**追加する位置**: Atuin 初期化の直前（line 17 の前）

**追加内容**:
```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ステップ4.5: Atuin 設定ファイルの初期化（初回ログイン時のみ）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 注記: docker-entrypoint.sh では root コンテキストで実行されるため、
#       ユーザー固有の設定ファイル作成は初回ログイン時に実行
if [ "$(id -u)" -ne 0 ] && [ ! -f ~/.config/atuin/config.toml ] && command -v atuin >/dev/null 2>&1; then
    echo "Initializing Atuin configuration for $(whoami)..."
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin
    cat > ~/.config/atuin/config.toml <<'EOF'
# Atuin設定ファイル（ユーザー用）
sync_address = ""
sync_frequency = "0"
search_mode = "fuzzy"
filter_mode = "host"
filter_mode_shell_up_key_binding = "directory"
style = "compact"
inline_height = 25
show_preview = true
show_help = true
history_filter = []
show_stats = true
timezone = "+09:00"
EOF
    echo "✅ Atuin configuration initialized."
fi

# ステップ5: Atuinの初期化（一般ユーザーのみ）
if [ "$(id -u)" -ne 0 ] && command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init bash)"
fi
```

### 7-2. 検証手順

実装後、以下の手順で検証：

1. **コンテナ再ビルド**
   ```bash
   cd .devcontainer
   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml down
   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml build --no-cache
   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml up -d
   ```

2. **ログ確認**
   ```bash
   docker logs devcontainer-dev-1 2>&1 | grep -E "docker-entrypoint|Phase"
   # 期待結果: docker-entrypoint サービスが正常に完了（exit status 0）
   ```

3. **初回ログイン確認**
   ```bash
   ./bin/dc exec dev /bin/bash
   # 期待結果: "Initializing Atuin configuration for <個別ユーザー名>..." メッセージ表示
   # 期待結果: ~/.config/atuin/config.toml が作成される
   ```

4. **2回目ログイン確認**
   ```bash
   ./bin/dc exec dev /bin/bash
   # 期待結果: Atuin 初期化メッセージが表示されない（冪等性確認）
   ```

5. **Atuin 動作確認**
   ```bash
   ./bin/dc exec dev /bin/bash
   atuin status
   # 期待結果: Atuin が正常に動作
   ```

---

## 8. 今後の課題

### 8-1. 短期的な課題

- [ ] 推奨案（案1）の実装
- [ ] 検証手順の実施
- [ ] 検証結果のドキュメント更新

### 8-2. 中長期的な課題

- [ ] s6-overlay の環境変数メカニズムの調査（`/run/s6/container_environment/` の動作確認）
- [ ] 案3（sudo 使用 + with-contenv）の実現可能性検証
- [ ] docker-entrypoint.sh の責任範囲の再検討（初期化処理の適切な配置）

---

## 9. 参考情報

### 9-1. s6-overlay 関連ドキュメント

- [s6-overlay v3 documentation](https://github.com/just-containers/s6-overlay)
- [s6-rc service definitions](https://skarnet.org/software/s6-rc/servicedirs.html)
- [s6-envdir](https://skarnet.org/software/s6/s6-envdir.html)
- [with-contenv](https://github.com/just-containers/s6-overlay#customizing-s6-behaviour)

### 9-2. 関連する過去の問題

- [25_6_20_supervisord_hardcoded_username_issue.md](25_6_20_supervisord_hardcoded_username_issue.md): supervisord ハードコードされたユーザー名問題（環境変数化で解決）
- **25_6_13**: USER ディレクティブのコンテキスト問題（ラッパースクリプトで解決）
- **25_6_10**: docker exec のデフォルトユーザー問題（ラッパースクリプトで解決）

---

**最終更新**: 2026-01-10T13:00:00+09:00
**次のアクション**: 推奨案（案1）の実装とドキュメント更新
