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

## 11. 教訓

### 11.1 デバッグ手法の選択

`exec > /tmp/entrypoint.log 2>&1` のような全出力リダイレクトは、通常のシェルスクリプトでは有効だが、**s6-overlay のような特殊な実行環境では予期しない副作用を引き起こす可能性がある**。

デバッグ時は、以下を考慮すべき:
1. **最小限のリダイレクト**: 標準エラー出力のみをリダイレクト
2. **tee の活用**: 出力を複製して、元の出力先も維持
3. **段階的なテスト**: リダイレクトを無効化した状態で動作確認

### 11.2 s6-overlay の理解の深化

s6-overlay の oneshot サービスは、単純な「スクリプトを一度実行する」というものではなく、**execlineb による厳格な実行管理下にある**。標準入出力の扱いも含めて、s6-overlay の設計思想を理解する必要がある。

---

**このドキュメントは、exec リダイレクトが s6-overlay の oneshot サービス実行を妨げた問題を分析し、標準エラー出力のみをリダイレクトする修正を提案するものです。**
