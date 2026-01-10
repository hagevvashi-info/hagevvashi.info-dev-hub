# workspace.code-workspace の仕組み

## 概要

`workspace.code-workspace` は、VS Codeのマルチルートワークスペース機能を定義するための設定ファイルです。複数のディレクトリを1つのワークスペースとして統合管理できます。

## 基本的な仕組み

### ファイル形式

`workspace.code-workspace` はJSON形式のファイルで、以下のような構造を持ちます：

```json
{
  "folders": [
    {
      "path": "/path/to/folder1"
    },
    {
      "path": "/path/to/folder2"
    }
  ],
  "settings": {
    // ワークスペース固有の設定
  }
}
```

### 主な機能

1. **複数ディレクトリの統合表示**
   - エクスプローラーに複数のフォルダが表示される
   - 各フォルダは独立したルートとして扱われる

2. **統合された検索・編集**
   - すべてのフォルダ内のファイルを検索可能
   - すべてのフォルダ内のファイルを編集可能

3. **独立したGit操作**
   - 各フォルダは独立したGitリポジトリとして扱われる
   - 各フォルダで個別にコミット・PR提出が可能

4. **AIエージェントの参照**
   - AIエージェントがすべてのフォルダを参照可能
   - コンテキストエンジニアリングが容易になる

## エディタ別のサポート状況

### VS Code
- **完全サポート**
- `workspace.code-workspace` でマルチルートワークスペースを定義可能
- ネイティブ機能として提供

### code-server
- **サポートあり**
- VS Codeをベースにしているため、`workspace.code-workspace` をサポート
- ブラウザ経由でリモート開発が可能
- **注意点**: マルチテナント環境での使用は推奨されない（リソース管理・セキュリティ面）

### Kiro
- **サポートあり**
- AWS提供のエージェント型IDEで、VS Codeをベースに構築
- マルチルートワークスペースをサポート
- 同じウィンドウ内で異なるプロジェクトを開くことが可能

## AIエージェント別のサポート状況

### Cursor
- **サポートあり**
- VS Codeをベースにしているため、`workspace.code-workspace` をサポート
- マルチルートワークスペース内のすべてのフォルダを参照可能

### Claude Code
- **完全サポート**
- VS Codeのネイティブ拡張機能として提供
- VS Codeのマルチルートワークスペース機能を完全にサポート
- プロジェクト全体の構造と依存関係を自動的にマッピング
- 複数のプロジェクトやリポジトリを同時に扱う環境で効果的に機能

### Gemini CLI
- **部分的サポート（推測）**
- CLIツールとして動作するため、VS Codeのマルチルートワークスペース機能に直接対応しているという明確な情報は見つからない
- ただし、CLIツールとしての特性上、複数のプロジェクトやディレクトリを柔軟に扱うことが可能
- 大規模なコードベースの分析やマルチモーダル処理（画像やPDFの解析）に強み
- 他のツールと連携してコンテキストエンジニアリングを効率化可能

### Codex CLI
- **部分的サポート（推測）**
- VS Codeの拡張機能やCLIとして利用可能
- マルチルートワークスペース機能への対応状況が明確ではない
- ただし、CLIツールとしての特性上、複数のプロジェクトやディレクトリを柔軟に扱うことが可能
- GitHubとの統合や自動ToDo管理などの機能を備え、複数のプロジェクトを効率的に管理可能

## この設計での活用方法

### 想定される構成

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

### 実現できること

1. **コンテキストエンジニアリング**
   - AIエージェントが `${project}-dev-hub/foundations/`、`${project}-dev-hub/initiatives/`、`repos/<product-repo>` を同時に参照可能
   - プロダクトコード開発時に、設計思想や文脈情報を自然に参照できる

2. **同時コントリビューション**
   - `${project}-dev-hub` と `<product-repo>` の両方に同時にコントリビューション可能
   - 各リポジトリで独立してコミット・PR提出が可能

3. **Devin互換性の維持**
   - `repos/<product-repo>` は `/home/<user>/repos/<product-repo>` に配置（Devin互換性）
   - I/Oパフォーマンスを維持（Docker Volume上）

## 設計上の利点

1. **シンプルな構造**
   - シンボリックリンクが不要
   - マウント構造が明確

2. **柔軟性**
   - 新しいプロダクトリポジトリを簡単に追加可能
   - `post-create.sh` で自動的に `workspace.code-workspace` を更新可能

3. **エディタ非依存**
   - VS Code、code-server、Kiroなど、複数のエディタで動作
   - 標準的な仕組みを活用

## 運用上の考慮事項

### workspace.code-workspace の管理

設計ドキュメント（QA v5）によると：
- `workspace.code-workspace` はGit管理対象（コミットする）
- 新しいリポジトリを追加する際は、`post-create.sh` と `workspace.code-workspace` の両方を更新
- 将来的には `post-create.sh` で自動生成することも検討可能（ただし、Git上で常に「変更あり」と表示されるため、手動管理が推奨）

### マウント設定との関係

- `${project}-dev-hub` はバインドマウント（Git管理と編集性）
- `repos/` はDocker Volume上（I/Oパフォーマンス）
- `workspace.code-workspace` は、これらの物理的な配置を論理的に統合する役割

## 設定のスコープと優先順位

### VS Code設定の優先順位（スコープ）

VS Codeの設定には明確な優先順位があり、下に行くほど強く（上書きされる）なります：

1. **Default Settings** - VS Codeの初期値
2. **User Settings** - 個人のGlobal設定
3. **Remote Settings** - DevContainer内の `.vscode-server/data/Machine/settings.json`
4. **Workspace Settings** - `workspace.code-workspace` の `"settings"`
5. **Folder Settings** - 各リポジトリ直下の `.vscode/settings.json`

### マルチルートワークスペースにおける設定の継承

**重要な仕組み**: マルチルートワークスペースでは、各ルートフォルダ（`folders`に書かれたパス）は**論理的に並列（兄弟）**として扱われます。

```
誤った理解:
dev-hub/                          ← ここの .vscode/settings.json は
  └── repos/
      └── product-a/              ← product-a には継承されない
```

```
正しい理解:
workspace.code-workspace
  ├─ dev-hub/                     ← ルートフォルダ1（兄弟）
  └─ repos/product-a/             ← ルートフォルダ2（兄弟）
```

親ディレクトリに `.vscode/settings.json` があっても、兄弟としてマウントされたサブディレクトリには影響を及ぼしません。

### 共通設定の記述方法

**解決策**: `workspace.code-workspace` の `"settings"` に記述する

```json
{
  "folders": [
    {
      "path": ".",
      "name": "dev-platform"
    },
    {
      "path": "repos/product-a",
      "name": "product-a"
    }
  ],
  "settings": {
    // UIのテーマ設定など
    "workbench.colorTheme": "Default Dark Modern",

    // エディタの挙動（フォーマットなど）
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",

    // 特定の言語ごとの設定も可能
    "[python]": {
      "editor.defaultFormatter": "ms-python.python"
    },

    // 検索除外設定など
    "search.exclude": {
      "**/node_modules": true,
      "**/dist": true
    }
  }
}
```

このワークスペースを開いている限り、`product-a` にも `dev-platform` にも上記の設定が適用されます。

### Monolithic DevContainerにおける推奨方針

「環境の統一」という目的を考えると、以下の使い分けがベストプラクティスです：

#### 1. 共通のルール（フォーマッタ、除外設定、共通のツールパスなど）

**→ `workspace.code-workspace` の `"settings"` に書く**

- `repos/` 配下のどのプロダクトを開いても、チーム全員が同じ挙動になる
- 各プロダクトリポジトリの `.gitignore` を汚さずに済む

#### 2. リポジトリ固有の例外ルール

**→ 各リポジトリ (`repos/product-a/.vscode/settings.json`) に書く**

- 例: 特定のプロダクトだけビルドコマンドが特殊、特定のプロダクトだけ言語バージョンが違う、など
- **注意**: ここに書いた設定は、`workspace.code-workspace` の設定よりも**優先（上書き）**されます

### よくある誤解と解決策

#### 誤解: 「dev-hubのルートに.vscodeを置けば、配下のrepos/にも効くはず」

**現実**: `workspace.code-workspace` で `repos/product-a` を**別のルートフォルダ**として定義している場合、`dev-hub` の設定は `product-a` には**継承されません**。

#### 解決策

共通設定は `workspace.code-workspace` の `"settings"` に集約することで、すべてのルートフォルダに適用されます。

## 拡張機能の管理

### workspace.code-workspaceでの拡張機能推奨

`workspace.code-workspace` ファイル内に `extensions` プロパティを追加して、推奨拡張機能をリスト化できます。

```json
{
  "folders": [
    {
      "path": ".",
      "name": "dev-platform"
    },
    {
      "path": "repos/product-a",
      "name": "product-a"
    }
  ],
  "settings": {
    // 共通設定
  },
  "extensions": {
    "recommendations": [
      "esbenp.prettier-vscode",
      "dbaeumer.vscode-eslint",
      "eamodio.gitlens"
    ]
  }
}
```

**挙動**:
- このワークスペースを開くと、VS Codeの拡張機能サイドバーの「推奨（Recommended）」欄に記載された拡張機能が表示される
- 各リポジトリ直下の `.vscode/extensions.json` の内容と**マージ（合算）**される
- ユーザーがボタンを押してインストールする必要がある（あくまで「推奨」）

### DevContainerにおける推奨方針

Monolithic DevContainer環境では、**`devcontainer.json`に記述する方が強力かつ推奨されます。**

#### 理由

| 記述場所 | 挙動 | 用途 |
|---------|------|------|
| `.code-workspace` / `extensions.json` | 「推奨」として表示されるだけ | 緩やかな推奨 |
| `devcontainer.json` | コンテナビルド時に**自動的にインストール** | 必須ツール |

#### devcontainer.jsonでの記述例

```json
{
  "name": "Monolithic DevContainer",

  "customizations": {
    "vscode": {
      "extensions": [
        "esbenp.prettier-vscode",
        "dbaeumer.vscode-eslint",
        "ms-azuretools.vscode-docker"
      ],
      "settings": {
        // コンテナ内でのデフォルト設定など
      }
    }
  }
}
```

### 使い分けのベストプラクティス

#### 1. 必須ツール（チーム全員に強制）

**→ `devcontainer.json` の `customizations.vscode.extensions` に書く**

- コンテナ起動時に自動インストール
- 「環境構築作業をゼロにする」という目的に合致
- 例: Linter、Formatter、言語サーバー

#### 2. 任意の便利ツール（推奨レベル）

**→ `workspace.code-workspace` の `extensions.recommendations` に書く**

- ユーザーが選択してインストール
- 個人の好みに応じて選択可能
- 例: GitLens、テーマ、アイコンパック

### 拡張機能のマージ動作

複数の場所に拡張機能を定義した場合、以下のようにマージされます：

```
最終的な推奨リスト =
  devcontainer.json の extensions (自動インストール)
  + workspace.code-workspace の recommendations
  + 各フォルダの .vscode/extensions.json の recommendations
```

すべてが合算されて表示され、どれかが無効になることはありません。

## まとめ

`workspace.code-workspace` は、複数のディレクトリを1つのワークスペースとして統合管理するための標準的な仕組みです。VS Code、code-server、Kiroなど、複数のエディタでサポートされており、この設計での要求（コンテキストエンジニアリング、同時コントリビューション、Devin互換性）を実現するための最適な解決策と考えられます。

特に、`"settings"` プロパティを活用することで、マルチルートワークスペース全体に共通の設定を適用でき、Monolithic DevContainerの「環境の統一」という目的を効果的に実現できます。

