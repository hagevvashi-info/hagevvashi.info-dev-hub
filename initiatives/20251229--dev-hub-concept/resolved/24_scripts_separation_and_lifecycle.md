# DevContainerスクリプトの棲み分けとライフサイクル

**作成日**: 2026-01-02
**目的**: DevContainer環境における各スクリプトの役割・実行タイミング・設計意図を明確化する

## 概要

DevContainer環境では、複数のスクリプトが異なるタイミングで実行されます。このドキュメントでは、それぞれの役割と棲み分けを整理し、設計意図を明確にします。

---

## DevContainerのライフサイクルと実行順序

```
┌─────────────────────────────────────────────┐
│ 1. イメージビルド時（Dockerfile）           │
│    - パッケージインストール                  │
│    - ユーザー作成                            │
│    - スクリプトのCOPY                        │
│    - /etc/skel/ への設定ファイル配置         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ 2. コンテナ起動時（ENTRYPOINT）             │
│    - docker-entrypoint.sh 実行               │
│    - パーミッション調整                      │
│    - 環境固有の初期化                        │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ 3. DevContainer作成後（postCreateCommand）  │
│    - post-create.sh 実行（1回のみ）          │
│    - プロダクトリポジトリclone               │
│    - シンボリックリンク作成                  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ 4. ユーザーログイン時（.bashrc等）          │
│    - env.sh, paths.sh, .bashrc_custom 実行   │
│    - 環境変数設定、PATH設定                  │
│    - Atuin、asdf等の初期化                   │
└─────────────────────────────────────────────┘
```

---

## 各スクリプトの詳細

### 1️⃣ Dockerfile内でコピーされるスクリプト

**実行タイミング**: イメージビルド時（`docker build` 実行時）

#### `.devcontainer/shell/` 配下のファイル群

| ファイル | コピー先 | 役割 |
|---------|---------|------|
| `.bash_profile` | `/etc/skel/.bash_profile` | ログインシェル初期化 |
| `.bashrc_custom` | `/etc/skel/.bashrc_custom` | Bash設定のカスタマイズ |
| `paths.sh` | `/etc/skel/paths.sh` | PATH設定 |
| `env.sh` | `/etc/skel/env.sh` | 環境変数設定 |
| `.profile` | `/etc/skel/.profile` | POSIXシェル用プロファイル |

**Dockerfileでの処理**:
```dockerfile
# 外部化したシェル設定ファイルをコンテナにコピー
COPY .devcontainer/shell/.bash_profile /etc/skel/.bash_profile
COPY .devcontainer/shell/.bashrc_custom /etc/skel/.bashrc_custom
COPY .devcontainer/shell/paths.sh /etc/skel/paths.sh
COPY .devcontainer/shell/env.sh /etc/skel/env.sh
COPY .devcontainer/shell/.profile /etc/skel/.profile

# メインの.bashrcからカスタム設定を読み込むように設定
RUN echo '\n# Load custom dev container configurations' >> /etc/skel/.bashrc && \
    echo '# First, load environment variables' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/env.sh ]; then . ~/env.sh; fi' >> /etc/skel/.bashrc && \
    echo '# Second, set up paths' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/paths.sh ]; then . ~/paths.sh; fi' >> /etc/skel/.bashrc && \
    echo '\n# Then, load custom functions and aliases' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/.bashrc_custom ]; then . ~/.bashrc_custom; fi' >> /etc/skel/.bashrc
```

**`/etc/skel/` の仕組み**:
- `/etc/skel/` は「スケルトンディレクトリ」と呼ばれる
- 新規ユーザー作成時（`useradd`）に、`/etc/skel/` の内容が新規ユーザーのホームディレクトリに自動コピーされる
- これにより、すべてのユーザーが同じデフォルト設定を持つ

**読み込み順序**（シェル起動時）:
```bash
1. ~/.bashrc が実行される（システムデフォルト）
2. ~/env.sh が読み込まれる（環境変数設定）
3. ~/paths.sh が読み込まれる（PATH設定）
4. ~/.bashrc_custom が読み込まれる（Bash設定）
```

#### 各ファイルの内容と役割

##### `env.sh`
```bash
echo "Loading environment variables..."

TEST_ENV_VAR="<一般ユーザー>.info_test"
```

**役割**: プロジェクト固有の環境変数を設定

**設計意図**:
- プロジェクトごとに異なる環境変数を一元管理
- 変更が容易（ファイル編集だけで反映）

---

##### `paths.sh`
```bash
echo "Setting paths..."

# ユーザーのローカルbinディレクトリ（pipxなどで利用）
export PATH="${HOME}/.local/bin:${PATH}"

# asdfのパス設定
export PATH="${HOME}/.asdf/bin:${HOME}/.asdf/shims:${PATH}"

# tfenvのパス設定
export PATH="${HOME}/.tfenv/bin:${PATH}"
```

**役割**: 各種ツールのPATH設定

**設計意図**:
- PATH設定を一箇所に集約
- 読み込み順序を明確化（env.sh → paths.sh → .bashrc_custom）

---

##### `.bashrc_custom`
```bash
# Bash履歴の基本挙動を設定
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend
export HISTCONTROL=ignoredups:erasedups

# 真の複数行履歴を有効化
shopt -s cmdhist
shopt -s lithist

# 複数行履歴の永続化を有効化
export HISTTIMEFORMAT="%F %T "

# 事前実行フックフレームワークの読み込み
[ -f ~/.bash_preexec ] && source ~/.bash_preexec

# Atuinの初期化
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init bash)"
fi

eval "$(tfenv init -)"

. ~/.asdf/asdf.sh

. ~/.asdf/completions/asdf.bash
```

**役割**: Bash環境のカスタマイズ

**設計意図**:
- 履歴管理の強化（Atuin連携）
- 開発ツール（asdf、tfenv）の初期化
- シェル機能の拡張

---

#### docker-entrypoint.sh

| スクリプト | コピー先 | 役割 |
|-----------|---------|------|
| `docker-entrypoint.sh` | `/usr/local/bin/docker-entrypoint.sh` | コンテナ起動時の前処理 |

**Dockerfileでの処理**:
```dockerfile
# ENTRYPOINTスクリプトをコピー
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

...

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth password"]
```

**なぜイメージに焼き込むのか？**:
- これらのスクリプトは「環境の一部」であり、どのコンテナでも同じ設定が必要
- 変更頻度が低い（変更する場合はイメージ再ビルドが妥当）
- セキュリティ上、イメージに含めることで改ざんリスクを低減

---

### 2️⃣ docker-entrypoint.sh

**実行タイミング**: コンテナ起動時（毎回）

**トリガー**: Dockerfileの `ENTRYPOINT` 設定

**現在の処理内容**:

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. マウントされた設定ファイルのパーミッション修正
echo "Fixing permissions for mounted config volumes..."
CONFIG_ITEMS=(
    ~/.config
    ~/.local
    ~/.git
    ~/.ssh
    ~/.aws
    ~/.claude
    ~/.claude.json
    ~/.cursor
    ~/.bash_history
    ~/.gitconfig
)
for item in "${CONFIG_ITEMS[@]}"; do
    if [ -e "$item" ]; then
        sudo chown -R $(id -u):$(id -g) "$item"
    fi
done

# 2. Docker Socketのパーミッション調整
if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock
    if ! groups | grep -q docker; then
        sudo usermod -a -G docker $(whoami)
    fi
fi

# 3. Atuin設定ファイルの初期化
if command -v atuin >/dev/null 2>&1; then
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin

    if [ ! -f ~/.config/atuin/config.toml ]; then
        # デフォルト設定を作成
        cat > ~/.config/atuin/config.toml <<'EOF'
...
EOF
    fi
fi

# 4. 元のコマンドを実行（CMDの内容）
exec "$@"
```

**役割の詳細**:

| 処理 | 目的 | なぜENTRYPOINTで実行？ |
|------|------|---------------------|
| パーミッション修正 | ホストからマウントされたファイルのUID/GID調整 | コンテナ起動のたびに必要（ホスト環境に依存） |
| Docker Socket調整 | コンテナ内からDockerコマンドを実行可能にする | コンテナ起動時に毎回確認が必要 |
| Atuin初期化 | 履歴管理ツールの設定ファイル作成 | 初回のみ実行したいが、存在確認は毎回必要 |
| `exec "$@"` | CMDで指定されたコマンドを実行 | ENTRYPOINTの標準的なパターン |

**ENTRYPOINTとCMDの関係**:
```dockerfile
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth password"]
```

**実際の動作**:
1. コンテナ起動時、`docker-entrypoint.sh` が実行される
2. スクリプト内の処理（パーミッション修正等）が実行される
3. `exec "$@"` により、CMDの内容（code-server起動）が実行される
4. code-serverがフォアグラウンドで動き続ける

**設計意図**:
- **毎回実行が必要な処理**をENTRYPOINTで実行
- コンテナの「前処理」として確実に実行される
- CMDの内容を置き換えず、前処理として機能する

---

### 3️⃣ post-create.sh

**実行タイミング**: DevContainer作成後（**1回のみ**）

**トリガー**: `devcontainer.json` の `postCreateCommand` 設定

**devcontainer.json.template での設定**:
```json
{
  "postCreateCommand": "/home/__UNAME__/__REPO_NAME__/.devcontainer/post-create.sh"
}
```

**現在の処理内容**:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Running post-create setup..."

# 環境変数の確認
UNAME=$(whoami)

# スクリプトのディレクトリから相対的にリポジトリ名を取得
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
REPO_NAME=$(basename "${REPO_ROOT}")

echo "User: ${UNAME}"
echo "Repository: ${REPO_NAME}"
echo "Repository root: ${REPO_ROOT}"

# Devin互換用のシンボリックリンクを作成
# /home/<user>/repos -> /home/<user>/<repo-name>/repos
SYMLINK_PATH="/home/${UNAME}/repos"
TARGET_PATH="/home/${UNAME}/${REPO_NAME}/repos"

if [ ! -L "${SYMLINK_PATH}" ]; then
    echo "Creating symlink: ${SYMLINK_PATH} -> ${TARGET_PATH}"
    ln -sf "${TARGET_PATH}" "${SYMLINK_PATH}"
    echo "✅ Symlink created successfully"
else
    echo "ℹ️  Symlink already exists: ${SYMLINK_PATH}"
    # シンボリックリンクの向き先を確認
    CURRENT_TARGET=$(readlink "${SYMLINK_PATH}")
    if [ "${CURRENT_TARGET}" != "${TARGET_PATH}" ]; then
        echo "⚠️  Warning: Symlink target mismatch. Updating..."
        ln -sf "${TARGET_PATH}" "${SYMLINK_PATH}"
        echo "✅ Symlink updated"
    fi
fi

# repos/ ディレクトリの確認
if [ ! -d "${TARGET_PATH}" ]; then
    echo "⚠️  Warning: ${TARGET_PATH} does not exist"
else
    echo "✅ repos/ directory exists"
    echo "Contents of repos/:"
    ls -la "${TARGET_PATH}" || echo "    (empty or permission denied)"
fi

echo "✅ Post-create setup completed"
```

**役割の詳細**:

| 処理 | 目的 | なぜpostCreateCommandで実行？ |
|------|------|---------------------------|
| シンボリックリンク作成 | Devin互換性の確保 | 1回作成すれば永続化される |
| repos/ディレクトリ確認 | マウント状態の検証 | 初回確認で十分 |
| （将来）プロダクトリポジトリclone | 開発環境の自動セットアップ | 初回のみ必要 |

**postCreateCommandの特性**:
- DevContainer作成時に**1度だけ**実行される
- コンテナ再起動では実行されない
- DevContainerを削除して再作成すると再実行される

**なぜバインドマウント経由でアクセス？**:
- **開発中に変更する可能性がある**
  - シンボリックリンクのロジック修正
  - プロダクトリポジトリのclone処理追加
- **イメージに焼き込むと柔軟性が低下**
  - 変更のたびにイメージ再ビルドが必要
  - デバッグが困難
- **DevContainerの設定の一部として管理したい**
  - `${REPO_NAME}` と同じリポジトリで管理
  - Git履歴で変更を追跡可能

**設計意図**:
- DevContainer固有のセットアップを実行
- 1回だけ実行すれば良い処理に最適
- 開発時の柔軟性を保つ

---

### 4️⃣ .devcontainer/shell/ 配下のスクリプト

**実行タイミング**: ユーザーがシェルを起動するたび

**トリガー**: `.bashrc` からの読み込み

**読み込みフロー**:

```
ユーザーがシェルを起動
    ↓
~/.bashrc が実行される（システムデフォルト）
    ↓
~/env.sh が読み込まれる
    ↓
~/paths.sh が読み込まれる
    ↓
~/.bashrc_custom が読み込まれる
    ↓
シェルが使用可能に
```

**各ファイルの実行頻度と影響範囲**:

| ファイル | 実行頻度 | 影響範囲 | 用途 |
|---------|---------|---------|------|
| `env.sh` | シェル起動時（毎回） | 環境変数 | プロジェクト固有の環境変数設定 |
| `paths.sh` | シェル起動時（毎回） | PATH | 各種ツールのPATH追加 |
| `.bashrc_custom` | シェル起動時（毎回） | Bash環境全体 | 履歴管理、ツール初期化、シェル機能拡張 |

**なぜ `/etc/skel/` にコピーするのか？**:
- **ユーザー作成時に自動適用**
  - Dockerfileで `useradd` 実行時、`/etc/skel/` の内容が自動コピーされる
  - すべてのユーザーが同じデフォルト設定を持つ
- **環境の「デフォルト設定」として機能**
  - イメージに焼き込むことで、環境の一部として管理
  - 変更頻度が低い設定に最適

**設計意図**:
- ユーザー環境の標準化
- 環境変数・PATH・Bash設定を一元管理
- シェル起動時の初期化を自動化

---

## 比較表: スクリプトの棲み分け

| スクリプト | 実行タイミング | 実行頻度 | 配置方法 | 変更頻度 | 役割 |
|-----------|--------------|---------|---------|---------|------|
| **docker-entrypoint.sh** | コンテナ起動時 | 毎回 | イメージに焼き込む | 低 | パーミッション修正、Docker Socket調整、Atuin初期化 |
| **post-create.sh** | DevContainer作成後 | 1回 | バインドマウント | 中〜高 | シンボリックリンク作成、プロダクトリポジトリclone |
| **.devcontainer/shell/*** | シェル起動時 | 毎回 | イメージに焼き込む (`/etc/skel/`) | 低〜中 | 環境変数、PATH、Bash設定 |

---

## 設計の意図と原則

### 1. 変更頻度による分離

**原則**: 変更頻度が低いものはイメージに焼き込み、高いものはバインドマウント

| 変更頻度 | 配置方法 | 例 |
|---------|---------|---|
| **低** | イメージに焼き込む | `docker-entrypoint.sh`, `.devcontainer/shell/*` |
| **中〜高** | バインドマウント | `post-create.sh` |

**理由**:
- イメージに焼き込む → 安定性が高い、再ビルドのコストを許容
- バインドマウント → 柔軟性が高い、開発時の変更が即座に反映

---

### 2. 実行タイミングによる分離

**原則**: 実行タイミングに応じて最適なメカニズムを選択

| 実行タイミング | メカニズム | 例 |
|-------------|-----------|---|
| **コンテナ起動時（毎回）** | ENTRYPOINT | `docker-entrypoint.sh` |
| **DevContainer作成後（1回）** | postCreateCommand | `post-create.sh` |
| **シェル起動時（毎回）** | `.bashrc` | `.devcontainer/shell/*` |

**理由**:
- ENTRYPOINT → コンテナレベルの前処理、確実に実行される
- postCreateCommand → DevContainer固有のセットアップ、1回だけで十分
- `.bashrc` → ユーザー環境の初期化、シェルごとに必要

---

### 3. 責務による分離

**原則**: 各スクリプトの責務を明確にし、単一責任の原則に従う

| スクリプト | 責務 |
|-----------|------|
| **docker-entrypoint.sh** | コンテナレベルの初期化（パーミッション、Docker Socket、基本ツール設定） |
| **post-create.sh** | DevContainer固有のセットアップ（シンボリックリンク、プロダクトリポジトリclone） |
| **.devcontainer/shell/*** | ユーザー環境の設定（環境変数、PATH、Bash設定） |

**理由**:
- 責務を分離することで、各スクリプトの役割が明確になる
- 変更時の影響範囲が限定される
- テスト・デバッグが容易になる

---

## よくある疑問と回答

### Q1: なぜ `post-create.sh` をイメージに焼き込まないのか？

**A**: 開発時の柔軟性を保つため

- `post-create.sh` は開発中に頻繁に変更される可能性がある
  - シンボリックリンクのロジック修正
  - プロダクトリポジトリのclone処理追加
  - デバッグ用の出力追加
- イメージに焼き込むと、変更のたびにイメージ再ビルドが必要
- バインドマウント経由なら、ファイル編集だけで即座に反映

**トレードオフ**:
- メリット: 開発効率が高い、デバッグが容易
- デメリット: マウント設定が必要、実行時にファイルが存在することを前提とする

---

### Q2: なぜ `.devcontainer/shell/*` を `/etc/skel/` にコピーするのか？

**A**: 新規ユーザー作成時に自動適用するため

- `/etc/skel/` は「スケルトンディレクトリ」と呼ばれる特殊なディレクトリ
- `useradd` コマンド実行時、`/etc/skel/` の内容が新規ユーザーのホームディレクトリに自動コピーされる
- Dockerfileで以下のようにユーザーが作成される際、設定ファイルが自動適用される

```dockerfile
RUN useradd -o -l -u ${UID} -g ${GNAME} -G docker -m ${UNAME}
# ↑ -m オプションでホームディレクトリ作成時、/etc/skel/ の内容がコピーされる
```

**参考**: [Linux の /etc/skel/ ディレクトリ](https://linuxjm.osdn.jp/html/shadow/man8/useradd.8.html)

---

### Q3: `docker-entrypoint.sh` と `post-create.sh` の使い分けは？

**A**: 実行頻度と責務で使い分ける

| 観点 | docker-entrypoint.sh | post-create.sh |
|------|---------------------|---------------|
| **実行頻度** | コンテナ起動時（毎回） | DevContainer作成後（1回） |
| **責務** | コンテナレベルの初期化 | DevContainer固有のセットアップ |
| **例** | パーミッション修正、Docker Socket調整 | シンボリックリンク作成、リポジトリclone |

**判断基準**:
- 毎回実行が必要 → `docker-entrypoint.sh`
- 1回だけで十分 → `post-create.sh`

---

### Q4: なぜ `env.sh` と `paths.sh` を分けているのか？

**A**: 責務を分離し、読み込み順序を明確にするため

**読み込み順序**:
```bash
1. env.sh        # 環境変数設定
2. paths.sh      # PATH設定（環境変数を参照する可能性）
3. .bashrc_custom # Bash設定（環境変数・PATHを前提とする）
```

**分離のメリット**:
- 各ファイルの役割が明確
- 依存関係が明示的
- 変更時の影響範囲が限定される

---

## 現在のエラー（post-create.sh not found）との関係

### 問題の本質

**`post-create.sh` はバインドマウント経由でアクセスする前提だが、マウント設定が不足している**

**設計意図**:
- `post-create.sh` は `${REPO_NAME}/.devcontainer/post-create.sh` としてホスト側に存在
- コンテナ内では `/home/<user>/${REPO_NAME}/.devcontainer/post-create.sh` としてアクセス
- これには `${REPO_NAME}` が `/home/<user>/${REPO_NAME}` にバインドマウントされている必要がある

**現状の問題**:
- `${localWorkspaceFolder}` の明示的なマウント設定がない
- VS Codeのデフォルトマウント挙動に依存している可能性
- マウント先パスが不明確

### 解決策（23_post_create_sh_not_found_analysis.md参照）

**推奨**: `docker-compose.yml` でバインドマウントを明示

```yaml
volumes:
  # <MonolithicDevContainerレポジトリ名> リポジトリ全体をバインドマウント
  - type: bind
    source: ..
    target: /home/${UNAME:-vscode}/${REPO_NAME}
    consistency: cached
  # repos/ を Docker Volume で直接マウント（I/Oパフォーマンス）
  - type: volume
    source: repos
    target: /home/${UNAME:-vscode}/${REPO_NAME}/repos
```

**これにより**:
- `post-create.sh` がバインドマウント経由でアクセス可能になる
- 設計v10に準拠したマウント構造が実現される

---

## まとめ

### スクリプトの役割一覧

| スクリプト | いつ実行？ | 何をする？ | どこにある？ |
|-----------|----------|----------|------------|
| **docker-entrypoint.sh** | コンテナ起動時 | パーミッション修正、Docker Socket調整 | `/usr/local/bin/`（イメージ内） |
| **post-create.sh** | DevContainer作成後 | シンボリックリンク作成、リポジトリclone | バインドマウント経由 |
| **env.sh** | シェル起動時 | 環境変数設定 | `~/`（/etc/skel/ からコピー） |
| **paths.sh** | シェル起動時 | PATH設定 | `~/`（/etc/skel/ からコピー） |
| **.bashrc_custom** | シェル起動時 | Bash設定、ツール初期化 | `~/`（/etc/skel/ からコピー） |

### 設計の3原則

1. **変更頻度による分離**: 低頻度 → イメージ、高頻度 → バインドマウント
2. **実行タイミングによる分離**: ENTRYPOINT、postCreateCommand、.bashrc を使い分け
3. **責務による分離**: 各スクリプトの役割を明確化

---

## 参考資料

- [Dockerfileリファレンス](https://docs.docker.com/engine/reference/builder/)
- [DevContainer specification](https://containers.dev/implementors/json_reference/)
- [Linux の /etc/skel/ ディレクトリ](https://linuxjm.osdn.jp/html/shadow/man8/useradd.8.html)
- [Bash起動ファイルの読み込み順序](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)

---

## 変更履歴

### 2026-01-02
- 初版作成
- DevContainerスクリプトのライフサイクルと棲み分けを整理
- 各スクリプトの役割と設計意図を明確化
- 現在のエラー（post-create.sh not found）との関係を説明
