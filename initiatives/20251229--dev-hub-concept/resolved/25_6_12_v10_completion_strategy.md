# v10設計完成戦略: s6-overlay統合の最終1%実装

**作成日**: 2026-01-09
**目的**: v10設計（s6-overlayをPID 1として使用）の残り1%の実装を完了し、Monolithic DevContainerのプロセス管理を完成させる

**基準ドキュメント**:
- `25_0_process_management_solution.v10.md` - v10設計の詳細
- `25_6_11_pid1_design_deviation_analysis.md` - 問題の分析
- `25_6_11_pid1_design_deviation_verification_tracker.md` - 検証結果

---

## 0. 目標（達成すべき状態）

### 0.1 技術的目標

**v10設計の完全実装**:
```
┌─────────────────────────────────────────────┐
│           s6-overlay (PID 1)                │
│                 /init                       │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ docker-entrypoint (oneshot)         │   │
│  │ - Phase 1-5の初期化処理             │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ supervisord (longrun)               │   │
│  │ - code-server 管理                  │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ process-compose (longrun)           │   │
│  │ - TUI プロセス管理                  │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 0.2 成功基準

| 項目 | 成功基準 | 確認方法 |
|------|---------|----------|
| **PID 1** | s6-overlay（/init）がPID 1として動作 | `docker exec <container> ps aux \| grep "^root.*1"` |
| **docker-entrypoint実行** | Phase 1-5が正常に実行される | `docker logs <container>` で確認 |
| **supervisord起動** | s6-overlayのlongrunサービスとして起動 | `/command/s6-svstat /run/service/supervisord` |
| **process-compose起動** | s6-overlayのlongrunサービスとして起動 | `/command/s6-svstat /run/service/process-compose` |
| **code-server動作** | ポート4035で正常動作 | `curl http://localhost:4035` |
| **graceful shutdown** | SIGTERM受信時に全プロセスが正常終了 | `docker stop <container>` でログ確認 |

---

## 1. 課題（目標とのギャップ）

### 1.1 現在の状態

**検証結果（25_6_11_pid1_design_deviation_verification_tracker.md セクションB-4）より**:

- ✅ s6-overlayインストール済み（Dockerfile line 93-107）
- ✅ s6-overlayサービス定義完璧（`.devcontainer/s6-rc.d/`）
- ❌ DockerfileのENTRYPOINTが`/usr/local/bin/docker-entrypoint.sh`のまま（line 299）
- ❌ docker-entrypoint.shの最後で`exec sudo supervisord`を実行（line 228-229）

### 1.2 ギャップ

**残り1%の実装**:
1. Dockerfile line 299のENTRYPOINT変更
2. docker-entrypoint.sh line 228-229の削除
3. docker-entrypoint.sh内のsudo削除（s6-overlayのoneshotサービスとして実行されるため）

---

## 2. 原因

### 2.1 直接的原因

**仮説2（ENTRYPOINTの切り替えを忘れた）が正しい**（検証済み）:

- v10実装トラッカーには「Phase 1完了」と記録
- しかし実際にはENTRYPOINTが変更されていない
- サービス定義は完璧に実装されている

### 2.2 根本原因

**トラッカー更新と実装の乖離**:
- Phase 1のタスクを完了としてマークしたが、実装が伴っていなかった
- または、実装後にDockerfileを別の理由で修正し、ENTRYPOINTが元に戻った

---

## 3. 目的（あるべき状態）

### 3.1 短期目的

**v10設計の完全実装**:
- s6-overlayがPID 1として動作
- docker-entrypoint.shがoneshotサービスとして実行
- supervisordとprocess-composeがlongrunサービスとして動作

### 3.2 中期目的

**堅牢なプロセス管理の実現**:
- PID 1保護（ゾンビプロセスの回収）
- graceful shutdown
- プロセス監視・自動再起動

### 3.3 長期目的

**Monolithic DevContainerの完成**:
- v10設計の全Phase完了
- 本番環境レベルの堅牢性

---

## 4. 戦略・アプローチ（解決の方針）

### 戦略A: 最小限の変更で実装（推奨）

**方針**: Dockerfile 1行とdocker-entrypoint.sh 2行のみを修正し、s6-overlay統合を完成させる

**理由**:
- サービス定義は既に完璧に実装済み
- 変更箇所が明確で、リスクが低い
- すぐに検証可能

### 戦略B: docker-entrypoint.shのリファクタリングも実施

**方針**: ENTRYPOINT変更に加え、docker-entrypoint.sh全体をリファクタリング（sudo削除、Phase 6削除等）

**理由**:
- より設計に忠実
- 将来的なメンテナンス性向上

**デメリット**:
- 変更範囲が広がる
- テスト負荷増加

### 戦略C: 段階的実装（Phase 6削除は後回し）

**方針**: まずENTRYPOINT変更のみ実施し、docker-entrypoint.shの修正は後回し

**理由**:
- リスクを最小化
- 段階的検証が可能

**デメリット**:
- docker-entrypoint.shの最後で`exec sudo supervisord`が残る
- s6-overlayのサービス定義と重複する可能性

---

## 5. 解決策（3つの異なるアプローチ）

### 解決策1: 最小限変更・即時完成（戦略A） ★推奨★

**概要**: Dockerfile 1行とdocker-entrypoint.sh 2行のみを修正

#### 実施内容

##### 変更1: Dockerfile line 299

```dockerfile
# 修正前
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 修正後
ENTRYPOINT ["/init"]
```

##### 変更2: docker-entrypoint.sh line 228-229を削除

```bash
# 修正前（line 220-229）
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Starting supervisord..."
echo ""

# supervisordをフォアグラウンドで起動（PID 1として実行）
exec sudo supervisord -c "${TARGET_CONF}" -n

# 修正後（line 220-227）
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ docker-entrypoint.sh finished. s6-overlay will now start services."
echo ""

# Phase 6削除: s6-overlayがsupervisordとprocess-composeを起動する
```

##### 変更3: Dockerfileのコメント修正（line 300-302）

```dockerfile
# 修正前
# s6-overlay を PID 1 として起動
# s6-overlay が docker-entrypoint, supervisord, process-compose を管理

# 修正後
# s6-overlay を PID 1 として起動（/init）
# s6-overlay が以下のサービスを管理:
#   - docker-entrypoint (oneshot): Phase 1-5の初期化処理
#   - supervisord (longrun): code-server等のプロセス管理
#   - process-compose (longrun): TUIプロセス管理
```

#### メリット

- ✅ **最小限の変更**: 3箇所のみの修正
- ✅ **即座に完成**: v10設計が完全実装される
- ✅ **リスク低**: 既存のサービス定義を活用
- ✅ **テスト容易**: 変更箇所が明確

#### デメリット

- ⚠️ docker-entrypoint.sh内にsudoが残る（s6-overlayのoneshotサービスとして実行されるため不要だが、動作には影響しない）

#### 適用シーン

- **今すぐv10設計を完成させたい場合**（現在の状況に最適）

---

### 解決策2: docker-entrypoint.shリファクタリング込み（戦略B）

**概要**: ENTRYPOINT変更に加え、docker-entrypoint.sh全体をリファクタリング

#### 実施内容

解決策1に加えて:

##### 追加変更: docker-entrypoint.sh内のsudo削除

```bash
# 修正前（Phase 1）
chown -R ${UNAME}:${GNAME} "$item"

# 修正後
sudo chown -R ${UNAME}:${GNAME} "$item"

# 理由: s6-overlayのoneshotサービスとして実行される場合、
# rootユーザーで実行されるためsudoは不要...
# ただし、wait! サービス定義を確認すると...
```

**重要な発見**: `.devcontainer/s6-rc.d/docker-entrypoint/up`を確認すると:

```bash
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh
```

**ユーザー指定がない** = デフォルトでrootとして実行される可能性が高い

**結論**: sudoは不要の可能性が高いが、25_6_10で提案された「ENTRYPOINTをUSER後に移動」との関係を整理する必要がある。

#### メリット

- ✅ **設計に忠実**: sudo不要な箇所を削除
- ✅ **将来的なメンテナンス性**: コードがクリーンになる

#### デメリット

- ⚠️ **変更範囲拡大**: テスト負荷増加
- ⚠️ **25_6_10との整合性**: ユーザー切り替え問題との関係を整理する必要

#### 適用シーン

- sudo削除も同時に実施したい場合
- 25_6_10の問題も同時に解決したい場合

---

### 解決策3: 段階的実装（戦略C）

**概要**: まずENTRYPOINT変更のみ実施し、docker-entrypoint.shは後回し

#### 実施内容

Dockerfile line 299のみを修正:

```dockerfile
# 修正前
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 修正後
ENTRYPOINT ["/init"]
```

docker-entrypoint.shは**変更しない**。

#### 動作予測

1. `/init` (s6-overlay) がPID 1として起動
2. s6-overlayが`docker-entrypoint`をoneshotサービスとして実行
3. docker-entrypoint.sh Phase 1-5を実行
4. docker-entrypoint.sh Phase 6で`exec sudo supervisord`を実行
5. **問題**: `exec`によりプロセスが置き換えられ、s6-overlayの制御から外れる可能性

#### 結論

**この解決策は機能しない可能性が高い**（`exec`の挙動により）

---

## 6. 推奨アプローチの選定

### 推奨: **解決策1（最小限変更・即時完成）**

**選定理由**:

1. **即効性**: 3箇所の修正でv10設計完成
2. **安全性**: 既存のサービス定義を活用、変更範囲が明確
3. **検証容易性**: すぐにテスト可能
4. **25_6_10との分離**: ユーザー切り替え問題は別途対応

**実施タイミング**: 今すぐ

---

## 7. 実装計画（解決策1の詳細手順）

### Phase 1: コード修正

#### タスク1-1: Dockerfile修正

**ファイル**: `.devcontainer/Dockerfile`

**変更箇所1**: line 299

```dockerfile
# 修正前
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 修正後
ENTRYPOINT ["/init"]
```

**変更箇所2**: line 300-302（コメント追加）

```dockerfile
# 修正前
# s6-overlay を PID 1 として起動
# s6-overlay が docker-entrypoint, supervisord, process-compose を管理

# 修正後
# s6-overlay を PID 1 として起動（/init）
# v10設計: s6-overlay が以下のサービスを管理
#   - docker-entrypoint (oneshot): 初期化処理（Phase 1-5）
#   - supervisord (longrun): code-server等のプロセス管理
#   - process-compose (longrun): TUIプロセス管理
```

#### タスク1-2: docker-entrypoint.sh修正

**ファイル**: `.devcontainer/docker-entrypoint.sh`

**変更箇所**: line 220-229

```bash
# 修正前
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Starting supervisord..."
echo ""

# supervisordをフォアグラウンドで起動（PID 1として実行）
exec sudo supervisord -c "${TARGET_CONF}" -n

# 修正後
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Container initialization complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ docker-entrypoint.sh finished."
echo "   s6-overlay will now start supervisord and process-compose as longrun services."
echo ""

# Phase 6削除: s6-overlayがsupervisordとprocess-composeを起動する
```

### Phase 2: ビルドと検証

#### タスク2-1: DevContainerビルド

```bash
cd /Users/<一般ユーザー>/repos/hagevvashi.info-dev-hub/.devcontainer

# ビルド（キャッシュなし）
docker compose --progress plain -f docker-compose.yml -f docker-compose.dev-vm.yml build --no-cache
```

**期待結果**: エラーなくビルド完了

#### タスク2-2: コンテナ起動

```bash
# 既存コンテナ削除
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml down

# 起動
docker compose --project-name hagevvashiinfo-dev-hub_devcontainer \
  -f docker-compose.yml -f docker-compose.dev-vm.yml up -d
```

**期待結果**: エラーなく起動

#### タスク2-3: PID 1確認

```bash
docker exec hagevvashiinfo-dev-hub_devcontainer-dev-1 ps aux | head -n 10
```

**期待結果**:
```
USER       PID  COMMAND
root         1  s6-svscan /run/service
```

#### タスク2-4: サービス状態確認

```bash
docker exec hagevvashiinfo-dev-hub_devcontainer-dev-1 /command/s6-rc -a list
```

**期待結果**: `docker-entrypoint`, `supervisord`, `process-compose` が表示される

```bash
docker exec hagevvashiinfo-dev-hub_devcontainer-dev-1 /command/s6-svstat /run/service/supervisord
docker exec hagevvashiinfo-dev-hub_devcontainer-dev-1 /command/s6-svstat /run/service/process-compose
```

**期待結果**: 両方とも`up`状態

#### タスク2-5: docker-entrypoint.sh実行確認

```bash
docker logs hagevvashiinfo-dev-hub_devcontainer-dev-1 2>&1 | grep "Phase"
```

**期待結果**: Phase 1-5の実行ログが表示される

#### タスク2-6: code-server動作確認

```bash
curl -I http://localhost:4035
```

**期待結果**: HTTP 200またはリダイレクト

#### タスク2-7: graceful shutdown確認

```bash
docker stop hagevvashiinfo-dev-hub_devcontainer-dev-1
docker logs hagevvashiinfo-dev-hub_devcontainer-dev-1 2>&1 | tail -n 20
```

**期待結果**: s6-overlayによる正常なシャットダウンログ

### Phase 3: ドキュメント更新

#### タスク3-1: v10実装トラッカー更新

**ファイル**: `25_4_2_v10_implementation_tracker.md`

Phase 1のステータスを更新:

```markdown
### Phase 1: s6-overlay導入（PID 1変更）
- [x] Dockerfileにs6-overlayをインストールし、ENTRYPOINTを`/init`に変更
- [x] `.devcontainer/s6-rc.d/` にサービス定義を作成

**更新日**: 2026-01-09
**更新内容**: ENTRYPOINTを`/init`に変更完了（25_6_12実装完了）
```

#### タスク3-2: 25_6_11検証トラッカー更新

**ファイル**: `25_6_11_pid1_design_deviation_verification_tracker.md`

セクションC-1, C-2を完了としてマーク

#### タスク3-3: 変更履歴の記録

25_6_12ドキュメントに「## 8. 実装完了」セクションを追加

### Phase 4: コミット

#### タスク4-1: git add

```bash
git add .devcontainer/Dockerfile
git add .devcontainer/docker-entrypoint.sh
git add initiatives/20251229--dev-hub-concept/25_6_12_v10_completion_strategy.md
git add initiatives/20251229--dev-hub-concept/25_4_2_v10_implementation_tracker.md
git add initiatives/20251229--dev-hub-concept/25_6_11_pid1_design_deviation_verification_tracker.md
```

#### タスク4-2: コミットメッセージ作成

**commit-messages-guidelines.mdcに従い、3つの候補を作成**（mode-3で実施）

---

## 8. リスク管理

### リスク1: s6-overlayのサービス起動失敗

**影響度**: 高
**発生確率**: 低

**緩和策**:
- サービス定義は既に完璧に実装済み（検証済み）
- ビルド時にエラーが発生すれば即座に検出可能

**ロールバック**:
```bash
git revert HEAD
docker compose -f docker-compose.yml -f docker-compose.dev-vm.yml build
```

### リスク2: docker-entrypoint.sh Phase 1-5の実行失敗

**影響度**: 中
**発生確率**: 低

**緩和策**:
- Phase 1-5は既存のロジックをそのまま使用
- s6-overlayのoneshotサービスとして実行されるだけ

**対処**:
- `docker logs`でエラー箇所を特定
- 必要に応じてサービス定義を修正

### リスク3: supervisordまたはprocess-composeの起動失敗

**影響度**: 中
**発生確率**: 低

**緩和策**:
- サービス定義ファイル（`.devcontainer/s6-rc.d/supervisord/run`）は既に実装済み
- `/command/s6-svstat`で状態確認可能

**対処**:
- s6-overlayのログを確認: `docker exec <container> cat /run/s6-rc/servicedirs/supervisord/log/current`
- 必要に応じてサービス定義を修正

---

## 9. 次のアクション

### 今すぐ実施（Phase 1-4）

1. **Dockerfile修正**（タスク1-1）
2. **docker-entrypoint.sh修正**（タスク1-2）
3. **ビルドと検証**（タスク2-1〜2-7）
4. **ドキュメント更新とコミット**（タスク3-1〜4-2）

### 検証完了後（将来）

- **25_6_10ユーザー切り替え問題の対応**（別途）
- **docker-entrypoint.sh内のsudo削除検討**（必要に応じて）

---

**このドキュメントは、v10設計の残り1%を完成させ、s6-overlay統合を完了するための戦略と実装計画を示すものです。**
