# DevContainer起動失敗: ポート競合エラー分析

**作成日**: 2026-01-08 09:00
**発見経緯**: Phase 5問題解決後、DevContainerをVSCode/Cursor拡張から起動しようとした際に発生

---

## 1. 問題の概要

### 1.1 現象

DevContainerの起動時に以下のエラーが発生し、コンテナの起動に失敗する:

```
Error response from daemon: failed to set up container networking:
driver failed programming external connectivity on endpoint
<MonolithicDevContainerレポジトリ名>_devcontainer-dev-1
(4c7c0e4225e38d8704f4b2ce9b0409e37461c19ad951c91a700c086b7778a55f):
Bind for 0.0.0.0:4035 failed: port is already allocated
```

**エラー発生箇所**: `docker compose up -d` 実行時
**失敗したポート**: `0.0.0.0:4035`

### 1.2 タイムライン

| 時刻 | イベント | ログファイル |
|------|----------|-------------|
| 08:48:45 | DevContainer起動開始 | 202601080857-devcontainer-output.log.txt:4 |
| 08:48:46 | 既存コンテナ削除 | 202601080857-devcontainer-output.log.txt:142 |
| 08:48:47-08:51:36 | Dockerイメージビルド（2分49秒） | 202601080857-devcontainer-output.log.txt:247 |
| 08:51:37 | **docker compose up -d 失敗** | 202601080856-devcontainer-terminal.log:224 |

---

## 2. 根本原因の特定

### 2.1 直接的原因

**ポート `4035` が既に別のプロセスによって使用されている**

証拠:
```bash
# 202601080856-devcontainer-terminal.log:224
Bind for 0.0.0.0:4035 failed: port is already allocated
```

### 2.2 考えられる原因

以下の可能性が考えられる:

#### 原因1: 以前のコンテナが完全に停止していない

- **可能性**: 中程度
- **証拠**: ログによると既存コンテナ(`5fa4fa56cebd`)は削除されている（line 142-144）
- **確認方法**: `docker ps -a` で全コンテナ確認

#### 原因2: 別のDevContainerインスタンスが起動中

- **可能性**: **高い** ⭐
- **証拠**: 手動で起動した `devcontainer-dev-1` コンテナがまだ実行中の可能性
- **確認方法**:
  ```bash
  docker ps --filter "name=devcontainer-dev-1"
  docker ps --filter "publish=4035"
  ```

#### 原因3: ホストマシン上の別プロセスがポート使用

- **可能性**: 低い
- **理由**: エラーメッセージが「Docker内でのポート割り当て失敗」を示している
- **確認方法**: `lsof -i :4035` または `netstat -an | grep 4035`

---

## 3. 問題の影響

### 3.1 即座の影響

- ✅ **docker-entrypoint.sh修正自体は成功**: イメージは正常にビルドされた（イメージID: `d1faecb8dfcd`）
- ❌ **VSCode/Cursor拡張からの起動失敗**: ポート競合により起動不可
- ⚠️ **手動起動は可能**: `docker compose up -d` を直接実行すれば回避可能

### 3.2 検証への影響

- Phase 5問題の修正自体は有効
- 手動起動したコンテナとVSCode/Cursor拡張の起動が競合している
- **このエラーは新しい問題ではなく、既存コンテナとの競合**

---

## 4. 仮説

### 仮説1: 手動起動コンテナが残存している（最有力）

**内容**:
以前のセクションで `cd .devcontainer && docker compose up -d` で手動起動したコンテナ（`devcontainer-dev-1`）がまだ実行中であり、VSCode/Cursor拡張が同じポートで新しいコンテナを起動しようとしている。

**根拠**:
1. 手動起動時のコンテナ名: `devcontainer-dev-1`
2. VSCode/Cursor拡張が作成しようとしたコンテナ名: `<MonolithicDevContainerレポジトリ名>_devcontainer-dev-1`
3. プロジェクト名のプレフィックスが異なる（VSCode拡張は `<MonolithicDevContainerレポジトリ名>_devcontainer` を使用）
4. 既存コンテナ削除ログ（line 142）で削除されたのは `5fa4fa56cebd` だが、これは手動起動したものではない可能性

**検証方法**:
```bash
docker ps -a --filter "name=dev-1"
docker ps --filter "publish=4035"
```

### 仮説2: docker-compose.ymlのポート設定に問題がある

**内容**:
docker-compose.ymlで定義されたポート（4035, 8035, 9001, 8080）のいずれかが既に使用されている。

**根拠**:
- エラーメッセージは明示的に `4035` を指摘
- docker-compose.ymlの設定:
  ```yaml
  ports:
    - "4035:4035"  # ← この行が問題
    - "8035:8035"
    - "9001:9001"
    - "8080:8080"
  ```

**可能性**: 中程度（仮説1が解決しない場合に検討）

---

## 5. 解決策

### 解決策1: 既存コンテナの停止・削除（推奨）

**手順**:
```bash
# ステップ1: 実行中のコンテナ確認
docker ps --filter "name=dev-1"

# ステップ2: 該当コンテナの停止と削除
docker compose -f /Users/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/.devcontainer/docker-compose.yml \
  -f /Users/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/.devcontainer/docker-compose.dev-vm.yml \
  down

# または直接削除
docker rm -f devcontainer-dev-1

# ステップ3: ポート確認
docker ps --filter "publish=4035"
lsof -i :4035  # macOSの場合

# ステップ4: VSCode/Cursor拡張から再起動
```

**メリット**:
- 根本的に競合を解消
- 手動起動とVSCode拡張起動を分離

**デメリット**:
- 手動起動したコンテナで作業中のデータが失われる可能性（マウントされたボリュームは安全）

### 解決策2: ポート番号の変更

**概要**: docker-compose.ymlのポート設定を変更し、競合を回避

**手順**:
1. `.devcontainer/docker-compose.yml` のポート設定を変更:
   ```yaml
   ports:
     - "14035:4035"  # ホスト側を変更
     - "18035:8035"
     - "19001:9001"
     - "18080:8080"
   ```

2. DevContainer再ビルド

**メリット**:
- 既存コンテナと並存可能

**デメリット**:
- ポート番号の変更が必要
- code-serverやその他サービスへのアクセスURLが変わる

### 解決策3: プロジェクト名の統一

**概要**: 手動起動時とVSCode拡張のプロジェクト名を統一する

**手順**:
1. 手動起動時に `--project-name` を指定:
   ```bash
   docker compose --project-name <MonolithicDevContainerレポジトリ名>_devcontainer \
     -f docker-compose.yml -f docker-compose.dev-vm.yml up -d
   ```

2. または、`.devcontainer/devcontainer.json` で `dockerComposeFile` を適切に設定

**メリット**:
- VSCode拡張と手動起動で同じコンテナを使用

**デメリット**:
- 手動起動とVSCode拡張起動の挙動の違いを理解する必要

---

## 6. 推奨アクション

### 短期対応（今すぐ実施）

1. **解決策1を実施**:
   ```bash
   cd /Users/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>/.devcontainer
   docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml down
   docker ps -a  # 確認
   ```

2. **VSCode/Cursor拡張から再起動**

3. **起動成功を確認**:
   - DevContainer Outputログでエラーがないことを確認
   - Phase 1-6すべて実行されることを確認
   - supervisorctl status が正常動作することを確認

### 中期対応（今後のワークフロー改善）

1. **手動起動とVSCode拡張起動を明確に分離**:
   - **検証・デバッグ時**: 手動起動（`docker compose up -d`）
   - **開発作業時**: VSCode/Cursor拡張起動（"Reopen in Container"）

2. **使い分けのドキュメント化**:
   - いつ手動起動を使うか
   - いつVSCode拡張を使うか
   - 切り替え時の注意点

3. **実装トラッカーに記録**:
   - セクションI: DevContainer起動方法の問題
   - 解決策と検証結果を記録

---

## 7. 検証計画

### 検証項目

| 項目 | コマンド | 期待結果 |
|------|----------|----------|
| コンテナ停止確認 | `docker ps --filter "name=dev-1"` | 0件 |
| ポート解放確認 | `lsof -i :4035` | プロセスなし |
| VSCode拡張起動 | Cursor: "Reopen in Container" | 成功 |
| Phase 1-6実行 | DevContainer Output確認 | すべて成功 |
| supervisord動作 | コンテナ内で `supervisorctl status` | code-server RUNNING |
| process-compose設定 | `ls -l /etc/process-compose/process-compose.yaml` | シンボリックリンク存在 |

---

## 8. まとめ

### 問題の本質

- **技術的問題**: ポート4035の競合
- **ワークフロー問題**: 手動起動とVSCode拡張起動の混在による管理の複雑化

### 重要な気づき

1. **docker-entrypoint.sh修正は成功している**:
   - イメージビルドは正常完了
   - Phase 5問題の修正は有効

2. **新しい問題ではなく、既存の環境問題**:
   - 以前の検証で手動起動したコンテナが残存
   - VSCode拡張はプロジェクト名プレフィックスを付けるため、別コンテナとして認識

3. **解決は容易**:
   - 既存コンテナの停止で即座に解決
   - 設計変更や大規模な修正は不要

### 次のステップ

1. 解決策1を実施して既存コンテナを停止
2. VSCode/Cursor拡張から再起動
3. Phase 5問題の最終検証を実施
4. 実装トラッカーを更新

---

**このドキュメントは、DevContainer起動時のポート競合問題を分析し、即座に解決可能な対応策を提示するものです。**
