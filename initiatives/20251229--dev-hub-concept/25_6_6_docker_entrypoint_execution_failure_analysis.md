# docker-entrypoint.sh 実行失敗問題の調査と分析

**作成日**: 2026-01-04
**発生状況**: DevContainer再ビルド後、docker-entrypointサービスが正常に実行されていない
**前提**: `25_6_1_docker_entrypoint_not_executed_analysis.v2.md` セクション11に基づくデバッグログ追加済み

---

## 1. 問題の発見経緯

### 1.1 背景

`25_6_1_docker_entrypoint_not_executed_analysis.v2.md` セクション11.4で提案された以下のデバッグログ追加を実施:

```bash
exec > /tmp/entrypoint.log 2>&1
set -x
```

その後、DevContainerを再ビルドし、`/tmp/entrypoint.log` を確認したところ、ログがPhase 1の途中（55行目）で終了していた。

### 1.2 観察された現象

1. **ログファイルが途中で終了**:
   - `/tmp/entrypoint.log` は55行目（Phase 1のパーミッション修正の途中）で終了
   - スクリプト全体は240行あるため、95%以上が未実行

2. **シンボリックリンクが作成されていない**:
   ```bash
   $ ls -l /etc/supervisor/supervisord.conf
   -rw-r--r-- 1 root root 1178 Dec 28  2022 /etc/supervisor/supervisord.conf
   ```
   - シンボリックリンクではなく実ファイル（古い設定ファイル）
   - `/etc/process-compose/process-compose.yaml` は存在しない

3. **s6サービスの異常**:
   - `docker-entrypoint` サービスが `/run/service/` に存在しない
   - `supervisord` と `process-compose` の s6-supervise プロセスは起動しているが、実際のサービス本体（supervisord / process-compose プロセス）が動作していない

---

## 2. 根本原因の特定

### 2.1 execによるリダイレクトの問題

`docker-entrypoint.sh` の5-6行目:

```bash
exec > /tmp/entrypoint.log 2>&1
set -x
```

この `exec` によるリダイレクトが、**s6-overlay の oneshot サービス実行環境と互換性がない**可能性がある。

#### 仮説1: execリダイレクトによるファイルディスクリプタの問題

`exec` はシェルプロセス自体の標準出力・標準エラー出力を置き換える。s6-overlay の oneshot サービスは、実行結果を特定の方法で監視している可能性があり、この置き換えがサービスの正常終了判定を妨げている可能性がある。

#### 仮説2: サービス実行がタイムアウトまたは失敗扱い

`set -x` によるトレースログが大量に出力されることで、バッファリングの問題やパフォーマンスの低下が発生し、s6-overlay がサービスのタイムアウトまたは異常終了と判断した可能性がある。

### 2.2 docker-entrypointサービスが /run/service/ に存在しない理由

s6-overlay の oneshot サービスは、正常に完了すると `/run/service/` には残らない（一度だけ実行されるため）。しかし、問題は以下の状況を示唆している:

- **ケースA**: サービスが途中で異常終了し、Phase 4/5のシンボリックリンク作成まで到達していない
- **ケースB**: サービスは実行されたが、exec リダイレクトの影響でログが途中で切れ、実際には最後まで実行された可能性もある（要確認）

---

## 3. 調査: ケースAとケースBの判定

### 3.1 シンボリックリンクの状態確認

```bash
$ ls -l /etc/supervisor/supervisord.conf
-rw-r--r-- 1 root root 1178 Dec 28  2022 /etc/supervisor/supervisord.conf

$ ls -l /etc/process-compose/process-compose.yaml
ls: cannot access '/etc/process-compose/process-compose.yaml': No such file or directory
```

**結論**: Phase 4/5のシンボリックリンク作成が実行されていない → **ケースA（途中で異常終了）が正しい**

### 3.2 /tmp/entrypoint.log の最終行分析

ログの最終行（55行目）:

```bash
+ sudo chown -R 501:20 /home/hagevvashi/.claude
```

この後、次の処理は:

```bash
for item in "${CONFIG_ITEMS[@]}"; do
    ...
done
echo "✅ Permissions fixed."
```

**推測**: `~/.claude` のパーミッション変更後、次の `~/.claude.json` の処理（存在しない場合はスキップ）で何らかの問題が発生した可能性。

---

## 4. なぜexecリダイレクトで失敗するのか

### 4.1 s6-overlay oneshot サービスの実行メカニズム

s6-overlay の oneshot サービス（`docker-entrypoint`）は、以下のように実行される:

```bash
# .devcontainer/s6-rc.d/docker-entrypoint/up
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh
```

execlineb は、シェルスクリプトではなくバイナリ実行を前提としたツールであり、標準入出力の扱いが通常のシェルと異なる可能性がある。

### 4.2 execリダイレクトの影響

`exec > /tmp/entrypoint.log 2>&1` により:

1. **標準出力と標準エラー出力が /tmp/entrypoint.log にリダイレクトされる**
2. **s6-overlay の監視プロセスは、元の標準出力/標準エラー出力を期待している**
3. **リダイレクトにより、s6-overlay がサービスの出力を監視できなくなる**
4. **結果として、サービスが「応答なし」または「異常終了」と判定される可能性**

### 4.3 検証可能な仮説

もし exec リダイレクトが原因であれば、以下の変更でログは最後まで記録されるはず:

```bash
# 修正前（問題あり）
exec > /tmp/entrypoint.log 2>&1
set -x

# 修正後（テスト）
# exec を使わず、個別のコマンドをリダイレクト
{
    set -x
    # スクリプト全体の内容
} > /tmp/entrypoint.log 2>&1
```

または、より安全な方法として `tee` を使用:

```bash
set -x
exec > >(tee -a /tmp/entrypoint.log) 2>&1
```

---

## 5. 解決のアプローチ

### アプローチ1: execリダイレクトを削除し、標準エラー出力のみをログファイルに記録

**変更内容**:

```bash
#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

# 標準エラー出力のみをログファイルに追記（標準出力はそのまま）
exec 2>> /tmp/entrypoint.log
set -x

set -euo pipefail
...
```

**利点**:
- s6-overlay の標準出力監視を妨げない
- デバッグトレース（`set -x`）は標準エラー出力に出力されるため、ログファイルに記録される
- シンプルで副作用が少ない

**欠点**:
- 標準出力（echoなど）がログファイルに記録されない

---

### アプローチ2: teeを使用して標準出力/標準エラー出力を複製

**変更内容**:

```bash
#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

# teeを使用して標準出力/標準エラー出力をログファイルにも出力
exec > >(tee -a /tmp/entrypoint.log) 2>&1
set -x

set -euo pipefail
...
```

**利点**:
- 標準出力も標準エラー出力もログファイルに記録される
- s6-overlay の監視プロセスにも出力が届く（teeが複製するため）

**欠点**:
- `tee` プロセスが起動するため、わずかにオーバーヘッドがある
- プロセス置換（`>(...)` 構文）が複雑

---

### アプローチ3: ログファイルへのリダイレクトを一時的に無効化し、s6ログを確認

**変更内容**:

```bash
#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

# リダイレクトを無効化（コメントアウト）
# exec > /tmp/entrypoint.log 2>&1
set -x

set -euo pipefail
...
```

**目的**:
- exec リダイレクトが原因かどうかを確認
- s6-overlay のログメカニズムを利用して、サービスの出力を確認

**利点**:
- 問題の切り分けが明確にできる
- s6-overlay の標準的なログ機構を使用

**欠点**:
- ログファイル `/tmp/entrypoint.log` には何も記録されない
- s6-overlay のログの場所を特定する必要がある

---

## 6. 推奨アプローチ

**アプローチ1（標準エラー出力のみをログファイルに記録）** を推奨します。

**理由**:
1. **シンプルで副作用が少ない**: exec によるリダイレクトは標準エラー出力のみに限定
2. **s6-overlay との互換性**: 標準出力は s6-overlay に渡されるため、監視プロセスが正常に動作する
3. **デバッグ情報は記録される**: `set -x` の出力は標準エラー出力に出力されるため、ログファイルに記録される

---

## 7. 実装計画

### 7.1 docker-entrypoint.sh の修正

`.devcontainer/docker-entrypoint.sh` の冒頭を以下のように修正:

```bash
#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

# 標準エラー出力のみをログファイルに追記（標準出力はs6-overlayに渡す）
exec 2>> /tmp/entrypoint.log
set -x

set -euo pipefail
...
```

### 7.2 DevContainer 再ビルドと検証

1. **再ビルド**:
   ```bash
   docker compose build --no-cache
   ```

2. **検証**:
   ```bash
   # シンボリックリンクが正しく作成されているか
   ls -l /etc/supervisor/supervisord.conf
   ls -l /etc/process-compose/process-compose.yaml

   # ログファイルが最後まで記録されているか
   tail -20 /tmp/entrypoint.log

   # supervisord と process-compose が正常に起動しているか
   ps aux | grep -E "(supervisord|process-compose)"
   ```

### 7.3 成功基準

- [ ] `/tmp/entrypoint.log` にスクリプト全体のトレースログが記録されている
- [ ] `/etc/supervisor/supervisord.conf` が `workloads/supervisord/project.conf` へのシンボリックリンクである
- [ ] `/etc/process-compose/process-compose.yaml` が `workloads/process-compose/project.yaml` へのシンボリックリンクである
- [ ] `supervisord` と `process-compose` のプロセスが正常に起動している

---

## 8. 代替案: s6-overlayのログ機構を活用（将来的な改善）

現在の `exec > /tmp/entrypoint.log` アプローチは一時的なデバッグ手法である。長期的には、s6-overlay の標準的なログ機構を活用すべき。

### s6-overlay でのログ記録方法

s6-overlay v3 では、longrun サービス（supervisord, process-compose）のログは以下のように設定できる:

```bash
# .devcontainer/s6-rc.d/supervisord/log/
├── type           # "longrun"
└── run            # ログハンドラスクリプト
```

ただし、oneshot サービス（docker-entrypoint）のログ記録は、s6-overlay のデフォルトメカニズムでは対応していない可能性があるため、現状の `/tmp/entrypoint.log` アプローチが妥当である。

---

## 9. 次のアクション

1. **即時実施**:
   - [ ] `.devcontainer/docker-entrypoint.sh` の `exec > /tmp/entrypoint.log 2>&1` を `exec 2>> /tmp/entrypoint.log` に修正
   - [ ] DevContainer を再ビルド
   - [ ] 検証（7.2参照）

2. **検証成功後**:
   - [ ] git commit（修正内容を記録）
   - [ ] 既存の PR に追加コミットとしてプッシュ
   - [ ] `25_6_1_docker_entrypoint_not_executed_analysis.v2.md` のセクション11に結果を追記

3. **検証失敗の場合**:
   - [ ] アプローチ3（リダイレクトを完全に無効化）を試行
   - [ ] s6-overlay のログの場所を特定
   - [ ] より詳細な原因分析を実施

---

## 10. 参考資料

- [25_6_1_docker_entrypoint_not_executed_analysis.v2.md](25_6_1_docker_entrypoint_not_executed_analysis.v2.md) - 問題の背景とセクション11のデバッグ提案
- [s6-overlay GitHub - Logging](https://github.com/just-containers/s6-overlay#logging)
- [execlineb documentation](https://skarnet.org/software/execline/execlineb.html)

---

## 11. アプローチ1の検証結果（2026-01-04 22:32）

### 11.1 実施した修正

`docker-entrypoint.sh` の冒頭を以下のように修正し、DevContainer を再ビルド:

```bash
# For debugging purposes, redirect stderr to a log file.
# This ensures that `set -x` output is captured without interfering with s6-overlay's stdout monitoring.
exec 2>> /tmp/entrypoint.log
set -x
```

### 11.2 検証結果

#### シンボリックリンクの状態

```bash
$ ls -l /etc/supervisor/supervisord.conf
-rw-r--r-- 1 root root 1178 Dec 28  2022 /etc/supervisor/supervisord.conf

$ ls -l /etc/process-compose/process-compose.yaml
ls: cannot access '/etc/process-compose/process-compose.yaml': No such file or directory
```

**結果**: ❌ シンボリックリンクは作成されていない

#### ログファイルの状態

```bash
$ wc -l /tmp/entrypoint.log
43 /tmp/entrypoint.log

$ tail -3 /tmp/entrypoint.log
+ '[' -e /home/hagevvashi/.claude ']'
+ echo '  Updating ownership for /home/hagevvashi/.claude'
++ id -u
++ id -g
+ sudo chown -R 501:20 /home/hagevvashi/.claude
```

**結果**: ❌ ログは Phase 1 の途中（43行目）で終了。`exec 2>>` 修正前（55行目）よりさらに短くなった。

#### サービスの起動状態

```bash
$ ps aux | grep -E "(supervisord|process-compose)" | grep -v grep
hagevva+    29  0.0  0.0    220    80 ?        S    22:32   0:00 s6-supervise supervisord
hagevva+    30  0.0  0.0    220    80 ?        S    22:32   0:00 s6-supervise process-compose
hagevva+  7337  100  0.2  37992 27064 ?        Rs   22:39   0:00 /usr/bin/python3 /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
```

**結果**:
- ✅ supervisord プロセスは起動している（ただし CPU 100%で異常）
- ❌ process-compose プロセスは起動していない

### 11.3 分析

1. **アプローチ1は効果がなかった**: `exec 2>> /tmp/entrypoint.log` への変更では、問題は解決しなかった。むしろログがさらに短くなった。

2. **リダイレクトの種類は問題ではない**: `exec >` も `exec 2>>` も同様に失敗することから、**exec によるリダイレクト自体が s6-overlay の oneshot サービスと互換性がない**可能性が高い。

3. **supervisord は独立して起動する**: docker-entrypoint とは別に、s6-overlay の longrun サービスとして supervisord は起動する。ただし、シンボリックリンクが作成されていないため、古い設定ファイルを読み込んでいる可能性がある（CPU 100%の異常状態）。

### 11.4 新たな仮説

**execlineb の厳格な実行制御が、bash の exec ビルトインコマンドと衝突している可能性**

`.devcontainer/s6-rc.d/docker-entrypoint/up` は以下の通り:

```bash
#!/command/execlineb -P
/usr/local/bin/docker-entrypoint.sh
```

execlineb は、実行するプログラム（docker-entrypoint.sh）の標準入出力を厳格に管理する。しかし、docker-entrypoint.sh 内で `exec 2>>` を使用すると、bash が自身のファイルディスクリプタを変更しようとし、execlineb の管理下から逸脱する可能性がある。

---

## 12. 次のアプローチ: アプローチ3（リダイレクト完全削除）の実施

### 12.1 方針

exec リダイレクトを完全に削除し、s6-overlay の標準的なログメカニズムを活用する。

### 12.2 実施内容

1. **docker-entrypoint.sh からリダイレクトを削除**:
   ```bash
   # 削除する行
   # exec 2>> /tmp/entrypoint.log
   # set -x
   ```

2. **s6-overlay のログを確認する方法を調査**:
   - `docker logs <container>` で標準出力を確認
   - `/run/s6/` 配下のログディレクトリを探索

3. **デバッグ情報は echo で明示的に出力**:
   - 各 Phase の開始/終了を echo で出力
   - 重要な変数値を echo で出力

### 12.3 期待される結果

- docker-entrypoint.sh が最後まで実行される
- シンボリックリンクが正しく作成される
- `docker logs` または s6-overlay ログに Phase 1-6 のすべての出力が記録される

---

## 13. 教訓（暫定）

### 13.1 exec リダイレクトと execlineb の非互換性

bash の `exec` ビルトインコマンドによるリダイレクトは、execlineb の実行環境では使用すべきではない。execlineb は、起動するプログラムの標準入出力を厳格に制御するため、プログラム内部での exec リダイレクトが予期しない動作を引き起こす。

### 13.2 s6-overlay でのデバッグ手法

s6-overlay 環境では、以下のデバッグ手法を採用すべき:
1. **リダイレクトを使用しない**: 標準出力/標準エラー出力をそのまま使用
2. **docker logs を活用**: コンテナのログから実行結果を確認
3. **明示的な echo**: 各処理の開始/終了を echo で出力
4. **set -x は使用しない**: トレースログは execlineb 環境では不要かつ有害の可能性

---

**次のアクション**: docker-entrypoint.sh から exec リダイレクトと set -x を完全に削除し、再ビルド・検証を実施する。

---

## 14. アプローチ3の検証結果（2026-01-04 22:53）

### 14.1 実施した修正

`docker-entrypoint.sh` から exec リダイレクトと set -x を完全に削除し、DevContainer を再ビルド:

```bash
#!/usr/bin/env bash

echo "=== docker-entrypoint.sh STARTED at $(date) ===" >&2

# exec 2>> /tmp/entrypoint.log  # 削除
# set -x  # 削除

set -euo pipefail
```

### 14.2 検証結果

#### シンボリックリンクの状態

```bash
$ ls -l /etc/supervisor/supervisord.conf
lrwxrwxrwx 1 root root 25 Jan  4 22:53 /etc/supervisor/supervisord.conf -> /etc/supervisor/seed.conf

$ ls -l /etc/process-compose/process-compose.yaml
lrwxrwxrwx 1 root root 79 Jan  4 22:53 /etc/process-compose/process-compose.yaml -> /home/hagevvashi/hagevvashi.info-dev-hub/workloads/process-compose/project.yaml
```

**結果**:
- ❌ supervisord.conf は seed.conf を指している（フォールバック発生）
- ✅ process-compose.yaml は正しく project.yaml を指している

#### 重要な発見

**docker-entrypoint.sh は最後まで実行されている！**

- Phase 4 (supervisord) でフォールバックが発生
- Phase 5 (process-compose) は成功
- Phase 6 まで完了

つまり、**exec リダイレクトが原因で途中終了していたわけではなく、Phase 4 の supervisord 検証で失敗していた**ことが判明。

### 14.3 Phase 4 失敗の根本原因

docker-entrypoint.sh の Phase 4 検証コード（135行目）:

```bash
if supervisord -c "${TARGET_CONF}" -t 2>&1; then
```

このコマンドを手動で実行すると:

```bash
$ supervisord -c /home/hagevvashi/hagevvashi.info-dev-hub/workloads/supervisord/project.conf -t
Error: Can't drop privilege as nonroot user
For help, use /usr/bin/supervisord -h
```

**問題**: `supervisord -t` (検証モード) は root 権限が必要だが、コマンドに `sudo` が付いていない。

docker-entrypoint.sh は非 root ユーザー（hagevvashi）として実行されるため、supervisord の検証が失敗し、フォールバックが発生していた。

### 14.4 修正案

docker-entrypoint.sh の135行目を以下のように修正:

```bash
# 修正前
if supervisord -c "${TARGET_CONF}" -t 2>&1; then

# 修正後
if sudo supervisord -c "${TARGET_CONF}" -t 2>&1; then
```

### 14.5 まとめ

1. **exec リダイレクトは赤いニシンだった**: 実際の問題は sudo の欠如
2. **docker-entrypoint.sh は正常に実行されていた**: Phase 1-6 すべて実行され、Phase 4 のみフォールバック
3. **process-compose は正常に動作**: Phase 5 の検証は成功している

---

## 15. 最終的な修正と検証計画

### 15.1 修正内容

`.devcontainer/docker-entrypoint.sh` の135行目:

```bash
if sudo supervisord -c "${TARGET_CONF}" -t 2>&1; then
```

### 15.2 検証手順

1. DevContainer を再ビルド
2. シンボリックリンクを確認:
   ```bash
   ls -l /etc/supervisor/supervisord.conf
   # 期待: -> /home/hagevvashi/hagevvashi.info-dev-hub/workloads/supervisord/project.conf
   ```
3. supervisorctl が動作することを確認:
   ```bash
   supervisorctl status
   # 期待: プロセスリストが表示される（エラーなし）
   ```

---

## 16. 教訓（最終版）

### 16.1 デバッグの罠: 早まった仮説

- 初期の仮説「docker-entrypoint.sh が実行されていない」は誤りだった
- exec リダイレクトが原因という仮説も誤りだった
- 実際の問題は単純な `sudo` の欠如だった

### 16.2 証拠ベースの分析の重要性

- シンボリックリンクの状態を正確に確認すれば、Phase 5 が成功していることから docker-entrypoint.sh が最後まで実行されていたことがわかった
- エラーメッセージを直接確認することで、権限エラーを特定できた

### 16.3 s6-overlay の実行環境

- s6-overlay の oneshot サービスは、bash の exec リダイレクトに関係なく正常に動作する
- 問題は s6-overlay ではなく、スクリプト内部のロジックにあった

---

**次のアクション**: docker-entrypoint.sh の135行目に `sudo` を追加し、再ビルド・検証を実施する。

---

## 17. Geminiによる客観的レビューとツッコミ（2026-01-04）

Claudeによるセクション14の根本原因分析（`supervisord -t`実行時の`sudo`欠如）は、提示された証拠に基づき論理的かつ妥当である。

ここでは、より高い視点から「`docker-entrypoint.sh`における`sudo`の利用は果たして正しい姿なのか？」という問いについて客観的なレビューを行う。

### `sudo`利用の妥当性評価

`docker-entrypoint.sh`における`sudo`の使われ方は、以下の3つに分類できる。

#### 1. Phase 4/5の`sudo`（シンボリックリンクと検証）: **妥当**

- **内容**: `sudo ln -sf` による `/etc` 配下へのシンボリックリンク作成と、`sudo supervisord -t` による検証。
- **評価**: `/etc` のようなシステムディレクトリへの書き込みには `root` 権限が必須。また、`supervisord` の検証プロセスが `root` を要求する仕様であるため、ここでの `sudo` の利用は**設計上やむを得ず、妥当**である。

#### 2. Phase 1の`sudo`（ホームディレクトリ内の所有者変更）: **条件付きで許容**

- **内容**: `sudo chown` による `~/.config` 等の所有者変更。
- **評価**: これはDocker開発で頻発する「ホストとコンテナのUID/GID不整合」問題に対する**一般的なワークアラウンド（回避策）**である。本来はコンテナビルド時にUID/GIDをホストに合わせることで防ぐべきだが、運用上発生しうる不整合をエントリーポイントで強制的に修正することは、開発環境の安定性を高める上で**現実的かつ許容可能な対策**と言える。

#### 3. Phase 2の`sudo`（Dockerソケットのパーミッション変更）: **再検討を強く推奨**

- **内容**: `sudo chmod 666 /var/run/docker.sock`
- **評価**: これは**重大なセキュリティリスク**を伴う。Dockerソケットへの書き込み権限は、実質的にホストOSのroot権限を掌握できることと同義である。開発環境の利便性のためとはいえ、この方法は避けるべき「アンチパターン」である。
- **代替案**: よりセキュアな方法として、**コンテナ内の`docker`グループのGIDを、ホスト側のDockerソケットのGIDに動的に合わせる**アプローチがある。具体的には、エントリーポイント内でホストのDockerソケットのGIDを`stat`コマンドで取得し、コンテナ内の`docker`グループのGIDを`groupmod`でそれに変更する。これにより、パーミッションを危険な`666`にすることなく、コンテナ内のユーザーがDockerコマンドを実行できるようになる。
- **結論**: この`sudo chmod`は**「正しい姿」とは言えず、将来的に修正すべき技術的負債**である。

### 総括

Claudeが特定した`sudo`の欠如というバグの修正は正しい。しかし、同時にPhase 2で使われている`sudo chmod 666`は、より安全な方法で置き換えることを強く推奨する。今回の修正と並行して、このセキュリティ改善を今後のタスクとして起票すべきである。

---

## 18. Geminiによる追加調査と修正（2026-01-04）

セクション17でレビューした`sudo`追加の修正後もコンテナが`unhealthy`となる問題が継続したため、`docker logs`を基に追加調査と修正を実施した。

### 18.1 仮説

`docker logs` の出力結果を分析したところ、以下の2つの異なるエラーが繰り返し発生していることが判明した。

1.  **`supervisord` の権限エラー**: `PermissionError: [Errno 13] Permission denied: '/var/log/supervisor/supervisord.log'` が多発。`supervisord`がログファイルに書き込めず、クラッシュと再起動を繰り返している。
2.  **`process-compose` のコマンドエラー**: `Error: unknown command "/etc/process-compose/process-compose.yaml"` が多発。`process-compose`の起動コマンドの引数が誤っている。

これらのプロセスが正常に起動しないことが、コンテナが `unhealthy` となる直接の原因であると仮説を立てた。

### 18.2 調査

上記仮説に基づき、関連する設定ファイルを調査した。

1.  **`supervisord` の設定調査**:
    *   `workloads/supervisord/project.conf` を確認したところ、ログで示唆された別の問題を発見した。ファイル内に `[program:docker-entrypoint]` セクションが存在していた。
    *   **原因特定**: s6-overlayがコンテナ初期化のために `docker-entrypoint.sh` を一度実行した後、プロセス管理デーモンである `supervisord` が、この設定に基づき `docker-entrypoint.sh` を再度プロセスとして起動しようとしていた。この**二重実行**が、権限エラーを含む予期せぬ動作の根本原因であると特定した。

2.  **`process-compose` の設定調査**:
    *   `.devcontainer/s6-rc.d/process-compose/run` ファイルを確認した。
    *   **原因特定**: 起動コマンドが `exec /usr/local/bin/process-compose -config /etc/process-compose/process-compose.yaml` となっていた。`process-compose` の正しいコマンドラインフラグは `-f` であり、`-config` は不正なフラグであった。

### 18.3 修正

上記調査に基づき、以下の2点の修正を実施した。

1.  **エントリーポイントの二重実行の解消**:
    *   **ファイル**: `workloads/supervisord/project.conf`
    *   **内容**: `[program:docker-entrypoint]` セクション全体を削除した。これにより、`docker-entrypoint.sh` は s6-overlay によってコンテナ起動時に一度だけ実行されるようになった。

2.  **`process-compose` 起動コマンドの修正**:
    *   **ファイル**: `.devcontainer/s6-rc.d/process-compose/run`
    *   **内容**: `exec` 行の `-config` フラグを正しい `-f` に修正した。

### 18.4 結論

これらの修正により、`supervisord` と `process-compose` が正常に起動し、コンテナが `healthy` 状態に移行することが期待される。次のステップは、再度DevContainerを再ビルドし、コンテナの状態を検証することである。

---

## 18. セクション15.2の検証結果（2026-01-04 23:24）

### 18.1 実施した検証

DevContainerを再ビルド後、以下の検証を実施:

#### 1. シンボリックリンクの確認

```bash
$ ls -l /etc/supervisor/supervisord.conf
lrwxrwxrwx 1 root root 75 Jan  4 23:10 /etc/supervisor/supervisord.conf -> /home/hagevvashi/hagevvashi.info-dev-hub/workloads/supervisord/project.conf

$ ls -l /etc/process-compose/process-compose.yaml
ls: cannot access '/etc/process-compose/process-compose.yaml': No such file or directory

$ ls -la /etc/process-compose/
total 16
drwxr-xr-x 1 root root 4096 Jan  4 23:07 .
drwxr-xr-x 1 root root 4096 Jan  4 23:10 ..
-rw-r--r-- 1 root root   30 Jan  4 07:46 seed.yaml
```

**結果**:
- ✅ supervisord.conf は正しく project.conf を指している（sudo修正が成功）
- ❌ process-compose.yaml のシンボリックリンクが作成されていない

#### 2. supervisord サービスの状態確認

```bash
$ ps aux | grep supervisord
hagevva+    29  0.0  0.0    220    80 ?        S    23:10   0:00 s6-supervise supervisord
root       324  0.0  0.0   5828  3480 ?        S    23:10   0:00 sudo supervisord -c /etc/supervisor/supervisord.conf -t
root       325  0.0  0.2  41328 30476 ?        S    23:10   0:00 /usr/bin/python3 /usr/bin/supervisord -c /etc/supervisor/supervisord.conf -t

$ /command/s6-svstat /run/service/supervisord
down (exitcode 2) 0 seconds, normally up, want up, ready 0 seconds
```

**結果**:
- ❌ supervisord サービスは down 状態（exitcode 2）
- 実行中のプロセスは検証モード（`-t` フラグ付き）のものであり、これはdocker-entrypoint.shからの検証コマンド

#### 3. supervisorctl による動作確認

```bash
$ supervisorctl status
error: <class 'PermissionError'>, [Errno 13] Permission denied: file: /usr/lib/python3/dist-packages/supervisor/xmlrpc.py line: 557
```

**結果**: supervisord サービスが起動していないため、supervisorctl もエラー

### 18.2 根本原因の特定

supervisord を手動で起動してみると:

```bash
$ sudo /usr/bin/supervisord -c /etc/supervisor/supervisord.conf -n
Traceback (most recent call last):
  File "/usr/bin/supervisord", line 33, in <module>
    sys.exit(load_entry_point('supervisor==4.2.5', 'console_scripts', 'supervisord')())
  File "/usr/lib/python3/dist-packages/supervisor/supervisord.py", line 359, in main
    go(options)
  File "/usr/lib/python3/dist-packages/supervisor/supervisord.py", line 369, in go
    d.main()
  File "/usr/lib/python3/dist-packages/supervisor/supervisord.py", line 72, in main
    self.options.make_logger()
  File "/usr/lib/python3/dist-packages/supervisor/options.py", line 1488, in make_logger
    loggers.handle_file(
  File "/usr/lib/python3/dist-packages/supervisor/loggers.py", line 417, in handle_file
    handler = FileHandler(filename)
  File "/usr/lib/python3/dist-packages/supervisor/loggers.py", line 160, in __init__
    self.stream = open(filename, mode)
OSError: [Errno 6] No such device or address: '/dev/stdout'
```

**問題点**:

`workloads/supervisord/project.conf` の13行目に以下の設定がある:

```ini
[supervisord]
logfile=/dev/stdout
```

s6-overlay の execlineb 実行環境では、`/dev/stdout` が正常に動作しない。これが supervisord サービスが exitcode 2 で終了する原因。

### 18.3 process-compose シンボリックリンクの問題

docker-entrypoint.sh の Phase 5 では以下のようにシンボリックリンクを作成しているはずだが:

```bash
sudo ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"
```

実際にはシンボリックリンクが作成されていない。これは:

1. docker-entrypoint.sh の実行タイミングの問題、または
2. Phase 5 の検証ロジックに問題がある可能性

### 18.4 次のアクション

#### 優先度1: supervisord の `/dev/stdout` 問題の解決

**アプローチA（推奨）**: ログファイルパスを実ファイルに変更

```ini
# 修正前
logfile=/dev/stdout

# 修正後
logfile=/var/log/supervisord/supervisord.log
```

**アプローチB**: s6-overlay 用の execlineb ラッパーを使用して `/dev/stdout` を扱えるようにする（複雑）

#### 優先度2: process-compose シンボリックリンク問題の調査

docker-entrypoint.sh が Phase 5 でどのような動作をしたか、ログを確認する必要がある。

---

## 19. まとめ（暫定）

### 19.1 解決した問題

✅ セクション15で修正した sudo の追加により、supervisord.conf のシンボリックリンクが正しく project.conf を指すようになった

### 19.2 新たに発見した問題

❌ **問題1**: supervisord サービスが起動しない
- 原因: `project.conf` の `logfile=/dev/stdout` が s6-overlay 環境で動作しない
- 影響: supervisord で管理されるべきプロセス（code-server等）が起動していない

❌ **問題2**: process-compose.yaml のシンボリックリンクが作成されていない
- 原因: 不明（docker-entrypoint.sh Phase 5 の動作を要調査）

### 19.3 次のステップ

1. supervisord の logfile 設定を実ファイルパスに変更
2. docker-entrypoint.sh の実行ログを確認して process-compose シンボリックリンクが作成されない原因を特定
3. 修正後に全体の統合検証を実施
