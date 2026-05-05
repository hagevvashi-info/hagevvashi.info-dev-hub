# foundations/ と initiatives/ のマウント問題の整理（改訂版）

## 1. 課題（目標とのギャップ）

**3つの重要な要求を同時に満たすマウント構造が実現できていない**

### 要求①：Devinとの互換性
- 汎用AIエージェントであるDevinは `~/repos/<product-repo>` にチェックアウトする前提
- `${project}-dev-hub` でも（コンテナ上でも）`~/repos/<product-repo>` に展開したい
- 現在の設計では `/home/<user>/repos/` にDocker Volumeでマウントされており、この要求は**満たされている**

### 要求②：コンテキストエンジニアリング（VS Code拡張機能版）
- 流動的情報（`initiatives/`）やFixedな情報（`foundations/`）が `${project}-dev-hub` に入っている
- AIエージェント（Cursor、Claude Code拡張機能版）が関連コンテキストを自動的に読み取りやすくしたい
- `workspace.code-workspace` によるマルチルートワークスペース機能で**部分的に満たされている**
  - VS Code拡張機能版では、`foundations/`、`initiatives/`、`repos/*` を統一的に参照可能
  - しかし、物理的には分離されたまま

### 要求③：CLI版AIエージェント対応（新規追加）
- **Claude Code CLI、Gemini CLI等は、起動したカレントディレクトリがワークスペースルートになる**
- `workspace.code-workspace` の恩恵を受けられない
- 物理的なディレクトリ構造として、`foundations/`、`initiatives/`、`repos/*` が統一的にアクセスできる必要がある
- 現在の設計では、この要求は**満たされていない**

### 具体的な問題

**VS Code拡張機能版では解決、CLI版では未解決**

- VS Code拡張機能版（Cursor、Claude Code拡張）
  - ✅ `workspace.code-workspace` で論理的に統合
  - ✅ すべてのフォルダを参照可能

- CLI版（Claude Code CLI、Gemini CLI等）
  - ❌ `/home/user/repos/product-a` で起動 → `foundations/`、`initiatives/` が見えない
  - ❌ `/home/user/${project}-dev-hub` で起動 → `repos/*` が見えない（別マウント）
  - ❌ カレントディレクトリの制約から逃れられない

## 2. 原因

**AIエージェントの起動方式の違いを考慮した設計になっていない**

- **要求①は満たされている**
  - `repos/` は `/home/<user>/repos/` にDocker Volumeでマウント（Devin互換性確保）

- **要求②は部分的に満たされている**
  - `workspace.code-workspace` により、VS Code拡張機能版では論理的に統合
  - しかし、物理的には `${project}-dev-hub` と `repos/` が分離

- **要求③（CLI版）への対応が不足**
  - CLI版AIエージェントは、物理的なディレクトリ構造に依存する
  - `workspace.code-workspace` は無関係
  - カレントディレクトリ起点でしか動作しない

- **起動場所の運用が定まっていない**
  - どこで `claude-code` を起動すべきか明確でない
  - 起動場所によって参照できる範囲が変わる

## 3. 目的（あるべき状態）

**3つの要求を同時に満たし、AIエージェントの起動方式に依存しないコンテキストエンジニアリングを実現する状態**

### 要求①の満足
- `~/repos/<product-repo>` でプロダクトリポジトリにアクセス可能（Devin互換性）
- I/Oパフォーマンスを維持（Docker Volume上）

### 要求②の満足（VS Code拡張機能版）
- `workspace.code-workspace` によるマルチルートワークスペース機能で実現済み
- VS Code拡張機能版AIエージェントが `foundations/`、`initiatives/`、`repos/*` を統一的に参照可能

### 要求③の満足（CLI版）
- **CLI版AIエージェントが、1つのディレクトリから `foundations/`、`initiatives/`、`repos/*` すべてにアクセス可能**
- 物理的なディレクトリ構造として、`${project}-dev-hub/` 配下で統一的に参照できる
- 推奨起動場所が明確（例：`/home/user/${project}-dev-hub`）

### その他の要件
- マウント設定が明示的で、どのパスでアクセスできるか明確
- `repos/` はDocker Volume上（I/Oパフォーマンス）、`${project}-dev-hub` リポジトリはバインドマウント（Git管理と編集性）という分離を維持
- VS Codeの標準パターンとの整合性（可能な範囲で）

## 4. 戦略・アプローチ（解決の方針）

**物理的なディレクトリ統合により、CLI版AIエージェントでもコンテキストエンジニアリングを実現する**

- **`${project}-dev-hub` を `/home/<user>/` 配下にマウント**
  - これにより、`${project}-dev-hub/repos/` というパス構造を実現可能にする
  - `repos/` はDocker Volumeで `/home/<user>/repos/` にマウント（既存のまま）
  - `${project}-dev-hub` 内に `repos/` へのシンボリックリンクを作成することで、`${project}-dev-hub/repos/` からアクセス可能にする

- **推奨起動場所の明確化**
  - CLI版AIエージェントは `/home/<user>/${project}-dev-hub` で起動
  - VS Code拡張機能版は `workspace.code-workspace` を開く
  - 運用フローを `foundations/onboarding/` に明記

- **明示的なマウント設定**
  - `${project}-dev-hub` リポジトリ全体を明示的にバインドマウントする
  - マウント先パスを固定し、AIエージェントが参照しやすい場所に配置する

## 5. 解決策（最低3つ、異なる観点で比較可能なもの）

### 解決策1: `${project}-dev-hub` を `/home/<user>/${project}-dev-hub` にマウント + `repos/` へのシンボリックリンク

**アプローチ**: ホームディレクトリ配下に統合し、シンボリックリンクで `repos/` を接続

```json
"mounts": [
  "source=${localWorkspaceFolder},target=/home/<user>/${project}-dev-hub,type=bind,consistency=cached"
],
"workspaceFolder": "/home/<user>/${project}-dev-hub"
```

`post-create.sh` でシンボリックリンクを作成：

```bash
ln -sf /home/<user>/repos /home/<user>/${project}-dev-hub/repos
```

**ディレクトリ構造**：
```
/home/<user>/
├── ${project}-dev-hub/           # バインドマウント
│   ├── foundations/
│   ├── initiatives/
│   ├── members/
│   ├── workspace.code-workspace
│   └── repos -> /home/<user>/repos/  # シンボリックリンク
└── repos/                        # Docker Volume
    ├── product-a/
    └── product-b/
```

**CLI版AIエージェントの起動方法**：
```bash
cd /home/<user>/${project}-dev-hub
claude-code
# → foundations/, initiatives/, repos/* すべて参照可能
```

**メリット**:
- ✅ 3つの要求をすべて満たす
- ✅ CLI版AIエージェントが `/home/<user>/${project}-dev-hub` から全体を参照可能
- ✅ Devin互換性を維持（`~/repos/<product-repo>` でもアクセス可能）
- ✅ I/Oパフォーマンスを維持（`repos/` はDocker Volume上）
- ✅ VS Code拡張機能版も `workspace.code-workspace` で引き続き動作

**デメリット**:
- ⚠️ シンボリックリンクの管理が必要
- ⚠️ `workspaceFolder` の変更が必要
- ⚠️ VS Codeの標準パターン（`/workspaces/`）と異なる

---

### 解決策2: `${project}-dev-hub` を `/workspaces/${project}-dev-hub` にマウント + `repos/` へのシンボリックリンク

**アプローチ**: VS Codeの標準パターンに合わせつつ、シンボリックリンクで `repos/` を接続

```json
"mounts": [
  "source=${localWorkspaceFolder},target=/workspaces/${project}-dev-hub,type=bind,consistency=cached"
],
"workspaceFolder": "/workspaces/${project}-dev-hub"
```

`post-create.sh` でシンボリックリンクを作成：

```bash
ln -sf /home/<user>/repos /workspaces/${project}-dev-hub/repos
```

**ディレクトリ構造**：
```
/workspaces/
└── ${project}-dev-hub/           # バインドマウント
    ├── foundations/
    ├── initiatives/
    ├── members/
    ├── workspace.code-workspace
    └── repos -> /home/<user>/repos/  # シンボリックリンク

/home/<user>/
└── repos/                        # Docker Volume
    ├── product-a/
    └── product-b/
```

**CLI版AIエージェントの起動方法**：
```bash
cd /workspaces/${project}-dev-hub
claude-code
# → foundations/, initiatives/, repos/* すべて参照可能
```

**メリット**:
- ✅ 3つの要求をすべて満たす
- ✅ VS Codeの標準パターンに準拠
- ✅ CLI版AIエージェントが `/workspaces/${project}-dev-hub` から全体を参照可能
- ✅ Devin互換性を維持
- ✅ I/Oパフォーマンスを維持

**デメリット**:
- ⚠️ シンボリックリンクの管理が必要
- ⚠️ パスが複数になり混乱の可能性（`/workspaces/` と `/home/` の両方）
- ⚠️ Devin互換の `~/repos/` と、開発拠点の `/workspaces/` が離れている

---

### 解決策3: `${project}-dev-hub` を `/home/<user>/${project}-dev-hub` にマウント + `repos/` を直接配置

**アプローチ**: `repos/` を `${project}-dev-hub}` 配下に直接Docker Volumeマウントし、完全に統合

```json
"mounts": [
  "source=${localWorkspaceFolder},target=/home/<user>/${project}-dev-hub,type=bind,consistency=cached",
  "source=repos,target=/home/<user>/${project}-dev-hub/repos,type=volume"
],
"workspaceFolder": "/home/<user>/${project}-dev-hub"
```

`post-create.sh` でDevin互換用のシンボリックリンクを作成：

```bash
ln -sf /home/<user>/${project}-dev-hub/repos /home/<user>/repos
```

**ディレクトリ構造**：
```
/home/<user>/
├── ${project}-dev-hub/           # バインドマウント
│   ├── foundations/
│   ├── initiatives/
│   ├── members/
│   ├── workspace.code-workspace
│   └── repos/                    # Docker Volume（直接マウント）
│       ├── product-a/
│       └── product-b/
└── repos -> /home/<user>/${project}-dev-hub/repos/  # シンボリックリンク（Devin互換用）
```

**CLI版AIエージェントの起動方法**：
```bash
cd /home/<user>/${project}-dev-hub
claude-code
# → foundations/, initiatives/, repos/* すべて参照可能（シンボリックリンク不要）
```

**メリット**:
- ✅ 3つの要求をすべて満たす
- ✅ パス構造が最もシンプルで明確
- ✅ CLI版AIエージェントが自然に全体を参照可能
- ✅ コンテキストエンジニアリングを完全に実現
- ✅ I/Oパフォーマンスを維持（Docker Volume）
- ✅ Devin互換性も逆向きシンボリックリンクで維持

**デメリット**:
- ⚠️ `repos/` のマウント先が変更されるため、既存設定への影響がやや大きい
- ⚠️ Devin互換性が「逆向きシンボリックリンク」に依存（本来の `/home/<user>/repos/` ではない）

---

## 比較表

| 観点 | 解決策1<br>(/home/配下 + repos→シンボリックリンク) | 解決策2<br>(/workspaces/配下 + repos→シンボリックリンク) | 解決策3<br>(/home/配下 + repos直接配置) |
|------|--------------------------------------|-------------------------------------------|-------------------------------|
| **Devin互換性** | ⭐⭐⭐ 高い（本来の`~/repos/`） | ⭐⭐⭐ 高い（本来の`~/repos/`） | ⭐⭐ 中程度（逆向きシンボリックリンク） |
| **CLI版コンテキストエンジニアリング** | ⭐⭐⭐ 高い | ⭐⭐⭐ 高い | ⭐⭐⭐ 高い（最も自然） |
| **VS Code拡張版コンテキストエンジニアリング** | ⭐⭐⭐ 高い | ⭐⭐⭐ 高い | ⭐⭐⭐ 高い |
| **VS Code標準との整合性** | ⭐⭐ 中程度 | ⭐⭐⭐ 高い | ⭐⭐ 中程度 |
| **I/Oパフォーマンス** | ⭐⭐⭐ 高い | ⭐⭐⭐ 高い | ⭐⭐⭐ 高い |
| **パスの明確性** | ⭐⭐⭐ 明確 | ⭐⭐ やや複雑 | ⭐⭐⭐ 最も明確 |
| **実装の複雑さ** | ⭐⭐ やや複雑 | ⭐⭐ やや複雑 | ⭐⭐⭐ シンプル |
| **既存設定への影響** | ⭐⭐⭐ 小さい | ⭐⭐⭐ 小さい | ⭐⭐ 中程度 |

---

## 推奨

**解決策3（`/home/<user>/${project}-dev-hub` にマウント + `repos/` を直接配置）** を推奨します。

### 理由：

1. **3つの要求をすべて満たす**
   - ✅ Devin互換性（逆向きシンボリックリンクで対応）
   - ✅ VS Code拡張版コンテキストエンジニアリング（workspace.code-workspace継続）
   - ✅ CLI版コンテキストエンジニアリング（物理的に統合）

2. **パス構造が最もシンプルで明確**
   - すべてが `/home/<user>/${project}-dev-hub/` 配下に集約
   - CLI版AIエージェントの起動場所が自明

3. **将来性**
   - CLI版AIエージェントの重要性が増す可能性が高い
   - 物理的な統合が最も堅牢

4. **運用の明確性**
   - **推奨起動場所**: `/home/<user>/${project}-dev-hub`
   - VS Code拡張版: `workspace.code-workspace` を開く
   - CLI版: `cd /home/<user>/${project}-dev-hub && claude-code`

### トレードオフの評価：

- **Devin互換性の「逆向きシンボリックリンク」依存**
  - 許容可能：Devinも結局シンボリックリンクを辿れる
  - 本来の `/home/<user>/repos/` も引き続きアクセス可能

- **既存設定への影響**
  - 限定的：`repos/` のマウント先変更のみ
  - `workspaceFolder` の変更は3案とも共通
