# ラッパースクリプト戦略: docker compose exec -u の運用化

**作成日**: 2026-01-09
**目的**: `/root/.bashrc` を変更せず、ラッパースクリプトで `docker compose exec -u ${UNAME}` を自動化する

**関連ドキュメント**:
- `25_6_15_devcontainer_remoteuser_investigation.md` - remoteUser調査
- `25_6_14_user_directive_limitation_analysis.md` - USER directive の限界分析
- `25_6_12_v10_completion_implementation_tracker.md` - 実装トラッカー

---

## 1. ユーザーからの方針転換

### 1.1 以前の推奨案（選択肢2）

**提案内容**:
- `/root/.bashrc` に自動ユーザー切り替えロジックを追加
- docker exec セッション検出 → `exec su - ${UNAME}` で透過的に切り替え

**ユーザーの懸念**:
> /root/.bashrc いじるのはなんか怖いし

**妥当な理由**:
1. `/root/.bashrc` はシステムファイル
2. 予期しない副作用が発生する可能性
3. デバッグが困難になる
4. 他のツールやスクリプトに影響を与える可能性

### 1.2 新しい方針

**ユーザーからの提案**:
> いいですよ、の意味は、docker compose exec を打つ際に必ずオプションつけるっていう運用とか、docker compose exec のラッパースクリプト作る、でいいです

**採用理由**:
1. ✅ システムファイル（`/root/.bashrc`）を変更しない
2. ✅ シンプルで理解しやすい
3. ✅ デバッグが容易
4. ✅ 副作用が明確に限定される

---

## 2. docker compose exec -u の動作確認

### 2.1 コマンド確認

```bash
docker compose exec --help | grep -A 2 "user"
```

**結果**:
```
  -u, --user string       Run the command as this user
  -w, --workdir string    Path to workdir directory for this command
```

**確認事項**: ✅ `docker compose exec -u` は使用可能

### 2.2 実際の動作

**重要**: docker compose コマンドは `.devcontainer` ディレクトリから実行し、両方のcomposeファイルを `-f` フラグで明示的に指定する必要がある

```bash
# .devcontainer ディレクトリに移動
cd /Users/${UNAME}/repos/hagevvashi.info-dev-hub/.devcontainer

# 通常のログイン（rootになる）
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec dev /bin/bash

# -u フラグでユーザー指定
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash
# または
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash
```

**期待される動作**:
- `-u ${UNAME}` を指定すると、`${UNAME}` ユーザーで `/bin/bash` が起動
- `whoami` → `${UNAME}`
- `pwd` → `/home/${UNAME}`（デフォルト）または現在のワークディレクトリ

---

## 3. 解決策の比較

### 3.1 選択肢A: 手動で -u フラグを付ける（非推奨）

**実装**:
```bash
# .devcontainer ディレクトリに移動
cd /Users/${UNAME}/repos/hagevvashi.info-dev-hub/.devcontainer

# 毎回手動で -u フラグを付ける
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash
```

**メリット**:
- シンプル
- 追加のスクリプト不要

**デメリット**:
- ❌ 毎回手動で指定する必要がある（ディレクトリ移動、`-f` フラグ2つ、`-u` フラグ、サービス名、シェルパス）
- ❌ タイポのリスク
- ❌ 長いコマンドを覚える必要がある
- ❌ チーム全員が正確に覚えておく必要がある

### 3.2 選択肢B: シェルエイリアス（簡易版）

**実装**:
```bash
# ~/.bashrc または ~/.zshrc
alias dexec='cd /Users/${UNAME}/repos/hagevvashi.info-dev-hub/.devcontainer && docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash'
```

**メリット**:
- ✅ 簡単に実装できる
- ✅ 個人の環境に閉じている

**デメリット**:
- ❌ チーム全員が個別に設定する必要がある
- ❌ 環境ごとに異なる設定が必要
- ❌ サービス名、ユーザー名、リポジトリの絶対パスがハードコード
- ❌ リポジトリのクローン場所が変わると動作しない

### 3.3 選択肢C: ラッパースクリプト（推奨）★

**実装**:
```bash
# bin/dexec
#!/usr/bin/env bash
# docker compose exec のラッパースクリプト
# 自動的に -u ${UNAME} フラグを付与する

set -euo pipefail

# スクリプトのディレクトリから .devcontainer への相対パスを計算
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="${SCRIPT_DIR}/../.devcontainer"

# 環境変数から実行ユーザーを取得
USER="${UNAME:-${UNAME}}"

# .devcontainer ディレクトリに移動して docker compose exec を実行
cd "${DEVCONTAINER_DIR}"
exec docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u "${USER}" dev /bin/bash "$@"
```

**メリット**:
- ✅ チーム全員が同じスクリプトを使用
- ✅ リポジトリで管理される（バージョン管理）
- ✅ 環境変数で柔軟に対応
- ✅ 拡張性が高い（オプション追加等）
- ✅ 相対パスで動作するため、リポジトリのクローン場所に依存しない
- ✅ 両方のcomposeファイルを自動的に指定

**デメリット**:
- ⚠️ スクリプトのパスを覚える必要がある
- ⚠️ docker compose の他のコマンド（up, down等）には使えない

### 3.4 選択肢D: 高機能ラッパースクリプト（最も推奨）★★★

**実装**:
```bash
# bin/dc
#!/usr/bin/env bash
# docker compose のラッパースクリプト
# exec サブコマンドの場合のみ -u フラグを自動付与

set -euo pipefail

# スクリプトのディレクトリから .devcontainer への相対パスを計算
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="${SCRIPT_DIR}/../.devcontainer"

# 環境変数から実行ユーザーを取得
USER="${UNAME:-${UNAME}}"

# .devcontainer ディレクトリに移動
cd "${DEVCONTAINER_DIR}"

# 基本的な compose コマンド構築（両方のファイルを指定）
COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml"

# サブコマンドが exec の場合、-u フラグを自動挿入
if [ "${1:-}" = "exec" ]; then
    shift  # "exec" を削除

    # 既に -u フラグが指定されている場合はそのまま渡す
    if [[ "$@" =~ -u|--user ]]; then
        exec ${COMPOSE_CMD} exec "$@"
    else
        # -u フラグを自動挿入
        exec ${COMPOSE_CMD} exec -u "${USER}" "$@"
    fi
else
    # exec 以外のサブコマンドはそのまま渡す
    exec ${COMPOSE_CMD} "$@"
fi
```

**メリット**:
- ✅ `docker compose` のすべてのサブコマンドに対応
- ✅ `exec` の場合のみ `-u` フラグを自動挿入
- ✅ 既に `-u` が指定されている場合は上書きしない
- ✅ チーム全員が同じ動作
- ✅ 拡張性が非常に高い
- ✅ 相対パスで動作するため、リポジトリのクローン場所に依存しない
- ✅ 複数のcomposeファイルを自動的に指定

**デメリット**:
- ⚠️ やや複雑

---

## 4. 推奨実装（選択肢D）

### 4.1 ラッパースクリプトの作成

**ファイル**: `bin/dc`

```bash
#!/usr/bin/env bash
# docker compose のラッパースクリプト
# exec サブコマンドの場合のみ -u ${UNAME} フラグを自動付与
#
# 使い方:
#   ./bin/dc up -d          # docker compose -f ... -f ... up -d と同じ
#   ./bin/dc exec dev /bin/bash  # docker compose -f ... -f ... exec -u ${UNAME} dev /bin/bash と同じ
#   ./bin/dc exec -u root dev /bin/bash  # 明示的に -u root を指定した場合はそれを尊重

set -euo pipefail

# スクリプトのディレクトリから .devcontainer への相対パスを計算
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="${SCRIPT_DIR}/../.devcontainer"

# 環境変数から実行ユーザーを取得
# UNAME が設定されていない場合のデフォルト値
DEFAULT_USER="${UNAME}"
USER="${UNAME:-${DEFAULT_USER}}"

# .devcontainer ディレクトリに移動
cd "${DEVCONTAINER_DIR}"

# 基本的な compose コマンド構築（両方のファイルを指定）
COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml"

# サブコマンドが exec の場合、-u フラグを自動挿入
if [ "${1:-}" = "exec" ]; then
    shift  # "exec" を削除

    # 既に -u または --user フラグが指定されている場合はそのまま渡す
    if [[ "$*" =~ -u|--user ]]; then
        exec ${COMPOSE_CMD} exec "$@"
    else
        # -u フラグを自動挿入
        exec ${COMPOSE_CMD} exec -u "${USER}" "$@"
    fi
else
    # exec 以外のサブコマンドはそのまま渡す
    exec ${COMPOSE_CMD} "$@"
fi
```

### 4.2 実行権限の付与

```bash
chmod +x bin/dc
```

### 4.3 使い方

#### 基本的な使い方

```bash
# docker compose のすべてのサブコマンドが使える
./bin/dc up -d
./bin/dc down
./bin/dc ps
./bin/dc logs -f

# exec の場合のみ自動的に -u ${UNAME} が付与される
./bin/dc exec dev /bin/bash
# 内部的に実行されるコマンド:
#   cd .devcontainer
#   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash
```

**重要**: スクリプトは自動的に `.devcontainer` ディレクトリに移動し、両方のcomposeファイルを指定するため、リポジトリルートからどこからでも実行可能

#### ユーザーを明示的に指定する場合

```bash
# 明示的に -u root を指定した場合はそれを尊重
./bin/dc exec -u root dev /bin/bash
# → docker compose -f ... -f ... exec -u root dev /bin/bash

# --user でも同様
./bin/dc exec --user root dev /bin/bash
# → docker compose -f ... -f ... exec --user root dev /bin/bash
```

#### 環境変数でユーザーを変更

```bash
# UNAME 環境変数を設定
export UNAME=anotheruser
./bin/dc exec dev /bin/bash
# → docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u anotheruser dev /bin/bash
```

### 4.4 パス設定（オプション）

**方法1: シェルエイリアス（個人の環境）**

```bash
# ~/.bashrc または ~/.zshrc
alias dc='./bin/dc'
```

**方法2: PATH に追加（個人の環境）**

```bash
# ~/.bashrc または ~/.zshrc
export PATH="$PWD/bin:$PATH"

# または、リポジトリルートを基準にする
export PATH="/Users/${UNAME}/repos/hagevvashi.info-dev-hub/bin:$PATH"
```

**方法3: そのまま使う（推奨）**

```bash
# リポジトリルートから相対パスで実行
./bin/dc exec dev /bin/bash
```

---

## 5. VSCode DevContainer との共存

### 5.1 devcontainer.json の設定

**現在の設定**:
```json
{
  "name": "Dev Container",
  "dockerComposeFile": "docker-compose.yml",
  "service": "dev"
  // remoteUser は設定しない（rootのまま）
}
```

**問題**: VSCodeがコンテナに接続する際、rootユーザーで接続される

### 5.2 解決策: remoteUser を明示的に設定

**`.devcontainer/devcontainer.json`** を修正:

```json
{
  "name": "Dev Container",
  "dockerComposeFile": "docker-compose.yml",
  "service": "dev",
  "remoteUser": "${UNAME}"  // VSCode接続時のユーザーを指定
}
```

**効果**:
- VSCode Dev Container: `remoteUser: "${UNAME}"` により、VSCodeは自動的に `docker exec -u ${UNAME}` を実行 ✅
- docker compose exec: `./bin/dc exec dev /bin/bash` により、`-u ${UNAME}` が自動付与 ✅

**結論**: 両方のケースで `${UNAME}` ユーザーとしてログイン可能

---

## 6. 実装計画

### Phase 1: ラッパースクリプトの作成

**タスク1-1**: `bin/dc` スクリプトを作成
- 選択肢Dの実装を採用
- `docker compose exec` の場合のみ `-u ${UNAME}` を自動挿入

**タスク1-2**: 実行権限を付与
- `chmod +x bin/dc`

**タスク1-3**: 動作確認
```bash
# テスト1: exec サブコマンド（${UNAME} ユーザーで自動ログイン）
./bin/dc exec dev /bin/bash
# 期待: ${UNAME} ユーザーでログイン、whoami → ${UNAME}

# テスト2: exec 以外のサブコマンド（ps）
./bin/dc ps
# 期待: docker compose -f ... -f ... ps と同じ出力

# テスト3: exec 以外のサブコマンド（logs）
./bin/dc logs dev
# 期待: コンテナのログが表示される

# テスト4: 明示的な -u 指定
./bin/dc exec -u root dev /bin/bash
# 期待: rootユーザーでログイン、whoami → root
```

### Phase 2: devcontainer.json の修正

**タスク2-1**: `.devcontainer/devcontainer.json` に `remoteUser` を追加
```json
{
  "remoteUser": "${UNAME}"
}
```

**タスク2-2**: VSCode Dev Container で動作確認
- VSCodeでコンテナに再接続
- ターミナルで `whoami` → `${UNAME}` を確認
- ワークディレクトリが `/home/${UNAME}` またはマウントされたワークスペースであることを確認

### Phase 3: ドキュメント更新

**タスク3-1**: README.md に使い方を追加
```markdown
## コンテナへのログイン

### 推奨方法: ラッパースクリプト

```bash
# ${UNAME} ユーザーでログイン（リポジトリルートから実行）
./bin/dc exec dev /bin/bash
```

### 直接 docker compose を使う場合

```bash
# .devcontainer ディレクトリに移動
cd .devcontainer

# 手動で -u フラグと両方のcomposeファイルを指定
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml exec -u ${UNAME} dev /bin/bash
```
```

**タスク3-2**: 実装トラッカー（25_6_12）の更新
- Phase 2-3-1 の解決策として記録

---

## 7. メリットとデメリット

### 7.1 メリット

1. ✅ **システムファイルを変更しない**
   - `/root/.bashrc` に手を加えない
   - 副作用のリスクが低い

2. ✅ **シンプルで理解しやすい**
   - ラッパースクリプトの動作が明確
   - デバッグが容易

3. ✅ **チーム全員が同じ動作**
   - リポジトリで管理される
   - バージョン管理可能

4. ✅ **拡張性が高い**
   - 他のオプションも追加可能（例: `-w` ワークディレクトリ）
   - 環境変数で柔軟に対応

5. ✅ **VSCode DevContainer とも共存**
   - `devcontainer.json` の `remoteUser` で対応
   - 両方のケースで一貫したユーザー体験

### 7.2 デメリット

1. ⚠️ **ラッパースクリプトのパスを覚える必要がある**
   - 緩和策: シェルエイリアスまたはPATH設定
   - または、README.mdに明記

2. ⚠️ **新しいメンバーへの教育が必要**
   - 緩和策: オンボーディングドキュメントに記載
   - README.mdに使い方を明記

3. ⚠️ **docker compose の公式CLIとは異なる**
   - 緩和策: ラッパースクリプト内にコメントで説明
   - `--help` オプションで使い方を表示（将来的な拡張）

---

## 8. 選択肢2（/root/.bashrc）との比較

### 8.1 選択肢2（非採用）

**実装内容**:
```bash
# /root/.bashrc に追加
if [ "$SHLVL" = "1" ] && [ -n "$UNAME" ]; then
    exec su - "$UNAME"
fi
```

**メリット**:
- ✅ すべてのツールに対応（VSCode、docker compose exec、docker exec）
- ✅ 透過的（ユーザーは意識しない）

**デメリット**:
- ❌ システムファイル（`/root/.bashrc`）を変更
- ❌ 副作用のリスクが高い
- ❌ デバッグが困難
- ❌ **ユーザーが「怖い」と感じる**

### 8.2 選択肢D（採用）

**実装内容**:
```bash
# bin/dc ラッパースクリプト
# docker compose exec の場合のみ -u ${UNAME} を自動挿入
```

**メリット**:
- ✅ システムファイルを変更しない
- ✅ シンプルで理解しやすい
- ✅ デバッグが容易
- ✅ **ユーザーが「安心」できる**

**デメリット**:
- ⚠️ ラッパースクリプトのパスを覚える必要がある
- ⚠️ docker compose 以外のツール（docker exec等）には対応しない

---

## 9. 結論

### 9.1 採用する解決策

**選択肢D: 高機能ラッパースクリプト** を採用

**理由**:
1. ユーザーの懸念（`/root/.bashrc` を変更したくない）を完全に解決
2. シンプルで理解しやすく、副作用が限定的
3. チーム全員が同じ動作を共有できる
4. VSCode DevContainer とも共存可能

### 9.2 実装の優先順位

**優先度 高**:
1. `bin/dc` ラッパースクリプトの作成（Phase 1）
2. `.devcontainer/devcontainer.json` の `remoteUser` 設定（Phase 2）

**優先度 中**:
3. README.md へのドキュメント追加（Phase 3）

### 9.3 次のステップ

**mode-3（実装モード）で直接実装**:
1. `bin/dc` スクリプトを作成
2. `.devcontainer/devcontainer.json` を修正
3. 動作確認
4. ドキュメント更新

---

**最終更新**: 2026-01-09T04:00:00+09:00
**ステータス**: ✅ 戦略立案完了
**次のアクション**: mode-3 で実装開始
