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

## まとめ

`workspace.code-workspace` は、複数のディレクトリを1つのワークスペースとして統合管理するための標準的な仕組みです。VS Code、code-server、Kiroなど、複数のエディタでサポートされており、この設計での要求（コンテキストエンジニアリング、同時コントリビューション、Devin互換性）を実現するための最適な解決策と考えられます。

