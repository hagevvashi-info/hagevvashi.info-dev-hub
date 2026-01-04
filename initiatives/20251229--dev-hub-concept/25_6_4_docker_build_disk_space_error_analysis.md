# Docker Build ディスク容量不足エラーの分析と解決策

**作成日**: 2026-01-04
**エラー発生箇所**: Dockerfile 240行目 (`pipx install csvkit`)
**関連ログ**: `202601041916-docker-compose-build.log`

---

## 1. 課題（目標とのギャップ）

### 1.1 発生したエラー

docker-entrypoint.sh 修正後の検証のため DevContainer を再ビルドしたところ、以下のエラーで失敗:

```
ERROR: Could not install packages due to an OSError: [Errno 28] No space left on device: '/home/hagevvashi/.local/pipx/venvs/csvkit/lib/python3.11/site-packages/babel/locale-data/en_BM.dat'
```

### 1.2 目標とのギャップ

- **目標**: DevContainer を正常にビルドし、docker-entrypoint.sh の修正を検証する
- **現状**: ディスク容量不足により Dockerfile の Step 40/43 (`pipx install csvkit`) で失敗
- **ギャップ**: Docker Desktop の仮想ディスクが満杯に近い状態

---

## 2. 原因

### 2.1 直接的原因

**Docker ビルド中のディスク容量不足**

エラーメッセージ:
```
[Errno 28] No space left on device
```

発生箇所:
- Dockerfile 240行目: `pipx install csvkit` 実行中
- `webssh` のインストールは成功、`csvkit` で失敗
- `csvkit` の依存パッケージ `babel` のロケールデータ書き込み時にディスク容量不足

### 2.2 Docker ディスク使用状況

#### ホストのディスク状況
```
/dev/disk3s5  460Gi  188Gi  249Gi  44%  /System/Volumes/Data
```
- **使用率**: 44% (188GB / 460GB)
- **空き容量**: 249GB
- **判定**: ホスト側は十分な空き容量あり ✅

#### Docker リソース使用状況
```
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          13        0         28.83GB   8.021GB (27%)
Containers      0         0         0B        0B
Local Volumes   1         0         0B        0B
Build Cache     590       0         49.98GB   21.39GB
```

- **イメージ**: 28.83GB (うち未使用 8.02GB)
- **ビルドキャッシュ**: 49.98GB (うち削除可能 21.39GB)
- **合計使用量**: 約 78.81GB

#### Docker Desktop 仮想ディスク
```
Docker.raw  60G
```
- **最大サイズ**: 60GB
- **現在使用量**: 約 78.81GB 相当のデータを格納 ⚠️
- **判定**: **Docker Desktop の仮想ディスクが容量上限に達している** ❌

### 2.3 根本原因

1. **Docker Desktop の仮想ディスク容量制限**
   - Docker Desktop (macOS) は `Docker.raw` という仮想ディスクを使用
   - デフォルト最大サイズは 60GB 程度
   - ビルドキャッシュとイメージの累積で容量を圧迫

2. **ビルドキャッシュの肥大化**
   - 590個のキャッシュエントリで 49.98GB を消費
   - `--no-cache` でビルドしているため、既存キャッシュは使われないが削除もされていない
   - 削除可能なキャッシュ 21.39GB が放置されている

3. **未使用リソースの蓄積**
   - 未使用イメージ 8.02GB
   - ビルド失敗時の中間レイヤーが累積している可能性

---

## 3. 目的（あるべき状態）

### 3.1 短期目標

Docker ビルドを正常に完了させ、docker-entrypoint.sh の修正を検証できる状態にする。

**成功基準**:
- `pipx install csvkit` が正常に完了する
- Dockerfile の全 Step (43/43) が成功する
- DevContainer が起動し、検証作業が実施できる

### 3.2 中長期目標

Docker のディスク使用量を適切に管理し、再発を防ぐ。

**成功基準**:
- Docker 仮想ディスクの使用率が 70% 以下に維持される
- 定期的なクリーンアップが習慣化または自動化される
- ビルドキャッシュが適切に削除される

---

## 4. 戦略・アプローチ（解決の方針）

### 戦略A: 即座のクリーンアップによる容量確保 ★最優先★

**方針**: Docker の未使用リソースを削除して空き容量を確保し、ビルドを再実行する。

**理由**:
- 最も迅速に問題を解決できる
- docker-entrypoint.sh 検証という本来のタスクを阻害している状態を即座に解消
- リスクが低く、副作用が少ない

### 戦略B: Docker Desktop 設定変更による仮想ディスク拡張

**方針**: Docker Desktop の仮想ディスク最大サイズを増やす（例: 60GB → 100GB）

**理由**:
- 戦略A で一時的に解決しても、将来的に同じ問題が再発する可能性
- より大きなマージンを確保することで安定性向上
- ただし、ホストのストレージを消費するトレードオフあり

### 戦略C: Dockerfile 最適化による軽量化

**方針**: Dockerfile の層数削減、マルチステージビルド、不要パッケージの削除により、イメージサイズを削減

**理由**:
- 根本的な解決策
- ビルド時間短縮の副次効果
- ただし、設計変更を伴うため慎重な検討が必要

---

## 5. 解決策（3つの異なるアプローチ）

### 解決策1: 緊急クリーンアップ + 再ビルド ★推奨★

**概要**: Docker の未使用リソースを全削除し、即座にビルドを再実行。

#### 実施手順

##### Step 1: 未使用リソースの全削除
```bash
# ビルドキャッシュ、未使用イメージ、停止コンテナ、未使用ネットワークを一括削除
docker system prune -a --volumes -f
```

**期待効果**:
- ビルドキャッシュ 21.39GB 削除
- 未使用イメージ 8.02GB 削除
- **合計約 29.41GB の空き容量確保**

##### Step 2: 再ビルド実行
```bash
cd /Users/hagevvashi/hagevvashi.info-dev-hub
docker compose --progress plain \
  -f .devcontainer/docker-compose.yml \
  -f .devcontainer/docker-compose.dev-vm.yml \
  build --no-cache
```

##### Step 3: ビルド成功確認
- 全 43 Step が完了することを確認
- エラーログが出力されないことを確認

#### メリット
- **即効性**: 5分以内に問題解決可能
- **低リスク**: 未使用リソースのみ削除、稼働中の環境への影響なし
- **シンプル**: 1コマンドで実行可能

#### デメリット
- **一時的**: ビルドキャッシュが再蓄積すれば再発の可能性
- **再ビルド時間**: キャッシュ削除により、次回ビルドも最初からになる

#### 適用シーン
- **今すぐ docker-entrypoint.sh の検証を進めたい場合**（現在の状況に最適）
- 緊急性が高く、即座に対処が必要な場合

---

### 解決策2: Docker Desktop ディスク拡張 + クリーンアップ + 定期メンテナンス

**概要**: 仮想ディスクを拡張し、クリーンアップ後、定期メンテナンスルーチンを確立。

#### 実施手順

##### Step 1: Docker Desktop 仮想ディスクの拡張
1. Docker Desktop を開く
2. Settings (⚙️) → Resources → Advanced
3. "Disk image size" を 60GB → **100GB** に変更
4. "Apply & Restart" をクリック

##### Step 2: クリーンアップ実行
```bash
docker system prune -a --volumes -f
```

##### Step 3: 再ビルド
```bash
cd /Users/hagevvashi/hagevvashi.info-dev-hub
docker compose --progress plain \
  -f .devcontainer/docker-compose.yml \
  -f .devcontainer/docker-compose.dev-vm.yml \
  build --no-cache
```

##### Step 4: 定期クリーンアップのスケジュール化
以下のスクリプトを `scripts/docker-cleanup.sh` として作成:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker リソース使用状況（クリーンアップ前） ==="
docker system df

echo ""
echo "=== 未使用リソースを削除中... ==="
docker system prune -a --volumes -f

echo ""
echo "=== Docker リソース使用状況（クリーンアップ後） ==="
docker system df

echo ""
echo "✅ クリーンアップ完了"
```

**実行タイミング**:
- 週1回の定期実行（手動または cron）
- ビルドエラー発生時
- ディスク使用率が 70% を超えた時

#### メリット
- **安定性向上**: より大きなマージンで余裕のある運用
- **再発防止**: 定期メンテナンスで問題を予防
- **可視化**: 使用状況を定期的に把握できる

#### デメリット
- **ホストストレージ消費**: Docker.raw が最大 100GB まで拡大する可能性
- **設定変更リスク**: Docker Desktop 再起動が必要
- **運用コスト**: 定期メンテナンスの習慣化が必要

#### 適用シーン
- 長期的な安定運用を重視する場合
- 開発マシンに十分なストレージ容量がある場合（空き 249GB あり ✅）
- 頻繁にビルドを繰り返す環境

---

### 解決策3: Dockerfile 最適化による根本的軽量化

**概要**: Dockerfile を最適化し、イメージサイズとビルド時の一時ファイルを削減。

#### 実施手順

##### Step 1: pipx インストールの最適化

**現在の問題点**:
```dockerfile
RUN pipx ensurepath && \
    pipx install webssh && \
    pipx install csvkit && \
    pipx install visidata
```
- 各パッケージごとに仮想環境を作成
- `csvkit` の依存 `babel` が大量のロケールデータを含む（数百MB）

**最適化案**:
```dockerfile
# 不要なロケールデータを削除する処理を追加
RUN pipx ensurepath && \
    pipx install webssh && \
    pipx install csvkit && \
    pipx install visidata && \
    # babel のロケールデータのうち、en_US 以外を削除して容量削減
    find /home/${UNAME}/.local/pipx/venvs/csvkit/lib/python*/site-packages/babel/locale-data \
         -type f ! -name 'en_US.dat' ! -name 'root.dat' -delete
```

##### Step 2: マルチステージビルドの検討（将来的）

イメージを「ビルドステージ」と「実行ステージ」に分離し、最終イメージから不要なビルドツールを排除。

**例**:
```dockerfile
# ビルドステージ
FROM mcr.microsoft.com/devcontainers/base:bookworm AS builder
RUN apt-get update && apt-get install -y build-essential
# ... ビルド処理 ...

# 実行ステージ
FROM mcr.microsoft.com/devcontainers/base:bookworm
COPY --from=builder /usr/local/bin /usr/local/bin
# 最小限のランタイム依存のみインストール
```

##### Step 3: 不要なパッケージの削除

Dockerfile の各 `apt-get install` 後に以下を追加:
```dockerfile
RUN apt-get update && \
    apt-get install -y <packages> && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
```

#### メリット
- **根本解決**: イメージサイズを恒久的に削減
- **ビルド高速化**: レイヤー数削減により、キャッシュ効率向上
- **ポータビリティ向上**: 軽量なイメージは配布・共有しやすい

#### デメリット
- **実装コスト**: Dockerfile の大幅な書き換えが必要
- **テスト負荷**: 最適化後の動作検証が必須
- **緊急対応不可**: 今すぐの問題解決には不向き

#### 適用シーン
- docker-entrypoint.sh 検証完了後のリファクタリングフェーズ
- DevContainer の長期的なメンテナンス計画として
- イメージサイズが問題となる場合（CI/CD での転送速度など）

---

## 6. 推奨アプローチの選定

### 即座の対処: **解決策1（緊急クリーンアップ + 再ビルド）** ★最優先★

**選定理由**:

1. **緊急性**: docker-entrypoint.sh の検証が待機状態になっている
2. **効果の確実性**: 29.41GB の空き容量確保で十分にビルド可能
3. **実施の容易性**: 1コマンドで即座に実行可能
4. **リスクの低さ**: 未使用リソースのみ削除、稼働中の環境への影響なし

**実施タイミング**: 今すぐ

---

### 短期的対処（ビルド成功後）: **解決策2（Docker Desktop 拡張 + 定期メンテナンス）**

**選定理由**:

1. **再発防止**: 60GB → 100GB への拡張で余裕を確保
2. **運用改善**: 定期クリーンアップスクリプトで持続可能な管理
3. **ホスト容量**: 空き 249GB あり、100GB 割り当ても問題なし
4. **バランス**: 実装コストと効果のバランスが良い

**実施タイミング**: docker-entrypoint.sh 検証完了後、1-2日以内

---

### 中長期的対処（リファクタリングフェーズ）: **解決策3（Dockerfile 最適化）**

**選定理由**:

1. **持続可能性**: イメージサイズの根本的削減
2. **パフォーマンス**: ビルド時間短縮の副次効果
3. **ベストプラクティス**: コンテナ設計の品質向上

**実施タイミング**: v10 実装完了後のリファクタリングフェーズ（1-2週間後）

---

## 7. 実装計画（解決策1 → 解決策2 の段階的実施）

### Phase 1: 緊急対処（今すぐ実施）

#### タスク1-1: Docker クリーンアップ

```bash
docker system prune -a --volumes -f
```

**確認方法**:
```bash
docker system df
# Build Cache の SIZE が大幅に減少していることを確認
```

#### タスク1-2: DevContainer 再ビルド

```bash
cd /Users/hagevvashi/hagevvashi.info-dev-hub
docker compose --progress plain \
  -f .devcontainer/docker-compose.yml \
  -f .devcontainer/docker-compose.dev-vm.yml \
  build --no-cache \
  >> initiatives/20251229--dev-hub-concept/202601041930-docker-compose-build-retry.log 2>&1
```

**成功基準**:
- ログファイルに `ERROR` が含まれない
- 最終行が `#43 DONE` で終わる
- `pipx install csvkit` が正常完了

#### タスク1-3: 検証作業の再開

docker-entrypoint.sh の検証（[25_6_3_docker_entrypoint_fix_implementation_tracker.md](25_6_3_docker_entrypoint_fix_implementation_tracker.md) セクションD）に戻る。

---

### Phase 2: 短期対処（検証完了後、1-2日以内）

#### タスク2-1: Docker Desktop ディスク拡張

1. Docker Desktop → Settings → Resources → Advanced
2. "Disk image size" を **100GB** に変更
3. "Apply & Restart"

**確認方法**:
```bash
ls -lh ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
# サイズが 100GB まで拡張可能になっていることを確認（実際のサイズは使用量に応じて増加）
```

#### タスク2-2: クリーンアップスクリプトの作成

```bash
mkdir -p scripts
cat > scripts/docker-cleanup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker リソース使用状況（クリーンアップ前） ==="
docker system df

echo ""
echo "=== 未使用リソースを削除中... ==="
docker system prune -a --volumes -f

echo ""
echo "=== Docker リソース使用状況（クリーンアップ後） ==="
docker system df

echo ""
echo "✅ クリーンアップ完了"
EOF

chmod +x scripts/docker-cleanup.sh
```

#### タスク2-3: 初回クリーンアップ実行

```bash
./scripts/docker-cleanup.sh
```

#### タスク2-4: README への運用手順追加

以下を README.md または運用ドキュメントに追加:

```markdown
## Docker メンテナンス

### 定期クリーンアップ（週1回推奨）

```bash
./scripts/docker-cleanup.sh
```

### ディスク使用状況の確認

```bash
docker system df
```

使用率が 70% を超えている場合は、クリーンアップを実行してください。
```

---

### Phase 3: 中長期対処（リファクタリングフェーズ）

#### タスク3-1: Dockerfile の pipx セクション最適化

現在の 240行目を以下に変更:

```dockerfile
RUN pipx ensurepath && \
    pipx install webssh && \
    pipx install csvkit && \
    pipx install visidata && \
    # babel ロケールデータの削減
    find /home/${UNAME}/.local/pipx/venvs/csvkit/lib/python*/site-packages/babel/locale-data \
         -type f ! -name 'en_US.dat' ! -name 'root.dat' -delete || true
```

#### タスク3-2: 全体的なレイヤー最適化の検討

- 複数の `RUN` を `&&` で結合
- 一時ファイルの削除を各ステップに追加
- マルチステージビルドの検討

**実施は慎重に**: v10 実装が完全に安定してから着手

---

## 8. 成功基準

### Phase 1（緊急対処）の成功基準

| 基準 | 確認方法 | 期待結果 |
|------|---------|---------|
| クリーンアップ完了 | `docker system df` | Build Cache が 30GB 以下 |
| ビルド成功 | ログファイル確認 | `ERROR` が含まれない |
| pipx インストール成功 | ログファイル確認 | `csvkit` と `visidata` が正常インストール |
| DevContainer 起動 | VS Code で接続 | コンテナが正常に起動し、接続可能 |

### Phase 2（短期対処）の成功基準

| 基準 | 確認方法 | 期待結果 |
|------|---------|---------|
| ディスク拡張完了 | Docker Desktop 設定確認 | Disk image size が 100GB |
| クリーンアップスクリプト作成 | `./scripts/docker-cleanup.sh` 実行 | 正常に動作し、結果が表示される |
| 運用ドキュメント更新 | README.md 確認 | メンテナンス手順が記載されている |

### Phase 3（中長期対処）の成功基準

| 基準 | 確認方法 | 期待結果 |
|------|---------|---------|
| Dockerfile 最適化完了 | ビルド成功確認 | 最適化後もビルドが正常完了 |
| イメージサイズ削減 | `docker images` | 最適化前より 10% 以上削減 |
| 機能性維持 | DevContainer 内で csvkit 実行 | `csvkit` が正常に動作 |

---

## 9. リスク管理

### リスク1: クリーンアップによる意図しないデータ削除

**影響度**: 中
**発生確率**: 低

**緩和策**:
- `docker system prune -a` は未使用リソースのみ削除（稼働中のコンテナ・イメージは削除されない）
- 重要なイメージには明示的にタグを付けておく
- クリーンアップ前に `docker images` でイメージリストを保存

**ロールバック**:
- 削除されたイメージは再ビルドまたは pull で復元可能

---

### リスク2: Docker Desktop ディスク拡張によるホストストレージ圧迫

**影響度**: 中
**発生確率**: 低

**緩和策**:
- 現在の空き容量 249GB で、100GB 割り当ても問題なし
- ディスク拡張後も定期クリーンアップで使用量を管理
- ホストの空き容量が 100GB を下回った場合は拡張サイズを見直し

**ロールバック**:
- Docker Desktop 設定でディスクサイズを縮小可能（ただし、データ削除が必要）

---

### リスク3: Dockerfile 最適化による機能劣化

**影響度**: 高
**発生確率**: 中

**緩和策**:
- Phase 3 は v10 実装安定後に実施
- 最適化前に現在の Dockerfile をバックアップ
- 変更後、全機能の動作確認を実施（csvkit, visidata の動作テスト）
- ロケールデータ削除は慎重に（英語以外が必要な場合は削除対象を調整）

**ロールバック**:
```bash
git checkout <commit-hash> -- .devcontainer/Dockerfile
docker compose build
```

---

## 10. 次のアクション

### 今すぐ実施（Phase 1）

- [ ] **タスク1-1**: Docker クリーンアップ実行
  ```bash
  docker system prune -a --volumes -f
  ```
- [ ] **タスク1-2**: DevContainer 再ビルド
  ```bash
  cd /Users/hagevvashi/hagevvashi.info-dev-hub
  docker compose --progress plain \
    -f .devcontainer/docker-compose.yml \
    -f .devcontainer/docker-compose.dev-vm.yml \
    build --no-cache \
    >> initiatives/20251229--dev-hub-concept/202601041930-docker-compose-build-retry.log 2>&1
  ```
- [ ] **タスク1-3**: ビルドログ確認
  ```bash
  tail -50 initiatives/20251229--dev-hub-concept/202601041930-docker-compose-build-retry.log
  grep -i error initiatives/20251229--dev-hub-concept/202601041930-docker-compose-build-retry.log
  ```
- [ ] **タスク1-4**: [25_6_3_docker_entrypoint_fix_implementation_tracker.md](25_6_3_docker_entrypoint_fix_implementation_tracker.md) セクションD の検証作業に戻る

### 検証完了後（Phase 2）

- [ ] Docker Desktop ディスク拡張（60GB → 100GB）
- [ ] `scripts/docker-cleanup.sh` 作成
- [ ] 運用ドキュメント更新

### リファクタリングフェーズ（Phase 3）

- [ ] Dockerfile の pipx セクション最適化
- [ ] イメージサイズ削減の検証
- [ ] 全機能の動作確認

---

## 11. 参考資料

- [Docker ディスク使用量管理公式ドキュメント](https://docs.docker.com/config/pruning/)
- [Docker Desktop for Mac リソース設定](https://docs.docker.com/desktop/settings/mac/#resources)
- [Dockerfile ベストプラクティス](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [25_6_3_docker_entrypoint_fix_implementation_tracker.md](25_6_3_docker_entrypoint_fix_implementation_tracker.md) - 元の検証タスク

---

## 付録: エラーログ抜粋

```
#46 [40/43] RUN pipx ensurepath &&     pipx install webssh &&     pipx install csvkit &&     pipx install visidata
#46 6.745 creating virtual environment...
#46 6.782 installing csvkit...
#46 9.274 Fatal error from pip prevented installation. Full pip output in file:
#46 9.274     /home/hagevvashi/.local/pipx/logs/cmd_2026-01-04_19.18.00_pip_errors.log
#46 9.274
#46 9.274 pip seemed to fail to build package:
#46 9.274     typing-extensions>=4.6.0
#46 9.274
#46 9.274 Some possibly relevant errors from pip install:
#46 9.274     ERROR: Could not install packages due to an OSError: [Errno 28] No space left on device: '/home/hagevvashi/.local/pipx/venvs/csvkit/lib/python3.11/site-packages/babel/locale-data/en_BM.dat'
#46 9.280 Error installing csvkit.
```

---

**このドキュメントは、Docker ビルド失敗の原因分析と、段階的な解決策を提示するものです。即座の対処（Phase 1）により、docker-entrypoint.sh の検証を再開できます。**
