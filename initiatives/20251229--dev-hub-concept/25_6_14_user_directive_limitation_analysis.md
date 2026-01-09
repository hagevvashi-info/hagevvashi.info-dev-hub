# Docker USER ディレクティブの挙動分析: 理論と実践の乖離

**作成日**: 2026-01-10
**目的**: Dockerfile の `USER` ディレクティブが ENTRYPOINT の後に配置された場合の実際の挙動を記録し、25_6_13 で立案した理論が実践で破綻したことを分析する

**関連ドキュメント**:
- `25_6_13_user_context_requirements.md` - 理論的仮説（実践で破綻）
- `25_6_12_v10_completion_implementation_tracker.md` - 実装と検証の記録
- `25_0_process_management_solution.v10.md` - v10設計

---

## 1. 問題の概要

### 1.1 要件

**v10設計で必要な2つの要件**:
1. **PID 1はrootで実行** - s6-overlayがPID 1としてゾンビプロセス回収とシグナル処理を行う
2. **docker execログインは`${UNAME}`ユーザー** - VSCode DevContainerと`docker compose exec`の両方に対応

### 1.2 25_6_13の理論的仮説

**25_6_13_user_context_requirements.md セクション3.2 方法1** で以下のように記載:

```dockerfile
ENTRYPOINT ["/init"]

# ENTRYPOINTの後にUSER指定（ログイン時のデフォルトユーザーのみ変更）
USER ${UNAME}
```

**理論上の効果**:
- ✅ ENTRYPOINTはrootで実行（PID 1がroot）
- ✅ `docker exec bash`等のログインは`${UNAME}`ユーザー
- ✅ VSCode DevContainerのログインも`${UNAME}`ユーザー
- ✅ docker-compose.ymlに追加設定不要

**根拠**（25_6_13 line 156）:
> Dockerの仕様として、`USER`指定は以降のレイヤー（RUN等）と、コンテナ起動後のデフォルトユーザーに影響するが、**ENTRYPOINTには遡及しない**

### 1.3 実践での結果

**Phase 1-4での実装**（2026-01-10T00:48:00+09:00）:
- Dockerfile line 306-309 で `USER ${UNAME}` を ENTRYPOINT の後に配置

**Phase 2-3での検証結果**（2026-01-10T01:32:00+09:00）:

#### ✅ **成功**: PID 1はrootで実行
```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0    428    96 ?        Ss   17:32   0:00 /package/admin/s6/command/s6-svscan -d4 -- /run/service
```

#### ❌ **失敗**: docker exec bashでrootとしてログイン
```bash
$ docker exec -it devcontainer-dev-1 bash
bash: /root/.atuin/bin/env: No such file or directory
```

**エラーの原因**: rootユーザーとしてログインしているため、`/root/.atuin/bin/env` が参照された

### 1.4 ユーザーによる追加検証

**ユーザーからの報告**（会話履歴より）:
> "PID 1 が非ルートになることは確認済みです"

つまり、`USER ${UNAME}` をアンコメントすると:
- ❌ PID 1が非rootで実行される（25_6_13の理論と矛盾）
- ✅ docker execは`${UNAME}`ユーザーでログイン

---

## 2. 理論と実践の乖離分析

### 2.1 25_6_13の理論が誤りだった理由

**仮説**: Dockerfileの`USER`指定はENTRYPOINTに遡及しない

**実際の挙動**:
1. `USER ${UNAME}` がコメントアウト → PID 1=root, docker exec=root
2. `USER ${UNAME}` がアンコメント → **PID 1=非root**, docker exec=${UNAME}

**結論**: **USER指定はENTRYPOINTに影響を与える**（理論の誤り）

### 2.2 Docker Image Metadata の影響

**`docker inspect` の結果**（会話履歴より）:
```json
"User": "${UNAME}"
```

**重要な発見**: Dockerfileで`USER ${UNAME}`を指定すると、イメージのメタデータに記録され、コンテナ起動時の**すべてのプロセス**（ENTRYPOINTを含む）に影響する。

### 2.3 Dockerの実際の仕様

**正しい理解**:
- Dockerfileの`USER`指定は、イメージメタデータの`User`フィールドを設定する
- コンテナ起動時、`User`フィールドが設定されている場合、**すべてのプロセス**（ENTRYPOINT、CMD、docker exec）がそのユーザーで実行される
- **ENTRYPOINTの前後は関係ない** - 最終的な`USER`指定がイメージメタデータに記録される

---

## 3. 現在の状況（デッドロック）

### 3.1 Dockerfile USER ディレクティブの限界

**選択肢A**: `USER ${UNAME}` をコメントアウト
- ✅ PID 1 = root
- ❌ docker exec = root（/root/.atuinエラー）

**選択肢B**: `USER ${UNAME}` をアンコメント
- ❌ PID 1 = 非root（v10設計違反）
- ✅ docker exec = ${UNAME}

**結論**: **Dockerfileの`USER`ディレクティブだけでは両立不可能**

### 3.2 なぜ devcontainer.json の remoteUser では解決できないか

**ユーザーからの要件**（会話履歴より）:
> "devcontainer も docker compose からのログインも、両対応できるようにしてほしい。devcontainer.json に書いたって、普通に docker compose から入る場合は採用されないわけだし"

**理由**:
- `devcontainer.json`の`remoteUser`設定は、VSCode DevContainer利用時のみ有効
- `docker compose exec`や`docker exec`からのログイン時には適用されない

---

## 4. 代替解決策の検討

### 4.1 選択肢1: rootログインを許容し、/root/.atuin問題を修正

**アプローチ**:
- `USER ${UNAME}` をコメントアウトのまま維持
- `/root/.bashrc` や `/root/.bash_profile` で atuin の初期化を条件付きに変更
- または、rootユーザー用の `.atuin` 設定を作成

**メリット**:
- PID 1 = root（v10設計を維持）
- シンプルな修正で解決可能

**デメリット**:
- 開発時にrootユーザーを使用（セキュリティベストプラクティス違反だが、開発コンテナでは許容範囲）

### 4.2 選択肢2: bashログイン時に自動的にsu/sudoで${UNAME}に切り替え

**アプローチ**:
- `USER ${UNAME}` をコメントアウトのまま維持
- `/root/.bashrc` の先頭に以下を追加:
```bash
# docker execからのログインの場合、${UNAME}ユーザーに切り替え
if [ "$SHLVL" = "1" ] && [ -n "$UNAME" ]; then
    exec su - "$UNAME"
fi
```

**メリット**:
- PID 1 = root（v10設計を維持）
- docker exec は実質 ${UNAME} として動作

**デメリット**:
- やや複雑
- デバッグ時に混乱の可能性

### 4.3 選択肢3: docker-compose.yml で user 指定（非推奨）

**アプローチ**:
```yaml
services:
  dev:
    user: "${UNAME}"
```

**問題点**: ENTRYPOINTもそのユーザーで実行されてしまうため、PID 1がrootにならない

### 4.4 選択肢4: s6-overlay の機能を活用（最も堅牢だが複雑）

**アプローチ**:
- ENTRYPOINTはrootで実行（USER指定なし）
- s6-overlayのサービス定義で各サービスごとにユーザーを指定
- docker execのデフォルトシェルを変更し、自動的に${UNAME}に切り替え

**メリット**:
- 完全な制御が可能
- 各サービスごとに最適なユーザーで実行

**デメリット**:
- 実装が複雑
- docker execのデフォルトシェル変更が必要

---

## 5. 推奨アプローチ

### 5.1 推奨: 選択肢2（bashログイン時の自動ユーザー切り替え）

**理由**:
1. **要件を完全に満たす** - PID 1=root、docker exec=${UNAME} の両立
2. **セキュリティベストプラクティスに準拠** - rootログインを避ける
3. **透過的** - ユーザーは ${UNAME} として作業、システムは適切に動作
4. **v10設計を維持** - PID 1はrootで実行
5. **拡張性** - 将来的にさらなる改善が可能

**実装内容**:
1. `/root/.bashrc` に自動ユーザー切り替えロジックを追加
2. docker exec セッション検出（`$SHLVL` や環境変数）
3. `exec su - ${UNAME}` で透過的にユーザー切り替え

### 5.2 将来的な改善: 選択肢4（s6-overlay機能活用）

**理由**:
- 最も堅牢で柔軟な解決策
- 各プロセスごとに最適なユーザーで実行可能
- コンテナレベルでの制御が可能

**実装の具体的内容**:

#### 手順1: docker exec 専用のシェルラッパーを作成

**`/usr/local/bin/docker-exec-shell.sh`** を作成:
```bash
#!/bin/bash
# docker exec 専用のシェルラッパー
# PID 1 (s6-overlay) はrootで実行されるが、
# docker exec セッションは ${UNAME} ユーザーで実行される

# 環境変数から実行ユーザーを取得
TARGET_USER="${UNAME:-${UNAME}}"

# rootで実行されている場合のみ、ユーザーを切り替え
if [ "$(id -u)" = "0" ]; then
    # s6-overlay の s6-setuidgid を使用してユーザー切り替え
    exec /command/s6-setuidgid "${TARGET_USER}" /bin/bash "$@"
else
    # 既に非rootユーザーの場合はそのまま実行
    exec /bin/bash "$@"
fi
```

#### 手順2: Dockerfile でデフォルトシェルを変更

**`.devcontainer/Dockerfile`** に追加:
```dockerfile
# docker exec 専用のシェルラッパーを配置
COPY docker-exec-shell.sh /usr/local/bin/docker-exec-shell.sh
RUN chmod +x /usr/local/bin/docker-exec-shell.sh

# シンボリックリンクで /bin/bash を上書き（オプション、リスク高）
# または、環境変数でデフォルトシェルを指定
ENV SHELL=/usr/local/bin/docker-exec-shell.sh

# ENTRYPOINT は /init (s6-overlay) で、rootとして実行される
ENTRYPOINT ["/init"]

# USER 指定はしない（コメントアウトのまま）
# USER ${UNAME}
```

#### 手順3: s6-overlay サービス定義の詳細化

既に実装済みだが、さらに細かく制御する場合:

**`.devcontainer/s6-rc.d/docker-entrypoint/run`**（より詳細な制御）:
```bash
#!/usr/bin/env bash
# docker-entrypoint を ${UNAME} ユーザーで実行

# ログ出力
echo "[s6-overlay] Starting docker-entrypoint as user: ${UNAME}"

# ユーザーの存在確認
if ! id "${UNAME}" &>/dev/null; then
    echo "[s6-overlay] ERROR: User ${UNAME} does not exist"
    exit 1
fi

# ホームディレクトリの確認
HOME_DIR="/home/${UNAME}"
if [ ! -d "${HOME_DIR}" ]; then
    echo "[s6-overlay] ERROR: Home directory ${HOME_DIR} does not exist"
    exit 1
fi

# 環境変数を設定してユーザー切り替え
exec /command/s6-envdir -fn -- /run/s6/container_environment \
     /command/s6-setuidgid "${UNAME}" \
     /usr/local/bin/docker-entrypoint.sh
```

#### 手順4: 環境変数の管理

**`.devcontainer/s6-rc.d/docker-entrypoint/env/`** ディレクトリを作成:
```bash
# 環境変数ファイルを配置
.devcontainer/s6-rc.d/docker-entrypoint/env/
  ├── HOME              # 内容: /home/${UNAME}
  ├── USER              # 内容: ${UNAME}
  └── SHELL             # 内容: /bin/bash
```

#### メリット

1. **完全な分離**:
   - PID 1 (s6-overlay) = root
   - docker-entrypoint = ${UNAME}
   - supervisord = root または ${UNAME}（設定可能）
   - process-compose = ${UNAME}
   - docker exec = ${UNAME}（ラッパー経由）

2. **拡張性**:
   - サービスごとに異なるユーザーで実行可能
   - 環境変数の細かい制御
   - ログ出力の統一管理

3. **堅牢性**:
   - ユーザーの存在確認
   - ホームディレクトリの検証
   - エラーハンドリング

#### デメリット

1. **複雑性**:
   - 複数のスクリプトとサービス定義が必要
   - デバッグが困難になる可能性

2. **互換性のリスク**:
   - デフォルトシェルを変更すると、一部のツールが動作しない可能性
   - `/bin/bash` を直接呼び出すツールには効果がない

3. **メンテナンスコスト**:
   - s6-overlay の仕様変更に追従が必要
   - カスタムスクリプトの保守

#### 推奨しない理由（致命的な問題あり）

**選択肢4は実用性がない**:

1. **致命的な問題: `/bin/bash` 直接呼び出しをバイパスできない**
   ```bash
   # 環境変数 SHELL=/usr/local/bin/docker-exec-shell.sh でも
   docker exec -it devcontainer-dev-1 /bin/bash
   # → ラッパーをバイパスして、rootとしてログイン
   ```
   - ユーザーや IDE が `/bin/bash` を直接指定すると、ラッパーは機能しない
   - VSCode DevContainer も `/bin/bash` を直接呼び出す可能性が高い

2. **`/bin/bash` の上書きはリスクが高すぎる**
   ```dockerfile
   # シンボリックリンクで /bin/bash を上書き
   RUN mv /bin/bash /bin/bash.orig && \
       ln -s /usr/local/bin/docker-exec-shell.sh /bin/bash
   ```
   - システムスクリプトが壊れる可能性
   - デバッグが困難
   - セキュリティリスク

3. **過度に複雑**
   - 複数のスクリプトとサービス定義が必要
   - デバッグが困難

**結論**: 選択肢4は理論上は可能だが、実用性がないため**採用不可**

**選択肢2（bashログイン時の自動ユーザー切り替え）が唯一の実用的な解決策**:
- `/root/.bashrc` でユーザー切り替え
- `/bin/bash` が呼び出されても、bashrc が実行されるため機能する
- シンプルで確実

### 5.3 非推奨: 選択肢1（rootログイン許容）

**理由**:
- ❌ セキュリティベストプラクティス違反
- ❌ ファイル所有権の問題が発生しやすい
- ❌ 将来的な問題の温床になる

**このアプローチは採用しない** - 変更量が少ないという理由だけで選択すべきではない

---

## 6. 教訓と今後の方針

### 6.1 ドキュメント作成時の教訓

**問題点**:
- 25_6_13 で Docker の仕様を誤解したまま「理論」として記載
- 実装前に簡易検証を行わなかった

**改善策**:
- 戦略立案時は「仮説」として記載し、実装後に「検証済み」にアップデート
- 重要な仕様は公式ドキュメントで確認

### 6.2 今後の実装方針

**Phase 2 検証の続行**:
1. 選択肢1を採用し、atuin問題を修正
2. Phase 2 残りの検証項目（2-4〜2-8）を実施
3. 検証完了後、Phase 3（ドキュメント更新）とPhase 4（コミット）を実施

**ドキュメント更新**:
- 25_6_13 に「理論と実践の乖離」セクションを追加
- 25_6_12実装トラッカーに Phase 2 の進捗を記録
- この分析ドキュメント（25_6_14）を作成

---

## 7. まとめ

### 7.1 理論と実践の乖離

**25_6_13の理論**:
- ❌ `USER ${UNAME}` を ENTRYPOINT の後に配置すれば、PID 1はroot、docker execは${UNAME}

**実際の挙動**:
- ✅ Dockerfileの`USER`指定は、配置位置に関わらず**すべてのプロセス**に影響する
- ✅ ENTRYPOINTの前後は関係ない

### 7.2 次のステップ

**immediate action** (今すぐ実施):
1. atuin初期化の条件分岐を実装（選択肢1）
2. Phase 2 検証を続行

**後続のドキュメント更新**:
1. 25_6_13 の訂正
2. 25_6_12実装トラッカーの更新

---

**最終更新**: 2026-01-10T02:00:00+09:00
**ステータス**: ✅ 分析完了
**次のアクション**: atuin問題の修正戦略を立案（mode-2）または直接実装（mode-3）
