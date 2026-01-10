# sudo権限エスカレーション問題の分析と解決策

**作成日**: 2026-01-04
**発見経緯**: docker-entrypoint.sh のsudo利用見直し
**影響範囲**: docker-entrypoint.sh 全体、Dockerfile ENTRYPOINT設定

---

## 1. 課題（目標とのギャップ）

### 1.1 発見された問題

**25_6_6セクション14.4で提案された `sudo supervisord` 修正の実装中に、より深刻な構造的問題が判明**

現在のdocker-entrypoint.shは、以下のように大量のsudoを使用:
- Phase 1: `sudo chown -R` で設定ファイルの所有権変更
- Phase 2: `sudo chmod 666` でDocker socket権限変更
- Phase 2: `sudo usermod` でdockerグループ追加
- Phase 4: `sudo ln -sf` でsupervisord設定シンボリックリンク作成
- Phase 4: `sudo supervisord -t` で設定ファイル検証
- Phase 5: `sudo mkdir -p` でprocess-composeディレクトリ作成
- Phase 5: `sudo ln -sf` でprocess-compose設定シンボリックリンク作成

### 1.2 根本的な矛盾

**Dockerfile の ENTRYPOINT は USER 変更前に設定されている**

```dockerfile
# 215行目: ユーザー作成
RUN useradd -o -l -u ${UID} -g ${GNAME} -G docker -m ${UNAME}

# 225行目: sudoers設定
RUN echo "${UNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 235行目: ENTRYPOINT設定（この時点ではまだ USER は root）
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 239行目: WORKDIR設定
WORKDIR /home/${UNAME}

# この後も USER ディレクティブは存在しない
# => docker-entrypoint.sh は root として実行される！
```

**つまり、docker-entrypoint.sh は root として実行されているにも関わらず、スクリプト内で sudo を使用している**

これは以下の問題を引き起こす:
1. **不要な権限エスカレーション**: rootがさらにsudoを使う意味がない
2. **設計の不明瞭性**: 実行ユーザーが曖昧で、意図が不明確
3. **25_6_6の誤った仮説**: "docker-entrypoint.sh は非rootユーザー（<一般ユーザー>）として実行される" という前提が誤り

---

## 2. 原因

### 2.1 直接的原因

1. **USER ディレクティブの欠如**:
   - Dockerfileに `USER <一般ユーザー>` ディレクティブが存在しない
   - ENTRYPOINTはデフォルトでroot権限で実行される

2. **sudo の誤用**:
   - rootで実行されているスクリプト内で、不必要にsudoを使用
   - Phase 1-5 のすべての操作がroot権限で実行可能なのに、sudoを明示している

3. **25_6_6での誤認**:
   - セクション14.3で「docker-entrypoint.sh は非rootユーザー（<一般ユーザー>）として実行される」と記載
   - この前提に基づき、`sudo supervisord -t` を提案
   - 実際には root として実行されているため、sudo は不要

### 2.2 設計上の混乱

以下の2つのアプローチが混在している:

**アプローチA**: docker-entrypoint.sh を root で実行し、初期化後に su で一般ユーザーに切り替え
- メリット: 初期化処理に必要な権限をシンプルに実行できる
- デメリット: セキュリティリスク、プロセス管理の複雑化

**アプローチB**: docker-entrypoint.sh を一般ユーザーで実行し、必要な箇所のみsudoを使用
- メリット: 最小権限の原則に従う、セキュリティ向上
- デメリット: 現状のDocker構造では実現されていない（USER未設定）

**現状**: どちらのアプローチも完全には実装されておらず、中途半端な状態

---

## 3. 目的（あるべき状態）

### 3.1 短期目標

**supervisord検証失敗問題を解決し、seed.confへのフォールバックを防ぐ**

成功基準:
- `/etc/supervisor/supervisord.conf` が `workloads/supervisord/project.conf` を指す
- `supervisorctl status` がエラーなく動作する

### 3.2 中長期目標

**docker-entrypoint.sh の実行ユーザーと権限管理を明確化する**

成功基準:
- Dockerfileの設計意図が明確（rootで実行 or 一般ユーザーで実行）
- 不要なsudoが削除され、必要な権限のみ使用される
- セキュリティベストプラクティスに従う

---

## 4. 戦略・アプローチ（解決の方針）

### 戦略A: rootで実行し、sudoを完全削除 ★推奨（短期）★

**方針**: 現状の設計（docker-entrypoint.sh がrootで実行）を明示的に維持し、sudoをすべて削除

**理由**:
- 既存の構造を最小限の変更で修正できる
- supervisord検証問題を即座に解決
- 設計意図が明確になる（rootでの初期化を意図している）

### 戦略B: 一般ユーザーで実行し、sudoを適切に配置

**方針**: Dockerfileに `USER ${UNAME}` を追加し、docker-entrypoint.shを一般ユーザーで実行

**理由**:
- セキュリティベストプラクティスに従う
- 最小権限の原則を実現
- ただし、Phase 1-5 の操作にroot権限が必要なため、sudoは残る

### 戦略C: s6-overlay oneshot サービスとして実行し、権限を分離

**方針**: docker-entrypoint.shをs6-overlay のoneshotサービスとして実行し、サービス定義で実行ユーザーを制御

**理由**:
- プロセス管理の責務をs6-overlayに委譲
- 権限分離が明確
- ただし、s6-overlay設定の複雑化

---

## 5. 解決策（3つの異なるアプローチ）

### 解決策1: rootで実行・sudo完全削除（アプローチA実装） ★推奨★

**概要**: docker-entrypoint.shがrootで実行されることを前提とし、すべてのsudoを削除

#### 実施手順

##### Step 1: docker-entrypoint.sh からsudoを削除

```bash
# Phase 1: 修正前
sudo chown -R $(id -u):$(id -g) "$item"

# Phase 1: 修正後
chown -R ${UNAME}:${GNAME} "$item"
```

```bash
# Phase 2: 修正前
sudo chmod 666 /var/run/docker.sock
sudo usermod -a -G docker $(whoami)

# Phase 2: 修正後
chmod 666 /var/run/docker.sock
usermod -a -G docker ${UNAME}
```

```bash
# Phase 4, 5: 修正前
sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"
sudo supervisord -c "${TARGET_CONF}" -t 2>&1

# Phase 4, 5: 修正後
ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"
supervisord -c "${TARGET_CONF}" -t 2>&1
```

##### Step 2: Dockerfileにコメント追加（設計意図の明示）

```dockerfile
# ENTRYPOINT runs as root for initialization tasks
# This allows direct filesystem operations without sudo
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

#### メリット
- **即効性**: 最小限の変更で問題解決
- **シンプル**: sudoの複雑さが排除される
- **明確性**: root実行が設計意図であることが明示される
- **25_6_6の修正が不要**: supervisord -t はroot権限で実行されるため、そのまま動作

#### デメリット
- **セキュリティ**: rootで実行し続けるため、セキュリティリスクが残る
- **ベストプラクティス違反**: コンテナセキュリティのベストプラクティスに反する

#### 適用シーン
- **今すぐsupervisord検証問題を解決したい場合**（現在の状況に最適）
- 短期的な修正として実施し、後でセキュリティ改善を検討

---

### 解決策2: 一般ユーザーで実行・sudoを適切配置（アプローチB実装）

**概要**: Dockerfileに `USER ${UNAME}` を追加し、docker-entrypoint.shを一般ユーザーで実行。必要な箇所のみsudoを使用。

#### 実施手順

##### Step 1: Dockerfileに USER ディレクティブ追加

```dockerfile
# ENTRYPOINT の前に USER を追加
RUN echo "${UNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${UNAME}  # 追加

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

##### Step 2: docker-entrypoint.sh のsudoを適切に配置

- Phase 1-5 で必要な箇所にsudoを残す
- `$(whoami)` や `$(id -u)` を `${UNAME}` に置き換え（一般ユーザーとして実行されるため）

```bash
# Phase 4: 修正後（sudoを残す）
sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"
sudo supervisord -c "${TARGET_CONF}" -t 2>&1
```

#### メリット
- **セキュリティ向上**: 最小権限の原則に従う
- **ベストプラクティス準拠**: コンテナセキュリティのベストプラクティスに沿う
- **監査性**: sudo使用箇所が明確で、権限が必要な操作が可視化される

#### デメリット
- **実装コスト**: Dockerfileとdocker-entrypoint.shの両方を修正
- **テスト負荷**: USER変更による副作用を検証する必要
- **sudo依存**: sudoersの設定が正しくないと失敗

#### 適用シーン
- セキュリティを重視する本番環境
- 長期的な安定運用を目指す場合

---

### 解決策3: s6-overlay oneshotサービス化・権限分離（アプローチC実装）

**概要**: docker-entrypoint.shをs6-overlay のoneshotサービスとして定義し、s6-overlay の機能で実行ユーザーを制御

#### 実施手順

##### Step 1: ENTRYPOINTを /init に変更

```dockerfile
# 修正前
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 修正後
ENTRYPOINT ["/init"]
```

##### Step 2: s6-rc.d/docker-entrypoint/up にユーザー指定を追加

```bash
#!/command/execlineb -P
# s6-setuidgid で実行ユーザーを指定
s6-setuidgid root /usr/local/bin/docker-entrypoint.sh
```

または

```bash
#!/command/execlineb -P
# 一般ユーザーで実行し、必要に応じてsudoを使用
s6-setuidgid <一般ユーザー> /usr/local/bin/docker-entrypoint.sh
```

#### メリット
- **プロセス管理の一元化**: s6-overlayがすべてのプロセスを管理
- **権限の柔軟性**: サービスごとに実行ユーザーを変更可能
- **設計の明確化**: 初期化処理がs6-overlayのライフサイクルに統合される

#### デメリット
- **複雑性**: s6-overlay の設定が複雑化
- **学習コスト**: execlineb の理解が必要
- **デバッグ困難**: s6-overlay のログメカニズムを理解する必要

#### 適用シーン
- s6-overlay を本格的に活用する場合
- 複数のサービスを同様にs6-overlayで管理する場合

---

## 6. 推奨アプローチの選定

### 即座の対処: **解決策1（rootで実行・sudo完全削除）** ★最優先★

**選定理由**:

1. **緊急性**: supervisord検証失敗問題を即座に解決
2. **シンプル**: 既存構造を最小限の変更で修正
3. **リスクの低さ**: docker-entrypoint.sh の動作ロジックを変更しない
4. **25_6_6の修正不要**: セクション14で提案された修正が実現される

**実施タイミング**: 今すぐ

---

### 中長期的対処: **解決策2（一般ユーザーで実行・sudoを適切配置）**

**選定理由**:

1. **セキュリティ**: ベストプラクティスに従う
2. **監査性**: sudo使用箇所が明確
3. **バランス**: 実装コストとセキュリティ向上のバランスが良い

**実施タイミング**: supervisord問題解決後、リファクタリングフェーズで検討

---

## 7. 実装計画（解決策1 → 解決策2 の段階的実施）

### Phase 1: 緊急対処（今すぐ実施）

#### タスク1-1: docker-entrypoint.sh からsudo削除

**変更箇所**:

1. Phase 1 (33行目):
   ```bash
   # 修正前
   sudo chown -R $(id -u):$(id -g) "$item"

   # 修正後
   chown -R ${UNAME}:${GNAME} "$item"
   ```

2. Phase 2 (55, 59行目):
   ```bash
   # 修正前
   sudo chmod 666 /var/run/docker.sock
   sudo usermod -a -G docker $(whoami)

   # 修正後
   chmod 666 /var/run/docker.sock
   usermod -a -G docker ${UNAME}
   ```

3. Phase 4 (133, 135, 153行目):
   ```bash
   # 修正前
   sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"
   sudo supervisord -c "${TARGET_CONF}" -t 2>&1
   sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"

   # 修正後
   ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"
   supervisord -c "${TARGET_CONF}" -t 2>&1
   ln -sf "${SEED_CONF}" "${TARGET_CONF}"
   ```

4. Phase 5 (171, 193, 195, 214, 222行目):
   ```bash
   # 修正前
   sudo ln -sf "${SEED_CONF}" "${TARGET_CONF}"
   sudo mkdir -p /etc/process-compose
   sudo ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"
   sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"
   sudo ln -sf "${SEED_YAML}" "${TARGET_YAML}"

   # 修正後
   ln -sf "${SEED_CONF}" "${TARGET_CONF}"
   mkdir -p /etc/process-compose
   ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"
   ln -sf "${SEED_YAML}" "${TARGET_YAML}"
   ln -sf "${SEED_YAML}" "${TARGET_YAML}"
   ```

#### タスク1-2: Dockerfileにコメント追加

```dockerfile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entrypoint & CMD
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ENTRYPOINT runs as root for initialization tasks
# This allows direct filesystem operations without sudo
# Future enhancement: Consider running as non-root user with sudo for security
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

#### タスク1-3: 25_6_6 ドキュメント更新

セクション14.3の記述を訂正:

```markdown
### 14.3 Phase 4 失敗の根本原因（訂正版）

**誤認の訂正**:
以前の分析では「docker-entrypoint.sh は非rootユーザー（<一般ユーザー>）として実行される」と記載していたが、これは誤りであった。

**実際の状況**:
- Dockerfileに `USER` ディレクティブが存在しない
- ENTRYPOINTはデフォルトでroot権限で実行される
- したがって、docker-entrypoint.sh は **root として実行されている**

**Phase 4 失敗の真の原因**:
25_6_7で詳細に分析されている通り、supervisord検証失敗の原因はsudo の欠如ではなく、別の要因である可能性が高い。

**次のアクション**:
25_6_7の解決策1（sudo完全削除）を実施し、実際にsupervisord検証が成功するか検証する。
```

#### タスク1-4: コミット

```bash
git add .devcontainer/docker-entrypoint.sh .devcontainer/Dockerfile initiatives/20251229--dev-hub-concept/25_6_6_docker_entrypoint_execution_failure_analysis.md initiatives/20251229--dev-hub-concept/25_6_7_sudo_privilege_escalation_issue_analysis.md

git commit -m "fix: remove unnecessary sudo from docker-entrypoint.sh

Root cause analysis revealed that docker-entrypoint.sh runs as root (no USER directive in Dockerfile), making all sudo calls unnecessary.

Changes:
1. docker-entrypoint.sh:
   - Removed all sudo calls (Phase 1, 2, 4, 5)
   - Changed $(whoami)/$(id -u) to ${UNAME}/${GNAME}
   - Simplified permissions and symlink operations

2. Dockerfile:
   - Added comment clarifying ENTRYPOINT runs as root
   - Noted future enhancement for non-root execution

3. Documentation:
   - Created 25_6_7_sudo_privilege_escalation_issue_analysis.md
   - Corrected 25_6_6 Section 14.3 misunderstanding

This fix resolves the supervisord validation issue by running 'supervisord -t' directly as root, without sudo.

Reference: 25_6_7_sudo_privilege_escalation_issue_analysis.md Section 5, Solution 1

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

#### タスク1-5: DevContainer 再ビルドと検証

```bash
# ビルド
docker compose build --no-cache

# コンテナ起動（または VS Code で接続）
docker compose up -d

# 検証
docker exec -it <container-name> bash
ls -l /etc/supervisor/supervisord.conf
# 期待: -> /home/<一般ユーザー>/hagevvashi.info-dev-hub/workloads/supervisord/project.conf

supervisorctl status
# 期待: エラーなく、プロセスリストが表示される
```

---

### Phase 2: 中長期対処（検証完了後、リファクタリング時）

#### タスク2-1: Dockerfileに USER ディレクティブ追加

#### タスク2-2: docker-entrypoint.sh のsudoを適切に配置

#### タスク2-3: セキュリティ監査とテスト

---

## 8. 成功基準

### Phase 1（緊急対処）の成功基準

| 基準 | 確認方法 | 期待結果 |
|------|---------|---------|
| sudoがすべて削除された | `grep -n sudo .devcontainer/docker-entrypoint.sh` | 0件 |
| supervisord検証成功 | コンテナ内で `ls -l /etc/supervisor/supervisord.conf` | `-> workloads/supervisord/project.conf` |
| supervisorctl動作 | コンテナ内で `supervisorctl status` | エラーなし、プロセスリスト表示 |

### Phase 2（中長期対処）の成功基準

| 基準 | 確認方法 | 期待結果 |
|------|---------|---------|
| USER設定完了 | `grep "^USER" .devcontainer/Dockerfile` | `USER ${UNAME}` が存在 |
| 最小権限の原則 | セキュリティ監査 | 不要なroot権限が使用されていない |

---

## 9. リスク管理

### リスク1: sudo削除による副作用

**影響度**: 中
**発生確率**: 低

**緩和策**:
- rootで実行されているため、sudo削除で動作が変わることはない
- ただし、chown のターゲットユーザーを正しく指定する必要がある（`${UNAME}:${GNAME}`）

**ロールバック**:
```bash
git revert HEAD
docker compose build
```

---

### リスク2: supervisord検証が依然として失敗

**影響度**: 高
**発生確率**: 中

**緩和策**:
- sudo削除後も失敗する場合、supervisord -t の実行環境を詳細に調査
- workloads/supervisord/project.conf の内容を確認
- supervisord のバージョンと -t オプションの互換性を確認

**対処**:
- 25_6_7にセクション10「Phase 1実施結果」を追加し、詳細を記録
- 必要に応じて、supervisord検証をスキップしてseed.confにフォールバックする設計を検討

---

## 10. 次のアクション

### 今すぐ実施（Phase 1）

- [ ] **タスク1-1**: docker-entrypoint.sh からsudo削除
- [ ] **タスク1-2**: Dockerfileにコメント追加
- [ ] **タスク1-3**: 25_6_6 ドキュメント訂正
- [ ] **タスク1-4**: 変更をコミット
- [ ] **タスク1-5**: DevContainer 再ビルドと検証

### 検証完了後（Phase 2）

- [ ] セキュリティ改善の検討（解決策2の実施）
- [ ] 25_4_2 v10実装トラッカーの更新

---

## 11. 参考資料

- [Dockerfile Best Practices - USER](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#user)
- [Container Security Best Practices](https://snyk.io/learn/container-security/)
- [25_6_6_docker_entrypoint_execution_failure_analysis.md](25_6_6_docker_entrypoint_execution_failure_analysis.md) - sudo使用の発端
- [25_6_1_docker_entrypoint_not_executed_analysis.v2.md](25_6_1_docker_entrypoint_not_executed_analysis.v2.md)

---

**このドキュメントは、docker-entrypoint.sh のsudo使用を見直し、Dockerfileの設計意図を明確化することで、supervisord検証問題を根本的に解決するものです。**
