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
