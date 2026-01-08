# 現状況サマリー: docker-entrypoint問題解決の全体像

**作成日**: 2026-01-04
**目的**: 一連の調査・分析の全体像を整理し、次のアクションを明確化

---

## 1. 問題の発見から現在までの経緯

### タイムライン

| 日時 | イベント | ドキュメント |
|------|---------|-------------|
| 2026-01-04 (初期) | supervisord.confがseed.confを指していることを発見 | 25_6_1 v2 セクション11 |
| 2026-01-04 (中期) | 「docker-entrypoint.shが実行されていない」仮説を立てる | 25_6_1 v2 セクション11.2 |
| 2026-01-04 (中期) | デバッグログ追加のため`exec`リダイレクトを試行 | 25_6_1 v2 セクション11.4 |
| 2026-01-04 (中期) | `exec`リダイレクトでログが途中で終了 | 25_6_6 セクション2 |
| 2026-01-04 (後期) | `exec`リダイレクト削除で全Phase実行を確認 | 25_6_6 セクション14 |
| 2026-01-04 (後期) | Phase 4 supervisord検証でsudo欠如を発見 | 25_6_6 セクション14.3 |
| 2026-01-04 (後期) | `sudo supervisord -t` 修正を実施 | git commit 8ed7b96 |
| 2026-01-04 (現在) | **重大発見**: docker-entrypoint.sh はrootで実行されており、sudo は不要だった | 25_6_7 |

### 仮説の変遷

| 仮説バージョン | 内容 | 結論 |
|-------------|------|------|
| v1 | docker-entrypoint.sh が実行されていない | ❌ 誤り（全Phase実行されていた） |
| v2 | execリダイレクトが途中終了の原因 | ❌ 赤いニシン（真の原因ではなかった） |
| v3 | supervisord -t にsudoが欠けている | ⚠️ 部分的に誤り（rootで実行されているのでsudo不要） |
| v4（現在） | **rootで実行されているのに不要なsudoを使っている** | ✅ **根本原因を特定** |

---

## 2. 現在の状況

### 2.1 作業ブランチの状態

**ブランチ**: `fix/docker-entrypoint-service-definition`

**変更済みファイル**:
- `.devcontainer/Dockerfile` - s6-overlayの位置変更、重複削除
- `.devcontainer/docker-entrypoint.sh` - sudo削除済み（ローカル変更、未コミット）
- `.devcontainer/docker-compose.yml` - （詳細不明）
- `.devcontainer/s6-rc.d/process-compose/run` - フラグ修正済み（コミット済み）
- `workloads/supervisord/project.conf` - docker-entrypointプログラム定義削除済み（コミット済み）

**未追跡ファイル**:
- `.devcontainer/s6-entrypoint.sh` - s6-rc コンパイル用スクリプト（用途不明）
- `.devcontainer/s6-rc.d/process-compose/dependencies.d/` - 依存関係定義（新規）
- `.devcontainer/s6-rc.d/supervisord/dependencies.d/` - 依存関係定義（新規）
- `.devcontainer/supervisord/supervisord.conf` - supervisord設定（新規）

### 2.2 最新コミット

```
8ed7b96 fix: remove exec redirect and add sudo for supervisord validation
87bf66b fix: attempt stderr-only redirect and document failure
603642d docs: add analysis for docker-entrypoint execution failure
d837a24 docs: add debug logging and track supervisord fallback investigation
62728f4 fix: resolve multiple devcontainer build blockers
```

### 2.3 ドキュメント状況

| ドキュメント | 状態 | 最新の内容 |
|------------|------|-----------|
| 25_6_1 v2 | 更新済み | セクション11追跡調査を含む |
| 25_6_2 Geminiレビュー | 完成 | 変更不要 |
| 25_6_3 トラッカー | 古い | E-2統合検証が未実施のまま |
| 25_6_4 ディスク容量 | 完成 | 変更不要 |
| 25_6_5 s6登録 | 完成 | 変更不要 |
| 25_6_6 実行失敗分析 | 更新済み | セクション14, 15, 16, 17を含む |
| 25_6_7 sudo問題 | **新規作成** | Phase 1実施準備完了 |
| 25_6_8 現状サマリー | **新規作成中** | このドキュメント |

---

## 3. 重要な発見: sudo不要問題

### 3.1 問題の本質

**docker-entrypoint.sh は root として実行されているにも関わらず、スクリプト内で sudo を大量に使用している**

証拠:
```dockerfile
# .devcontainer/Dockerfile (215-235行目)

# ユーザー作成
RUN useradd -o -l -u ${UID} -g ${GNAME} -G docker -m ${UNAME}
RUN echo "${UNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ENTRYPOINTを設定（この時点でUSER変更していない = root）
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# この後もUSERディレクティブは存在しない
```

**結論**: docker-entrypoint.sh は root で実行されるため、すべての sudo は不要

### 3.2 影響範囲

docker-entrypoint.sh の以下の箇所でsudoが使用されている:

| Phase | 行番号 | コマンド | 不要な理由 |
|-------|--------|---------|-----------|
| Phase 1 | 36 | `sudo chown -R` | rootは直接chownを実行できる |
| Phase 2 | 55 | `sudo chmod 666` | rootは直接chmodを実行できる |
| Phase 2 | 59 | `sudo usermod` | rootは直接usermodを実行できる |
| Phase 4 | 133 | `sudo ln -sf` | rootは直接lnを実行できる |
| Phase 4 | 135 | `sudo supervisord -t` | rootは直接supervisordを実行できる |
| Phase 4 | 153 | `sudo ln -sf` | rootは直接lnを実行できる |
| Phase 4 | 171 | `sudo ln -sf` | rootは直接lnを実行できる |
| Phase 5 | 193, 195 | `sudo mkdir -p`, `sudo ln -sf` | rootは直接実行できる |
| Phase 5 | 214, 222 | `sudo ln -sf` | rootは直接実行できる |

**合計**: 11箇所で不要なsudoを使用

### 3.3 25_6_6 の誤認

25_6_6 セクション14.3では以下のように記載されていた:

> docker-entrypoint.sh は非 root ユーザー（hagevvashi）として実行されるため、supervisord の検証が失敗し、フォールバックが発生していた。

**これは誤り**: 実際にはrootとして実行されている

この誤認により、`sudo supervisord -t` という修正が提案されたが、実際には sudo は不要だった。

---

## 4. 解決すべき問題の整理

### 4.1 主要問題: supervisord検証失敗

**症状**:
- `/etc/supervisor/supervisord.conf` が `seed.conf` を指している
- 正しくは `workloads/supervisord/project.conf` を指すべき
- `supervisorctl status` が失敗する

**原因の候補**:
1. ~~sudo の欠如~~ → 誤り（rootで実行されているため関係ない）
2. supervisord -t の実行環境の問題
3. project.conf の内容に問題がある可能性
4. その他の要因

**次のアクション**:
- 25_6_7 Phase 1（sudo削除）を実施
- 再ビルド後、supervisord -t が成功するか検証
- 失敗する場合、project.conf の内容を詳細に調査

### 4.2 副次的問題: 設計の不明瞭性

**症状**:
- docker-entrypoint.sh の実行ユーザーが不明確
- sudo の使用が一貫性を欠いている
- セキュリティベストプラクティスに反している

**解決策**:
- 短期: 25_6_7 解決策1（sudo削除）で設計意図を明確化
- 中長期: 25_6_7 解決策2（USER追加）でセキュリティ改善

---

## 5. 次のアクション（優先順位順）

### 🔴 最優先: sudo削除と検証（今すぐ）

1. ✅ **25_6_7 作成完了**
2. ✅ **25_6_8 作成完了**（このドキュメント）
3. ⏭️ **docker-entrypoint.sh からsudo削除** - ローカルで実施済み、レビュー必要
4. ⏭️ **25_6_6 セクション14.3訂正** - 誤認を明記
5. ⏭️ **変更をコミット&プッシュ**
6. ⏭️ **DevContainer 再ビルド**
7. ⏭️ **supervisord検証結果を記録**

### 🟡 重要: 統合検証の完了

8. ⏭️ **25_6_3 トラッカー更新** - セクションE-2の検証項目を実施
9. ⏭️ **25_4_2 v10トラッカー更新** - Phase 1完了基準を更新

### 🟢 推奨: セキュリティ改善（リファクタリング時）

10. ⏭️ **USER ディレクティブ追加の検討**（25_6_7 解決策2）
11. ⏭️ **セキュリティ監査**

---

## 6. 未解決の疑問点

### 6.1 新規ファイルの用途

以下のファイルがgit未追跡で存在している:

1. **`.devcontainer/s6-entrypoint.sh`**:
   - s6-rc-compile を実行するスクリプト
   - sudo を使用している（これも root実行なら不要の可能性）
   - ENTRYPOINTとして使用される予定か？

2. **`.devcontainer/s6-rc.d/process-compose/dependencies.d/`**:
   - process-composeサービスの依存関係定義
   - 中身は何が定義されているか？

3. **`.devcontainer/s6-rc.d/supervisord/dependencies.d/`**:
   - supervisordサービスの依存関係定義
   - 中身は何が定義されているか？

4. **`.devcontainer/supervisord/supervisord.conf`**:
   - 新しいsupervisord設定ファイル
   - seed.conf や project.conf との関係は？

**対応**:
- これらのファイルの用途を確認し、必要ならコミット、不要なら削除

### 6.2 Dockerfileの重複

Dockerfileの末尾（280-297行目）にs6-overlayのインストールが再度記載されている:

```dockerfile
# 280行目以降
# s6-overlay: PID 1 保護・プロセス監視
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
...
```

これは6-27行目のインストールと重複している。

**対応**:
- Dockerfileの構造を整理し、重複を削除

---

## 7. 作業の全体像（フローチャート）

```
[25_6_1 v2]
   ↓ 問題発見: supervisord.conf が seed.conf を指している
[デバッグログ追加試行]
   ↓ exec リダイレクト → 失敗（途中終了）
[25_6_6]
   ↓ exec削除 → docker-entrypoint.sh が全Phase実行されていることを確認
   ↓ Phase 4 失敗の原因: sudo の欠如（と誤認）
[git commit 8ed7b96]
   ↓ sudo supervisord -t を追加
[25_6_7] ★現在地★
   ↓ 重大発見: rootで実行されているのでsudo不要
   ↓ 解決策1: sudoをすべて削除
[次のアクション]
   ↓ 1. sudo削除をコミット
   ↓ 2. 再ビルド
   ↓ 3. supervisord検証が成功するか確認
   ├─ 成功 → [25_6_3 E-2統合検証] → 完了
   └─ 失敗 → project.conf の詳細調査 → [新規分析ドキュメント]
```

---

## 8. 成功基準（最終ゴール）

| 項目 | 成功基準 | 確認方法 |
|------|---------|---------|
| supervisord設定 | `/etc/supervisor/supervisord.conf` が `workloads/supervisord/project.conf` を指す | `ls -l /etc/supervisor/supervisord.conf` |
| supervisorctl動作 | `supervisorctl status` がエラーなく実行される | コンテナ内で `supervisorctl status` |
| process-compose設定 | `/etc/process-compose/process-compose.yaml` が `workloads/process-compose/project.yaml` を指す | `ls -l /etc/process-compose/process-compose.yaml` |
| s6サービス登録 | `docker-entrypoint`, `supervisord`, `process-compose` が認識される | `/command/s6-rc -d list` |
| 設計の明確性 | docker-entrypoint.sh の実行ユーザーがコメントで明示されている | Dockerfile確認 |
| sudo の適切性 | 不要なsudoが削除されている | `grep sudo .devcontainer/docker-entrypoint.sh` が0件 |
| **ユーザー切り替え** | **ログイン時のデフォルトユーザーがhagevvashi** | **`docker exec -it devcontainer-dev-1 whoami`** |
| **Atuinエラー解消** | **bashプロンプトでAtuinエラーが表示されない** | **コンテナ内でbash起動** |

---

## 9. リスクと緩和策

### リスク1: sudo削除後もsupervisord検証が失敗

**影響度**: 高
**発生確率**: 中

**緩和策**:
- project.confの内容を詳細に調査
- supervisord -t のエラーメッセージを記録
- 最悪の場合、seed.confへのフォールバックを受け入れる設計変更を検討

### リスク2: 未追跡ファイルが作業中に誤って削除される

**影響度**: 中
**発生確率**: 低

**緩和策**:
- git status で未追跡ファイルを常に確認
- 用途不明ファイルは削除前にバックアップ

---

## 10. まとめ

### 現在の状況

- ✅ 問題の根本原因を特定（sudo不要問題）
- ✅ 解決策を明確化（25_6_7 解決策1）
- ⏭️ docker-entrypoint.sh のsudo削除（ローカル実施済み、コミット待ち）
- ⏭️ 再ビルドと検証待ち

### 次のステップ

1. ユーザーに現状を報告し、25_6_7 Phase 1の実施を確認
2. sudo削除をコミット&プッシュ
3. DevContainer再ビルド
4. 検証結果を記録

### 期待される成果

- supervisord検証が成功し、project.confが読み込まれる
- supervisorctl が正常に動作する
- 設計の明確性が向上する
- 一連の問題が解決し、25_6_3 E-2統合検証が完了する

---

**このドキュメントは、複雑化した調査・分析の全体像を整理し、次のアクションを明確にするためのサマリーです。**
