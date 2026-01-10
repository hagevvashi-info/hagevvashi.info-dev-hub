# post-create.sh not found エラーの分析

**作成日**: 2026-01-02
**関連エラーログ**: [20260102_error.log](20260102_error.log)

## １．課題（目標とのギャップ）

**`post-create.sh` が実行されているが、ファイルが見つからないエラーが発生している**

エラーログ（[20260102_error.log:61](20260102_error.log#L61)）:
```
/bin/sh: 1: /home/<一般ユーザー>/hagevvashi.info-dev-hub/.devcontainer/post-create.sh: not found
```

**状況**:
- DevContainerのビルドは成功（image created）
- コンテナの起動も成功（Container Started）
- `postCreateCommand` 実行時にファイルが見つからない

## ２．原因

**Dockerfileに `post-create.sh` をコンテナにコピーする処理が存在しない**

### 設計v10の想定

設計v10（[14_詳細設計_ディレクトリ構成.v10.md](../20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v10.md)）では:
- `post-create.sh` は `postCreateCommand` で実行される前提
- コンテナ内に `/home/<user>/${REPO_NAME}/.devcontainer/post-create.sh` が存在する必要がある
- **実行時点では既に `${REPO_NAME}` がバインドマウントされている想定**

### 現在のDockerfileの状況

[.devcontainer/Dockerfile](../../.devcontainer/Dockerfile):
- ✅ `docker-entrypoint.sh` はコピーされている（line 115）
- ✅ シェル設定ファイル群もコピーされている（lines 120-124）
- ❌ **`post-create.sh` のコピー処理がない**

### 根本原因

**重要な考察**:
- `post-create.sh` は「コンテナ作成後」に実行される
- 実行時点では既に `${REPO_NAME}` がバインドマウントされている想定
- **つまり、ホスト側の `.devcontainer/post-create.sh` がそのままコンテナ内で見えるべき**

現在の問題:
- `${localWorkspaceFolder}` が `/home/<user>/${REPO_NAME}` に明示的にマウントされていない可能性
- VS Codeのデフォルトマウント挙動に依存している可能性
- マウント設定が不明確

## ３．目的（あるべき状態）

**設計v10に準拠し、`post-create.sh` が正しく実行される状態**

具体的には:
1. `post-create.sh` がコンテナ内に配置されている（バインドマウント経由）
2. Devin互換用シンボリックリンク `/home/<user>/repos` → `/home/<user>/${REPO_NAME}/repos` が作成される
3. CLI版AIエージェントが `/home/<user>/${REPO_NAME}` から全体を参照可能

これにより、設計v10の3つの要求を満たす:
1. **Devin互換性**: `~/repos/<product-repo>` でアクセス可能
2. **VS Code拡張版コンテキストエンジニアリング**: `workspace.code-workspace` で論理的に統合
3. **CLI版コンテキストエンジニアリング**: 物理的に `${REPO_NAME}/` 配下に統合

## ４．戦略・アプローチ（解決の方針）

**設計v10の意図を正しく理解し、マウント設定を明示的にする**

重要な設計判断:
- `post-create.sh` はイメージにコピーするのではなく、バインドマウント経由でアクセス可能にすべき
- これにより、開発時の柔軟性が保たれる（`post-create.sh` の変更がイメージ再ビルド不要で反映）
- マウント構造を明示的にすることで、動作が予測可能になる

## ５．解決策（最低3つ、異なる観点で比較可能なもの）

### 解決策1: `devcontainer.json.template` にマウント設定を追加

**アプローチ**: `devcontainer.json.template` で `${localWorkspaceFolder}` の明示的なマウントを設定

**修正箇所**: [.devcontainer/devcontainer.json.template](../../.devcontainer/devcontainer.json.template)

**修正内容**:
```json
"mounts": [
  "source=${localWorkspaceFolder},target=/home/__UNAME__/__REPO_NAME__,type=bind,consistency=cached",
  "source=__HOME__/.bash_history,target=/home/__UNAME__/.bash_history,type=bind,consistency=cached",
  ...
]
```

**動作**:
- ホストの `${localWorkspaceFolder}` が `/home/<user>/${REPO_NAME}` にバインドマウントされる
- `.devcontainer/post-create.sh` が自動的にコンテナ内で `/home/<user>/${REPO_NAME}/.devcontainer/post-create.sh` として見える

**メリット**:
- ✅ 設計v10の意図に最も近い
- ✅ Dockerfileへの変更不要
- ✅ `post-create.sh` がホストと同期される（開発時の柔軟性が高い）
- ✅ VS Codeの標準的なパターン

**デメリット**:
- ⚠️ `devcontainer.json` と `docker-compose.yml` の両方でマウント設定が必要になる可能性
- ⚠️ マウント設定の優先順位を理解する必要がある

**想定される影響**:
- VS Codeで開く際の挙動に変更が生じる可能性
- 既存の動作確認が必要

---

### 解決策2: Dockerfileに `COPY` 命令を追加

**アプローチ**: `docker-entrypoint.sh` と同様に、`post-create.sh` をコンテナイメージにコピー

**修正箇所**: [.devcontainer/Dockerfile](../../.devcontainer/Dockerfile) line 115付近

**修正内容**:
```dockerfile
# ENTRYPOINTスクリプトをコピー
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# postCreateスクリプトをコピー
COPY .devcontainer/post-create.sh /tmp/post-create.sh
RUN chmod +x /tmp/post-create.sh
```

その上で、[.devcontainer/devcontainer.json.template](../../.devcontainer/devcontainer.json.template) を修正:
```json
"postCreateCommand": "/tmp/post-create.sh"
```

**メリット**:
- ✅ シンプルで理解しやすい
- ✅ 確実に動作する
- ✅ マウント設定に依存しない
- ✅ 実装が容易

**デメリット**:
- ❌ `post-create.sh` の変更がイメージ再ビルドまで反映されない
- ❌ 開発時の柔軟性が低い
- ❌ ホストとの同期が取れない
- ❌ 設計v10の意図（バインドマウント活用）と乖離

**想定される影響**:
- 既存の動作への影響は最小限
- イメージサイズへの影響も微小

---

### 解決策3: `docker-compose.yml` でバインドマウントを明示（推奨）

**アプローチ**: `docker-compose.yml` で `${REPO_NAME}` 全体を明示的にバインドマウント

**修正箇所**: [.devcontainer/docker-compose.yml](../../.devcontainer/docker-compose.yml)

**修正内容**:
```yaml
volumes:
  # hagevvashi.info-dev-hub リポジトリ全体をバインドマウント
  - type: bind
    source: ..
    target: /home/${UNAME:-vscode}/${REPO_NAME}
    consistency: cached
  # repos/ を Docker Volume で直接マウント（I/Oパフォーマンス）
  - type: volume
    source: repos
    target: /home/${UNAME:-vscode}/${REPO_NAME}/repos
  # その他の既存マウント
  - type: bind
    source: ${HOME}/.bash_history
    target: /home/${UNAME:-vscode}/.bash_history
    consistency: cached
  ...
```

**動作**:
- ホストの `..`（リポジトリルート）が `/home/<user>/${REPO_NAME}` にバインドマウントされる
- `.devcontainer/post-create.sh` が自動的にコンテナ内で見える
- `repos/` は Docker Volume で `/home/<user>/${REPO_NAME}/repos` に直接マウント（設計v10準拠）

**メリット**:
- ✅ 設計v10に完全準拠（最も重要）
- ✅ マウント構造が明確で予測可能
- ✅ `post-create.sh` がホストと同期される
- ✅ 開発時の柔軟性が高い
- ✅ 設計ドキュメント（v10）との整合性が取れる

**デメリット**:
- ⚠️ 既存の `docker-compose.yml` への影響
- ⚠️ テストが必要
- ⚠️ `devcontainer.json` との整合性確認が必要

**想定される影響**:
- マウント構造の変更により、既存の動作に影響がある可能性
- 十分なテストが必要

---

## 比較表

| 観点 | 解決策1<br>devcontainer.json修正 | 解決策2<br>Dockerfileに COPY | 解決策3<br>docker-compose.yml修正（推奨） |
|------|----------------------------------|----------------------------|------------------------------------------|
| **設計v10準拠** | ⭐⭐⭐ 高い | ⭐ 低い | ⭐⭐⭐ 最も高い |
| **開発時の柔軟性** | ⭐⭐⭐ 高い | ⭐ 低い | ⭐⭐⭐ 高い |
| **実装のシンプルさ** | ⭐⭐ 中程度 | ⭐⭐⭐ シンプル | ⭐⭐ 中程度 |
| **動作保証** | ⭐⭐ 要確認 | ⭐⭐⭐ 確実 | ⭐⭐⭐ 確実 |
| **ホストとの同期** | ⭐⭐⭐ 同期される | ❌ 同期されない | ⭐⭐⭐ 同期される |
| **マウント構造の明確性** | ⭐⭐ やや不明確 | － | ⭐⭐⭐ 最も明確 |
| **既存環境への影響** | ⭐⭐ 中程度 | ⭐⭐⭐ 小さい | ⭐⭐ 中程度 |

---

## 推奨: 解決策3（docker-compose.yml修正）

### 推奨理由

1. **設計v10に完全準拠**
   - マウント構造が設計ドキュメント（[14_詳細設計_ディレクトリ構成.v10.md](../20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v10.md)）通りになる
   - `${REPO_NAME}` 全体が `/home/<user>/${REPO_NAME}` にバインドマウント
   - `repos/` が `/home/<user>/${REPO_NAME}/repos` に直接Docker Volumeマウント

2. **問題の根本解決**
   - `${localWorkspaceFolder}` が明示的にマウントされる
   - マウント構造が予測可能になる
   - 将来的な拡張も容易

3. **開発効率**
   - `post-create.sh` の変更がすぐ反映される
   - イメージ再ビルド不要
   - 開発・デバッグが容易

4. **設計意図との整合性**
   - 設計v10の「バインドマウントとDocker Volumeの使い分け」を実現
   - CLI版AIエージェント対応の基盤となる

### トレードオフの評価

- **既存環境への影響**: 中程度
  - マウント構造の変更が発生
  - 十分なテストが必要
  - **評価**: 設計v10への移行という大きな目的のために許容可能

- **実装の複雑さ**: 中程度
  - `docker-compose.yml` の修正が必要
  - マウント設定の理解が必要
  - **評価**: 一度理解すれば、以降はシンプルで明確

---

## 次のアクション

1. **`docker-compose.yml` を修正**
   - `${REPO_NAME}` 全体のバインドマウント設定を追加
   - `repos/` のマウント先を `/home/${UNAME}/${REPO_NAME}/repos` に変更（既に実施済み）

2. **コンテナを再起動してテスト**
   - DevContainerをリビルド
   - `post-create.sh` が正しく実行されるか確認

3. **動作確認**
   - シンボリックリンク `/home/<user>/repos` が作成されているか確認
   - CLI版AIエージェントが `/home/<user>/${REPO_NAME}` から全体を参照可能か確認
   - Devin互換性が維持されているか確認

4. **結果のドキュメント化**
   - 動作確認結果を記録
   - 問題があれば追加の対応を検討

---

## 参考資料

- [14_詳細設計_ディレクトリ構成.v10.md](../20251229--dev-hub-concept/14_詳細設計_ディレクトリ構成.v10.md): 設計v10の詳細
- [22_implementation_divergence_analysis.md](../20251229--dev-hub-concept/22_implementation_divergence_analysis.md): 実装と設計の乖離分析
- [21_foundations_initiatives_mount_issue.md](../20251229--dev-hub-concept/21_foundations_initiatives_mount_issue.md): マウント問題の整理と解決策の比較
- [20260102_error.log](20260102_error.log): 実際のエラーログ

---

## 変更履歴

### 2026-01-02
- 初版作成
- `post-create.sh not found` エラーの原因分析
- 3つの解決策を提示
- 解決策3（docker-compose.yml修正）を推奨
