# 実装と設計の乖離分析

**作成日**: 2026-01-02
**分析対象**: `.devcontainer/` 配下の実装 vs 設計ドキュメント v10

## 概要

現在の `.devcontainer/` 配下の実装と、設計ドキュメント v10（[14_詳細設計_ディレクトリ構成.v10.md](14_詳細設計_ディレクトリ構成.v10.md)）を比較し、重大な乖離点を特定しました。

**結論**: 設計v10の核心である**「CLI版AIエージェント対応のための物理統合」が実装されていません。**現在の実装は v8以前の構造に近い状態です。

---

## 🔴 重大な乖離

### 1. `repos/` のマウント構造が設計v10と異なる

#### 設計v10の想定

```json
{
  "mounts": [
    "source=${localWorkspaceFolder},target=/home/<user>/${project}-dev-hub,type=bind,consistency=cached",
    "source=repos,target=/home/<user>/${project}-dev-hub/repos,type=volume"
  ],
  "workspaceFolder": "/home/<user>/${project}-dev-hub"
}
```

**意図**:
- `repos/` を `${project}-dev-hub/repos` に直接Docker Volumeマウント
- シンボリックリンク `/home/<user>/repos` → `/home/<user>/${project}-dev-hub/repos` で Devin互換性を維持

**ディレクトリ構造**:
```
/home/<user>/
├── ${project}-dev-hub/            # バインドマウント
│   ├── foundations/
│   ├── initiatives/
│   ├── repos/                     # Docker Volume（直接マウント）
│   └── workspace.code-workspace
└── repos -> ${project}-dev-hub/repos/  # シンボリックリンク（Devin互換用）
```

#### 現在の実装

**docker-compose.yml**:
```yaml
volumes:
  - type: volume
    source: repos
    target: /home/${UNAME:-vscode}/repos  # ← 従来の構造
```

**実際のディレクトリ構造**:
```
/home/<user>/
├── repos/                         # Docker Volume（直接マウント）
│   ├── (プロダクトリポジトリ)
└── (${project}-dev-hubのマウント先が不明確)
```

#### 影響

- ❌ CLI版AIエージェントが `/home/<user>/${project}-dev-hub` から起動しても `repos/` が見えない
- ❌ 設計v10の最大の目的「**CLI版コンテキストエンジニアリング**」が実現できていない
- ❌ `foundations/`, `initiatives/`, `repos/*` を統一的に参照できない

#### 設計意図の再確認

設計v10では、以下の3つの要求を同時に満たすことを目的としていました:

1. **Devin互換性**: `~/repos/<product-repo>` でアクセス可能
2. **VS Code拡張版コンテキストエンジニアリング**: `workspace.code-workspace` で論理的に統合
3. **CLI版コンテキストエンジニアリング**: 物理的に `${project}-dev-hub/` 配下に統合

現在の実装では **3. が未達成** です。

---

### 2. `workspaceFolder` の設定が設計と異なる

#### 設計v10の想定

```json
"workspaceFolder": "/home/<user>/${project}-dev-hub"
```

**意図**: VS Codeで開いた際のルートディレクトリを `${project}-dev-hub` にする

#### 現在の実装

**devcontainer.json.template**:
```json
"workspaceFolder": "/home/__UNAME__"
```

**生成後の devcontainer.json**:
```json
"workspaceFolder": "/home/<一般ユーザー>"
```

#### 影響

- ❌ VS Codeで開いた際のルートディレクトリが `/home/<一般ユーザー>` になる
- ❌ `${project}-dev-hub` がルートではなく、設計意図と乖離
- ⚠️ ファイル参照時のパスが設計と異なる

---

### 3. `${project}-dev-hub` 自体のマウント設定が存在しない

#### 設計v10の想定

```json
"mounts": [
  "source=${localWorkspaceFolder},target=/home/<user>/${project}-dev-hub,type=bind,consistency=cached",
  "source=repos,target=/home/<user>/${project}-dev-hub/repos,type=volume",
  ...
]
```

**意図**: `${localWorkspaceFolder}` を `/home/<user>/${project}-dev-hub` に明示的にバインドマウント

#### 現在の実装

**devcontainer.json**:
```json
"mounts": [
  "source=/Users/<一般ユーザー>/.bash_history,target=/home/<一般ユーザー>/.bash_history,type=bind,consistency=cached",
  "source=/Users/<一般ユーザー>/.git,target=/home/<一般ユーザー>/.git,type=bind,consistency=cached",
  ...
  // ${localWorkspaceFolder} 自体のマウント設定がない
]
```

**docker-compose.yml**:
```yaml
build:
  context: ..  # 暗黙的にマウントされる？
```

#### 影響

- ⚠️ マウント先パスが不明確
- ⚠️ VS Codeのデフォルト挙動に依存している可能性
- ⚠️ 明示的なマウント設定がないため、動作が予測しづらい

#### 補足

VS Code DevContainerのデフォルト挙動では、`${localWorkspaceFolder}` が `/workspaces/<リポジトリ名>` にマウントされることが多いです。しかし、現在の設定では `workspaceFolder: /home/<一般ユーザー>` となっているため、実際のマウント先を確認する必要があります。

---

### 4. Devin互換用シンボリックリンクの作成スクリプトが存在しない

#### 設計v10の想定

**post-create.sh で実行**:
```bash
ln -sf /home/<user>/${project}-dev-hub/repos /home/<user>/repos
```

**意図**:
- `repos/` の実体は `/home/<user>/${project}-dev-hub/repos`（Docker Volume）
- `/home/<user>/repos` からもアクセス可能にする（逆向きシンボリックリンク）
- Devin互換性を維持

#### 現在の実装

**Dockerfile (149行目)**:
```dockerfile
mkdir -p /home/${UNAME}/repos && \
chown -R ${UID}:${GID} /home/${UNAME}/repos && \
```

**docker-entrypoint.sh**:
- シンボリックリンク作成処理なし
- パーミッション修正のみ

#### 影響

- ❌ Devin互換性が確保されていない
- ❌ 設計v10では逆向きシンボリックリンクで実現する予定だったが未実装
- ⚠️ Devinが期待する `~/repos/<product-repo>` のパス構造は維持されているが、v10の物理統合構造ではない

#### 補足

現在の実装では、従来の構造（`repos/` を `/home/<user>/repos` に直接マウント）のため、Devin互換性自体は保たれています。しかし、設計v10の「物理統合」構造にはなっていません。

---

### 5. `workspace.code-workspace` が空ファイル

#### 設計v10の想定

```json
{
  "folders": [
    {
      "path": "/home/<user>/${project}-dev-hub",
      "name": "${project}-dev-hub"
    },
    {
      "path": "/home/<user>/repos/product-a",
      "name": "product-a"
    },
    {
      "path": "/home/<user>/repos/product-b",
      "name": "product-b"
    }
  ],
  "settings": {
    // ワークスペース共通の設定
  }
}
```

**意図**: マルチルートワークスペースで `foundations/`, `initiatives/`, `repos/*` を統一的に参照可能にする

#### 現在の実装

```bash
$ ls -la workspace.code-workspace
-rw-r--r--@ 1 <一般ユーザー> staff 0 Dec 31 12:46 workspace.code-workspace
```

**0バイトの空ファイル**

#### 影響

- ❌ VS Code拡張版のコンテキストエンジニアリングが機能しない
- ❌ マルチルートワークスペースが構成されていない
- ❌ AIエージェントが `foundations/`, `initiatives/`, `repos/*` を同時に参照できない

#### 設計意図の再確認

`workspace.code-workspace` は、VS Code拡張版AIエージェント（Cursor、Claude Code拡張等）に対するコンテキストエンジニアリングの要です。これがないと、物理的に分離されたディレクトリを統一的に扱えません。

---

## ⚠️ 中程度の乖離

### 6. ホスト側セットアップスクリプトの命名が異なる

#### 設計v10の想定

**ファイル名**: `host-setup.sh`

**役割**:
- テンプレートから `devcontainer.json` を生成
- `.env` ファイルを生成

#### 現在の実装

**ファイル名**: `setup.sh`, `generate-env.sh`

**役割**:
- `setup.sh`: Docker Volume作成 + `devcontainer.json` 生成 + `docker-compose.dev-vm.yml` 生成
- `generate-env.sh`: `.env` ファイル生成（`initializeCommand` で実行）

#### 影響

- △ 機能的には問題ないが、命名規則が設計と乖離
- △ 設計ドキュメントとの対応関係がわかりづらい

#### 補足

機能的には `setup.sh` が `host-setup.sh` に相当します。ただし、`generate-env.sh` も `initializeCommand` で実行されるため、役割が分散しています。

---

## ✅ 一致している部分

以下の点は設計と一致しています:

### 1. UID/GID のテンプレート置換

**generate-env.sh**:
```bash
cat > .devcontainer/.env << EOF
UID="$(id -u)"
GID="$(id -g)"
UNAME="$(whoami)"
GNAME="$(id -n -g | sed 's/ /\\u00A0/g')"
EOF
```

**setup.sh**:
```bash
sed -e "s/__UNAME__/$(whoami)/g" \
    -e "s|__HOME__|${HOME}|g" \
    -e "s|__PLATFORM__|${PLATFORM}|g" \
    ./.devcontainer/devcontainer.json.template > ./.devcontainer/devcontainer.json
```

✅ 設計通り、ホスト側でUID/GIDを取得してテンプレート置換している

### 2. 認証情報のバインドマウント

**devcontainer.json**:
```json
"mounts": [
  "source=/Users/<一般ユーザー>/.ssh,target=/home/<一般ユーザー>/.ssh,type=bind,consistency=cached",
  "source=/Users/<一般ユーザー>/.gitconfig,target=/home/<一般ユーザー>/.gitconfig,type=bind,consistency=cached",
  "source=/Users/<一般ユーザー>/.aws,target=/home/<一般ユーザー>/.aws,type=bind,consistency=cached",
  ...
]
```

✅ 設計通り、`.ssh`, `.gitconfig`, `.aws` 等がバインドマウントされている

### 3. Docker Volume `repos` の作成

**setup.sh**:
```bash
VOLUME_NAME="repos"
if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "Volume '$VOLUME_NAME' は既に存在します"
else
  echo "Volume '$VOLUME_NAME' を作成します"
  docker volume create "$VOLUME_NAME"
fi
```

**docker-compose.yml**:
```yaml
volumes:
  repos:
    external: true
```

✅ 設計通り、Docker Volume `repos` が作成・マウントされている（ただし、マウント先パスが異なる）

### 4. ディレクトリ構造

```bash
$ ls -la /Users/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/
drwxr-xr-x@  3 <一般ユーザー>  staff    96 Dec 31 12:46 foundations
drwxr-xr-x@  5 <一般ユーザー>  staff   160 Jan  1 23:19 initiatives
drwxr-xr-x@  3 <一般ユーザー>  staff    96 Dec 31 12:46 members
```

✅ `foundations/`, `initiatives/`, `members/` は存在する

### 5. `.gitignore` の設定

```gitignore
# Dev container files
devcontainer.json
.env
```

✅ 設計通り、生成ファイルが `.gitignore` に含まれている

---

## 乖離の原因分析

### 設計進化の経緯

設計ドキュメントは以下のように進化しています:

- **v5-v8**: `repos/` を `/home/<user>/repos` に直接マウント（従来構造）
- **v9**: `workspace.code-workspace` の説明追加、`initiatives/` 命名規則明確化
- **v10**: **CLI版AIエージェント対応**のため、`repos/` を `${project}-dev-hub}/repos` に物理統合

### 実装が追従していない理由（推測）

1. **v10が最近追加された設計である**
   - 変更履歴によると、v10は 2026-01-01 に追加
   - 実装が v8以前の構造で固まっていた可能性

2. **v10の変更範囲が大きい**
   - マウント構造の根本的な変更
   - シンボリックリンクの追加
   - `workspaceFolder` の変更
   - 既存の動作環境への影響が大きい

3. **設計ドキュメントが複数バージョン存在**
   - v5, v6, v7, v8, v9, v10 が並存
   - どれが「確定版」かが不明確だった可能性

---

## 推奨される対応方針

### オプション1: 設計v10に合わせて実装を修正する（推奨）

**メリット**:
- ✅ CLI版AIエージェント対応が実現される
- ✅ 設計の最新版に準拠
- ✅ 将来性が高い（Claude Code CLI、Gemini CLI等の重要性が増す）

**デメリット**:
- ⚠️ 既存環境への影響が大きい
- ⚠️ マウント構造の変更が必要
- ⚠️ テストが必要

**修正項目**:
1. `devcontainer.json.template` のマウント設定変更
2. `docker-compose.yml` の `repos` マウント先変更
3. `workspaceFolder` の変更
4. `post-create.sh` または `docker-entrypoint.sh` にシンボリックリンク作成処理追加
5. `workspace.code-workspace` の記述

### オプション2: 現在の実装を基準に設計を見直す

**メリット**:
- ✅ 既存環境への影響なし
- ✅ 動作実績のある構造を維持

**デメリット**:
- ❌ CLI版AIエージェント対応が実現されない
- ❌ v10の設計意図が無駄になる
- ❌ 将来的な拡張性が低い

**見直し項目**:
1. v10を「将来構想」として位置づけ
2. v8を「現行設計」として確定
3. v10への移行計画を別途策定

### オプション3: 段階的移行

**メリット**:
- ✅ リスクを分散できる
- ✅ 動作確認しながら進められる

**デメリット**:
- ⚠️ 移行期間が長くなる
- ⚠️ 中間状態の管理が必要

**移行ステップ**:
1. **Phase 1**: `workspace.code-workspace` の記述（影響小）
2. **Phase 2**: `workspaceFolder` の変更（影響中）
3. **Phase 3**: マウント構造の変更（影響大）

---

## 次のアクション

以下のいずれかを決定する必要があります:

1. **設計v10への移行を開始する**
   - → 修正計画の立案（mode-1: 立案モード）
   - → 実装作業（mode-2: 作業モード）

2. **現在の実装を基準に設計を見直す**
   - → v8を「確定版」として明確化
   - → v10を「将来構想」として位置づけ

3. **段階的移行計画を策定する**
   - → 移行ロードマップの作成
   - → Phase 1から着手

---

## 参考資料

- [14_詳細設計_ディレクトリ構成.v10.md](14_詳細設計_ディレクトリ構成.v10.md): 設計v10の詳細
- [21_foundations_initiatives_mount_issue.md](21_foundations_initiatives_mount_issue.md): マウント問題の整理と解決策の比較
- [98_workspace_code-workspaceの仕組み.md](98_workspace_code-workspaceの仕組み.md): マルチルートワークスペースの詳細
- [00_Monolithic DevContainerの本質.v2.md](00_Monolithic%20DevContainerの本質.v2.md): Devin互換性の定義

---

## 設計v10への移行計画（決定版）

**決定日**: 2026-01-02
**採用アプローチ**: 段階的移行アプローチ（オプション3 → 解決策B）

### 課題（目標とのギャップ）

**現在の実装が設計v10と乖離しており、CLI版AIエージェント対応が実現できていない**

具体的には：
- `repos/` のマウント構造が従来型（`/home/<user>/repos`）のまま
- `workspace.code-workspace` が空ファイルで機能していない
- CLI版AIエージェント（Claude Code CLI、Gemini CLI等）が `foundations/`, `initiatives/`, `repos/*` を統一的に参照できない
- 設計v10の最大の目的「物理的な統合によるコンテキストエンジニアリング」が未達成

### 原因

**設計の進化に実装が追従していない**

- v10は2026-01-01に追加された最新設計だが、実装はv8以前の構造で固まっていた
- マウント構造の根本的な変更が必要で、影響範囲が大きい
- 設計ドキュメントが複数バージョン並存しており、どれが確定版か不明確だった

### 目的（あるべき状態）

**設計v10に準拠した実装により、3つの要求を同時に満たす状態を実現する**

1. **Devin互換性**: `~/repos/<product-repo>` でアクセス可能（シンボリックリンク経由）
2. **VS Code拡張版コンテキストエンジニアリング**: `workspace.code-workspace` で論理的に統合
3. **CLI版コンテキストエンジニアリング**: 物理的に `${project}-dev-hub/` 配下で統合

これにより：
- Claude Code CLI や Gemini CLI が `/home/<user>/${project}-dev-hub` から起動し、すべてのコンテキストを参照可能
- Cursor や Claude Code拡張等のVS Code拡張版も引き続き動作
- Devin等の既存AIエージェントとの互換性も維持

### 戦略・アプローチ（解決の方針）

**段階的移行により、リスクを最小化しながら設計v10を実現する**

- **Phase 1（影響小）**: `workspace.code-workspace` の記述
  - 既存のマウント構造のままでも動作する
  - VS Code拡張版のコンテキストエンジニアリングが先行して実現

- **Phase 2（影響中）**: `workspaceFolder` の変更とマウント設定の明示化
  - VS Codeで開く際のルートディレクトリを変更
  - 動作確認が容易

- **Phase 3（影響大）**: マウント構造の変更とシンボリックリンク作成
  - `repos/` を `${project}-dev-hub}/repos` に物理統合
  - Devin互換用シンボリックリンクの作成
  - CLI版コンテキストエンジニアリングを実現

各フェーズで動作確認を行い、問題があれば切り戻し可能な構造とする。

---

## 解決策の比較

### 解決策A: 一括移行アプローチ

**概要**: すべての変更を一度に実施し、設計v10を完全に実現する

**実装内容**:
1. `devcontainer.json.template` の全面書き換え
2. `docker-compose.yml` のマウント設定変更
3. `post-create.sh` の新規作成（またはdocker-entrypoint.sh拡張）
4. `workspace.code-workspace` の記述
5. 一括での動作確認

**メリット**:
- ⭐⭐⭐ 最短で設計v10を実現できる
- ⭐⭐⭐ 中間状態の管理が不要
- ⭐⭐ 一度の移行で完了

**デメリット**:
- ❌ リスクが高い（一度に多くの変更）
- ❌ 問題発生時の切り分けが困難
- ❌ 既存環境への影響が一度に発生

**想定期間**: 1日（実装） + 1日（テスト・修正）

---

### 解決策B: 段階的移行アプローチ（推奨・採用）

**概要**: 3つのPhaseに分けて段階的に移行し、各段階で動作確認

#### Phase 1: workspace.code-workspace の記述

**目標**: VS Code拡張版のコンテキストエンジニアリングを実現

**実装内容**:
1. `workspace.code-workspace` の記述
   - `foundations/`, `initiatives/`, `members/` を追加
   - `repos/` 配下のプロダクトリポジトリを追加（現時点では未存在の可能性）
2. 動作確認
   - VS Codeで `workspace.code-workspace` を開く
   - マルチルートワークスペースが正しく表示されるか確認
   - AIエージェント（Claude Code拡張）が全体を参照できるか確認

**影響範囲**: VS Codeの表示のみ

**成果物**:
- 記述された `workspace.code-workspace`
- 動作確認結果のドキュメント

**所要時間**: 0.5日（実装） + 0.5日（テスト） = **1日**

#### Phase 2: workspaceFolder変更とマウント明示化

**目標**: VS Codeのルートディレクトリを `${project}-dev-hub` に変更

**実装内容**:
1. `devcontainer.json.template` の修正
   - `workspaceFolder` を `/home/__UNAME__/<MonolithicDevContainerレポジトリ名>` に変更
   - `${localWorkspaceFolder}` のマウント設定を明示化
2. `repos/` は従来通り `/home/__UNAME__/repos` にマウント（暫定）
3. 動作確認
   - VS Codeで開いた際のルートディレクトリが正しいか確認
   - 既存機能が正常に動作するか確認

**影響範囲**: VS Codeのルートディレクトリ、パス参照

**成果物**:
- 修正された `devcontainer.json.template`
- 動作確認結果のドキュメント

**所要時間**: 1日（実装） + 0.5日（テスト） = **1.5日**

#### Phase 3: マウント構造変更とシンボリックリンク

**目標**: CLI版コンテキストエンジニアリングを実現

**実装内容**:
1. `docker-compose.yml` の修正
   - `repos/` のマウント先を `/home/${UNAME}/<MonolithicDevContainerレポジトリ名>/repos` に変更
2. `post-create.sh` の新規作成（または `docker-entrypoint.sh` の拡張）
   - プロダクトリポジトリの自動clone
   - Devin互換用シンボリックリンク作成: `ln -sf /home/${UNAME}/<MonolithicDevContainerレポジトリ名>/repos /home/${UNAME}/repos`
3. `devcontainer.json.template` の修正
   - `postCreateCommand` の設定（post-create.sh実行）
4. 動作確認
   - CLI版AIエージェントが `/home/<user>/<MonolithicDevContainerレポジトリ名>` から全体を参照可能か確認
   - Devin互換性が維持されているか確認（`~/repos/` からアクセス可能か）
   - 既存機能が正常に動作するか確認

**影響範囲**: コンテナ内の全体構造

**成果物**:
- 修正された `docker-compose.yml`
- 新規作成された `post-create.sh`（または修正された `docker-entrypoint.sh`）
- 修正された `devcontainer.json.template`
- 動作確認結果のドキュメント

**所要時間**: 1日（実装） + 1日（テスト） = **2日**

#### Phase全体の所要時間

**合計: 4.5日**

**メリット**:
- ⭐⭐⭐ リスクが分散される
- ⭐⭐⭐ 各段階で動作確認可能
- ⭐⭐⭐ 問題発生時の切り分けが容易
- ⭐⭐ 段階的に機能が実現される

**デメリット**:
- ⚠️ 完全な実現まで時間がかかる
- ⚠️ 中間状態の管理が必要

---

### 解決策C: 新規ブランチで並行開発アプローチ

**概要**: 既存環境を維持しながら、新規ブランチで設計v10を完全実装

**実装内容**:
1. `feature/implement-design-v10` ブランチを作成
2. 設計v10を完全実装
3. 十分なテストを実施
4. 問題なければメインブランチにマージ

**メリット**:
- ⭐⭐⭐ 既存環境への影響ゼロ（マージまで）
- ⭐⭐⭐ 十分なテストが可能
- ⭐⭐ 切り戻しが容易

**デメリット**:
- ❌ ブランチ管理のオーバーヘッド
- ❌ マージ時に一度に大きな変更が発生
- ⚠️ 並行開発中の変更の取り込みが困難

**想定期間**:
- 実装: 1.5日
- テスト: 1.5日
- レビュー・マージ: 0.5日
- **合計: 3.5日**

---

## 解決策の比較表

| 観点 | A: 一括移行 | B: 段階的移行（採用） | C: 並行開発 |
|------|------------|---------------------|------------|
| **リスク** | ⭐ 高い | ⭐⭐⭐ 低い | ⭐⭐ 中程度 |
| **実現速度** | ⭐⭐⭐ 最速 | ⭐⭐ 中速 | ⭐ 遅い |
| **問題切り分け** | ⭐ 困難 | ⭐⭐⭐ 容易 | ⭐⭐⭐ 容易 |
| **既存環境への影響** | ❌ 即座に影響 | ⚠️ 段階的に影響 | ✅ マージまで影響なし |
| **中間状態の価値** | － | ⭐⭐⭐ 段階的に機能実現 | － |
| **切り戻し容易性** | ⭐ 困難 | ⭐⭐⭐ 容易 | ⭐⭐⭐ 容易 |
| **想定期間** | 2日 | 4.5日 | 3.5日 |

---

## 採用理由: 解決策B（段階的移行アプローチ）

1. **リスク管理**: 各段階で動作確認でき、問題の早期発見が可能
2. **段階的な価値提供**: Phase 1で既にVS Code拡張版のコンテキストエンジニアリングが実現
3. **切り戻し容易性**: 各Phaseで問題があれば前段階に戻せる
4. **学習曲線**: 段階的に変更を理解しながら進められる

**懸念点への対処**:
- 「完全な実現まで時間がかかる」→ 各Phaseで価値が出るため許容可能
- 「中間状態の管理が必要」→ 各Phaseの完了条件を明確にすることで対処

---

## 次のステップ

~~**Phase 1の実装から着手**~~

~~詳細は上記「Phase 1: workspace.code-workspace の記述」を参照。~~

**→ 計画変更: 一括移行アプローチ(解決策A)を採用**

理由: 段階的移行のPhase 1では、マウント構造が変更されていないため単独での動作確認が困難と判断。リスクを許容して一括移行を実施することで、最短で設計v10を実現する。

---

## 実施した実装（2026-01-02）

**採用アプローチ**: 解決策A（一括移行アプローチ）

### 実装内容

1. **`generate-env.sh` の修正**
   - `REPO_NAME` 環境変数を追加（リポジトリ名を自動取得）

2. **`docker-compose.yml` の修正**
   - `repos/` のマウント先を `/home/${UNAME}/${REPO_NAME}/repos` に変更
   - `working_dir` を `/home/${UNAME}/${REPO_NAME}` に変更

3. **`setup.sh` の修正**
   - `REPO_NAME` のテンプレート置換処理を追加

4. **`devcontainer.json.template` の修正**
   - `workspaceFolder` を `/home/__UNAME__/__REPO_NAME__` に変更
   - `postCreateCommand` を追加（post-create.sh実行）

5. **`post-create.sh` の新規作成**
   - Devin互換用シンボリックリンク作成処理
   - `/home/${UNAME}/repos` → `/home/${UNAME}/${REPO_NAME}/repos`
   - カレントディレクトリに依存しない実装

6. **`workspace.code-workspace` の記述**
   - マルチルートワークスペース設定
   - ルートと `repos/` 配下のプロダクトリポジトリを追加可能な構造

7. **`.gitignore` の更新**
   - `repos/` を除外リストに追加

### 生成された設定（確認済み）

- `workspaceFolder`: `/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>` ✅
- `postCreateCommand`: `bash /home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/.devcontainer/post-create.sh` ✅
- `REPO_NAME`: `<MonolithicDevContainerレポジトリ名>` ✅
- Docker Volume `repos` のマウント先: `/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/repos` ✅

### 次のステップ

1. ブランチを作成してpush
2. コンテナ起動とテスト
3. 動作確認結果のドキュメント化

---

## 変更履歴

### 2026-01-02
- 初版作成
- 実装と設計v10の乖離点を分析
- 5つの重大な乖離、1つの中程度の乖離を特定
- 対応方針のオプションを提示
- 設計v10への移行計画を追加（当初は段階的移行アプローチを採用）
- **計画変更**: 一括移行アプローチ(解決策A)に変更
- 設計v10への移行を実装完了
