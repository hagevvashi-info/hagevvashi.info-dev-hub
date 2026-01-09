# ユーザーコンテキスト要件の整理

**作成日**: 2026-01-10
**目的**: PID 1（s6-overlay）とDevContainer利用時のユーザーコンテキストの要件を明確化し、両立可能性を検証する

---

## 1. 要件定義

### 1.1 PID 1実行要件

**要件**: PID 1はrootユーザーで実行する

- **対象プロセス**: s6-overlay（`/init`）
- **実行ユーザー**: `root`
- **理由**:
  - ゾンビプロセスの回収にはPID 1の特権が必要
  - システムレベルのシグナル処理
  - graceful shutdownの制御

**現状**: ❌ `${UNAME}`ユーザーで実行されている（Dockerfile line 296で`USER ${UNAME}`指定後にENTRYPOINT配置）

---

### 1.2 DevContainerログイン時のユーザーコンテキスト要件

**要件**: DevContainerにbashでログインした際は`${UNAME}`ユーザーであるべき

- **対象**: VSCode DevContainer、`docker exec`等でのログイン
- **実行ユーザー**: `${UNAME}`（例: `${UNAME}`）
- **ワークディレクトリ**: `/home/${UNAME}/<このリポジトリ>`
- **理由**:
  - 開発作業時のファイル所有権の一貫性
  - rootでの作業を避けるセキュリティベストプラクティス

**現状**: 確認が必要

---

### 1.3 docker-entrypoint.sh実行時のユーザーコンテキスト要件

**背景**: docker-entrypoint.shは`~`（ホームディレクトリ）を前提としている

**要件**: docker-entrypoint.shは`${UNAME}`ユーザーで実行する必要がある

- **理由**: スクリプト内で`~`が使用されており、これは実行ユーザーのホームディレクトリを指す
- **代替案**: `~`を`/home/${UNAME}`に置き換え可能
- **注意点**: ファイル所有権・パーミッションを適切に設定する必要がある

**現状**: 確認が必要（s6-overlayのoneshotサービスとして実行される際のユーザー）

---

## 2. 両立可能性の検証

### 2.1 結論

✅ **すべての要件は両立可能**

### 2.2 実現方法

s6-overlayの機能を活用することで、以下の構成が可能:

```
┌─────────────────────────────────────────────┐
│ PID 1: s6-overlay (root)                    │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ docker-entrypoint (oneshot)         │   │
│  │ - 実行ユーザー: ${UNAME}            │   │ ← ユーザー指定可能
│  │ - ホームディレクトリ: /home/${UNAME}│   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ supervisord (longrun)               │   │
│  │ - 実行ユーザー: root or ${UNAME}    │   │ ← ユーザー指定可能
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ process-compose (longrun)           │   │
│  │ - 実行ユーザー: root or ${UNAME}    │   │ ← ユーザー指定可能
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 2.3 実装方法

#### 方法1: s6-overlayサービス定義でユーザーを指定（推奨）

**docker-entrypoint/up** を修正:

```bash
#!/command/execlineb -P
# ユーザーを${UNAME}に切り替えてから実行
s6-setuidgid ${UNAME} /usr/local/bin/docker-entrypoint.sh
```

**メリット**:
- Dockerfileの`USER`指定を削除でき、ENTRYPOINTをrootで実行可能
- 各サービスごとに実行ユーザーを柔軟に指定可能

#### 方法2: docker-entrypoint.sh内で`~`を`/home/${UNAME}`に置き換え

**docker-entrypoint.sh** を修正:

```bash
# 修正前
chown -R ${UNAME}:${GNAME} ~/.cache

# 修正後
chown -R ${UNAME}:${GNAME} /home/${UNAME}/.cache
```

**メリット**:
- rootユーザーで実行しても正しくホームディレクトリを参照
- `chown`等の権限操作が確実に実行される

#### 方法3: 両方を組み合わせ（最も堅牢）

1. Dockerfileから`USER ${UNAME}`を削除（またはENTRYPOINT前に移動）
2. s6-overlayサービス定義で`s6-setuidgid`を使用
3. docker-entrypoint.sh内の`~`を`/home/${UNAME}`に置き換え

---

## 3. DevContainerログイン時のユーザー設定

### 3.1 要件の詳細化（ユーザーからの質疑応答）

**ユーザーからの要望**:
> devcontainer.json の remoteUser で設定 - これは既に設定されている可能性が高い（確認が必要）
>
> ここは、devcontainer も docker compose からのログインも、両対応できるようにしてほしい。
> devcontainer.json に書いたって、普通に docker compose から入る場合は採用されないわけだし

**重要な指摘**: `devcontainer.json`の`remoteUser`設定は、VSCode DevContainer利用時のみ有効。`docker compose exec`や`docker exec`からのログイン時には適用されない。

### 3.2 両方に対応する設定方法

#### 方法1: Dockerfileで`USER`を最後に指定（推奨）

```dockerfile
# Dockerfile最終行付近
ENTRYPOINT ["/init"]

# ENTRYPOINTの後にUSER指定（ログイン時のデフォルトユーザーのみ変更）
USER ${UNAME}
```

**効果**:
- ✅ ENTRYPOINTはrootで実行（PID 1がroot）
- ✅ `docker exec bash`等のログインは`${UNAME}`ユーザー
- ✅ VSCode DevContainerのログインも`${UNAME}`ユーザー（`devcontainer.json`の`remoteUser`設定がなくても）
- ✅ docker-compose.ymlに追加設定不要

**注意**: Dockerの仕様として、`USER`指定は以降のレイヤー（RUN等）と、コンテナ起動後のデフォルトユーザーに影響するが、**ENTRYPOINTには遡及しない**

#### 方法2: devcontainer.jsonとdocker-compose.ymlで個別設定

**devcontainer.json**:
```json
{
  "remoteUser": "${UNAME}",
  "workspaceFolder": "/home/${UNAME}/repos/hagevvashi.info-dev-hub"
}
```

**docker-compose.yml**:
```yaml
services:
  dev:
    # ENTRYPOINTはrootで実行したいため、user指定は使わない
    # 代わりに、Dockerfileの最後でUSER指定を利用
```

**問題点**: docker-compose.ymlに`user`を指定すると、ENTRYPOINTもそのユーザーで実行されてしまうため、使用できない

### 3.3 推奨アプローチ（方法1を採用）

**Dockerfile修正**:

```dockerfile
# 修正前（line 296-299付近）
USER ${UNAME}

# ... (コメント)

ENTRYPOINT ["/init"]

# 修正後（line 296-304付近）
# USER ${UNAME}  ← 削除またはコメントアウト

# s6-overlay を PID 1 として起動（/init）
# rootユーザーで実行し、各サービスで適切なユーザーに切り替え
ENTRYPOINT ["/init"]

# コンテナログイン時のデフォルトユーザーを設定
# ENTRYPOINTには影響せず、exec/attachのみに適用される
USER ${UNAME}
```

**devcontainer.json確認**:
```json
{
  "remoteUser": "${UNAME}"  // 念のため設定（Dockerfileで既に設定されているが、明示的に）
}
```

---

## 4. 推奨実装プラン（質疑応答を反映）

### Phase 1: Dockerfileの修正

**目的**: ENTRYPOINTをrootで実行し、ログイン時のデフォルトユーザーを`${UNAME}`に設定

```dockerfile
# 修正前（line 296-299付近）
USER ${UNAME}

# ... (コメント)

ENTRYPOINT ["/init"]

# 修正後（line 296-304付近）
# s6-overlay を PID 1 として起動（/init）
# rootユーザーで実行し、各サービスで適切なユーザーに切り替え
ENTRYPOINT ["/init"]

# コンテナログイン時のデフォルトユーザーを設定
# ENTRYPOINTには影響せず、docker exec/VSCode DevContainerのログインに適用
# これにより、devcontainer.jsonとdocker composeの両方に対応
USER ${UNAME}
```

**重要**: `USER ${UNAME}` を **ENTRYPOINTの後** に配置することで:
- PID 1はrootで実行
- `docker exec bash`も`VSCode DevContainer`も両方`${UNAME}`ユーザーでログイン

### Phase 2: s6-overlayサービス定義の修正

**目的**: docker-entrypoint.shを`${UNAME}`ユーザーで実行

**`.devcontainer/s6-rc.d/docker-entrypoint/up`**:

```bash
#!/command/execlineb -P
# ${UNAME}ユーザーで実行
# docker-entrypoint.sh内の~は${UNAME}のホームディレクトリを指す
s6-setuidgid ${UNAME} /usr/local/bin/docker-entrypoint.sh
```

### Phase 3: docker-entrypoint.shの修正（オプション）

**目的**: `~` を `/home/${UNAME}` に置き換え、より堅牢にする

**ユーザーからの要望**:
> 所有者パーミッションだけは気をつけたいですが

**対応**: `~` を `/home/${UNAME}` に置き換えることで、実行ユーザーに依存しない明示的なパス指定になる

### Phase 4: devcontainer.jsonの確認

**目的**: VSCode DevContainer利用時のユーザー設定を確認

```json
{
  "remoteUser": "${UNAME}"  // Dockerfileで既に設定されているが、念のため明示
}
```

**注記**: Dockerfile最後で`USER ${UNAME}`を指定しているため、この設定がなくても動作する。ただし、明示的に設定することでドキュメント性が向上。

---

## 5. 検証項目

### 5.1 PID 1検証

```bash
docker exec devcontainer-dev-1 ps aux | head -n 2
```

**期待結果**:
```
USER       PID  COMMAND
root         1  s6-svscan /run/service
```

### 5.2 docker-entrypoint.sh実行ユーザー検証

```bash
docker logs devcontainer-dev-1 2>&1 | grep "Running as user"
```

または、docker-entrypoint.shに以下を追加:
```bash
echo "Running docker-entrypoint.sh as user: $(whoami)"
```

**期待結果**: `${UNAME}`

### 5.3 ログインユーザー検証（devcontainerとdocker compose両対応）

#### 5.3.1 VSCode DevContainerからのログイン

VSCode DevContainerで接続後:
```bash
whoami
pwd
```

**期待結果**:
```
${UNAME}
/home/${UNAME}/repos/hagevvashi.info-dev-hub
```

#### 5.3.2 docker composeからのログイン

```bash
docker exec -it devcontainer-dev-1 bash
whoami
pwd
```

**期待結果**:
```
${UNAME}
/home/${UNAME}  # またはワークディレクトリ
```

**重要**: どちらの方法でログインしても、ユーザーは`${UNAME}`であること（Dockerfile最後の`USER`指定により実現）

---

## 6. まとめ

### 6.1 要件の両立可能性

✅ **すべての要件は両立可能**

1. **PID 1はrootで実行**
   - Dockerfileで`ENTRYPOINT ["/init"]`を`USER`指定の前に配置

2. **docker-entrypoint.shは`${UNAME}`で実行**
   - s6-overlayサービス定義で`s6-setuidgid`使用

3. **ログインは`${UNAME}`ユーザー（devcontainerとdocker compose両対応）**
   - Dockerfileの**最後**に`USER ${UNAME}`を配置
   - これにより、VSCode DevContainerと`docker exec`の両方で`${UNAME}`ユーザーとしてログイン可能

### 6.2 質疑応答からの重要な学び

**ユーザーからの指摘**:
> devcontainer.json に書いたって、普通に docker compose から入る場合は採用されないわけだし

**解決策**:
- `devcontainer.json`の`remoteUser`設定だけでは不十分
- Dockerfileの最後に`USER ${UNAME}`を配置することで、**両方に対応**

### 6.3 実装の優先順位

**即座に対応が必要**:
- Dockerfileの`USER ${UNAME}`をENTRYPOINTの後に移動（Phase 1）
- s6-overlayサービス定義の修正（Phase 2）

**後回しでも可**:
- docker-entrypoint.sh内の`~`を`/home/${UNAME}`に置き換え（Phase 3）

### 6.4 次のステップ

現在、25_6_12（v10完成）の検証中に25_6_10（USER問題）を発見した状態。

**選択肢A**: 25_6_12と25_6_10を同時に解決してから検証を続行
**選択肢B**: 現状のまま検証を続行し、25_6_10は後回し

**推奨**: 選択肢A（同時解決）
- 理由: Dockerfile 1行の修正（`USER ${UNAME}`の移動）だけで解決可能
- リスク: 低（変更箇所が明確）

---

## 7. 【重要】理論と実践の乖離

**更新日**: 2026-01-10T02:00:00+09:00

### 7.1 実装結果の検証

**Phase 1-4 の実装**（2026-01-10T00:48:00+09:00）:
- Dockerfile line 306-309 で `USER ${UNAME}` を ENTRYPOINT の後に配置

**Phase 2-3 の検証結果**（2026-01-10T01:32:00+09:00）:

#### ✅ 成功: PID 1 は root で実行
```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0    428    96 ?        Ss   17:32   0:00 /package/admin/s6/command/s6-svscan -d4 -- /run/service
```

#### ❌ 失敗: docker exec bash で root としてログイン
```bash
$ docker exec -it devcontainer-dev-1 bash
bash: /root/.atuin/bin/env: No such file or directory
```

### 7.2 理論の誤りの確認

**このドキュメントで立案した理論**（セクション3.2 方法1）:
> **効果**:
> - ✅ ENTRYPOINTはrootで実行（PID 1がroot）
> - ✅ `docker exec bash`等のログインは`${UNAME}`ユーザー

**実際の結果**:
- ✅ ENTRYPOINT は root で実行（PID 1 が root） ← **理論通り**
- ❌ `docker exec bash` は **root** ユーザー ← **理論と矛盾**

**さらなる検証**（ユーザーによる）:
- `USER ${UNAME}` をアンコメント → PID 1 が **非root** で実行される
- **結論**: `USER ${UNAME}` の配置位置（ENTRYPOINT の前後）は無関係

### 7.3 Docker の実際の仕様

**誤った理解**（セクション3.2 line 156）:
> Dockerの仕様として、`USER`指定は以降のレイヤー（RUN等）と、コンテナ起動後のデフォルトユーザーに影響するが、**ENTRYPOINTには遡及しない**

**正しい理解**:
- Dockerfile の `USER` 指定は、イメージメタデータの `User` フィールドを設定する
- コンテナ起動時、`User` フィールドが設定されている場合、**すべてのプロセス**（ENTRYPOINT、CMD、docker exec）がそのユーザーで実行される
- **ENTRYPOINT の前後は関係ない** - 最終的な `USER` 指定がイメージメタデータに記録される

### 7.4 結論

❌ **このドキュメント（25_6_13）で提案した方法1は機能しない**

**デッドロック状態**:
- `USER ${UNAME}` コメントアウト → PID 1=root ✅, docker exec=root ❌
- `USER ${UNAME}` アンコメント → PID 1=非root ❌, docker exec=${UNAME} ✅

**Dockerfile の `USER` ディレクティブだけでは両要件を両立できない**

### 7.5 代替解決策

**詳細分析ドキュメント**: `25_6_14_user_directive_limitation_analysis.md`

**推奨アプローチ: bashログイン時の自動ユーザー切り替え**
1. `USER ${UNAME}` をコメントアウトのまま維持（PID 1 = root）
2. `/root/.bashrc` に自動ユーザー切り替えロジックを追加
3. docker exec セッション検出 → `exec su - ${UNAME}` で透過的に切り替え

**理由**:
- ✅ 要件を完全に満たす（PID 1=root、docker exec=${UNAME}）
- ✅ セキュリティベストプラクティスに準拠
- ✅ v10設計を維持
- ✅ 将来的な拡張性

**非推奨: rootログイン許容**
- ❌ セキュリティベストプラクティス違反
- ❌ 変更量が少ないという理由だけで選択すべきではない

---

**最終更新**: 2026-01-10T02:00:00+09:00
**ステータス**: ❌ **理論が実践で破綻** - 代替策が必要
**次のアクション**: 25_6_14 の代替解決策を実装
