# プロセス管理ツール選定分析（改訂版）

**作成日**: 2026-01-02
**最終更新**: 2026-01-02
**関連ドキュメント**:
- [25_0_systemd_process_management_proposal.md](25_0_systemd_process_management_proposal.md) - systemd導入提案（原案）
- [25_1_systemd_process_management_proposal_fb_by_gemini.md](25_1_systemd_process_management_proposal_fb_by_gemini.md) - Geminiによるフィードバック

## 概要

当初はsystemd導入を提案し、Geminiからprocess-composeを推奨されました。しかし、議論を深める中で**本当に必要な要件**が明確になりました。このドキュメントでは、実際のニーズに基づいてプロセス管理ツールを再選定します。

---

## 本当に必要な要件（再定義）

### 議論の中で明確になった3つの要件

1. **PID 1 が特定のプロセス（code-server）に専有されているのが気持ち悪い**
   - code-serverは「開発環境の一部」であって「コンテナの主役」ではない
   - PID 1 = プロセス管理ツールにすべき

2. **ログは見やすくしたい**
   - デバッグしやすい環境が重要
   - エラーログが明確に見える

3. **できればWebでプロセスモニタリング**
   - TUIよりWebの方が便利
   - ブラウザで確認できる方が理想的

### 不要な要件（過剰設計だった部分）

1. ❌ **自動再起動**
   - 開発環境ではエラーを見たい
   - 自動再起動 → エラーログが流れて見えない
   - 手動起動 → エラーが明確に見える

2. ❌ **依存関係管理**
   - 開発者が起動順序を理解すべき
   - systemdで自動管理 → ブラックボックス化
   - 手動で起動順序制御 → 依存関係を理解できる

3. ❌ **「本番環境との一致」**
   - Monolithic DevContainerは開発環境特化
   - 本番（Kubernetes）とは構造が異なる
   - どのツールを使っても本番とは一致しない

---

## プロセス管理ツールの選択肢

### 比較表: 本当に必要な要件に基づく評価

| ツール | PID 1問題解決 | 複数プロセス | ログ見やすさ | **Webモニタリング** | 学習コスト | 実績 | 特権モード |
|--------|------------|------------|------------|------------------|----------|------|----------|
| **tini** | ✅ | ❌ | － | ❌ | ⭐⭐⭐ | ⭐⭐⭐ | ✅ 不要 |
| **s6-overlay** | ✅ | ✅ | ⭐⭐ | ❌ | ⭐ | ⭐⭐⭐ | ✅ 不要 |
| **process-compose** | ✅ | ✅ | ⭐⭐⭐ TUI | ⚠️ API提供のみ | ⭐⭐ | ⭐ | ✅ 不要 |
| **PM2** | ✅ | ✅ | ⭐⭐⭐ | ⭐⭐ PM2 Plus | ⭐⭐ | ⭐⭐⭐ | ✅ 不要 |
| **supervisord** | ✅ | ✅ | ⭐⭐⭐ | ⭐⭐⭐ **標準搭載** | ⭐⭐⭐ | ⭐⭐⭐ | ✅ 不要 |
| **systemd** | ✅ | ✅ | ⭐⭐⭐ journalctl | ❌ | ⭐ | ⭐⭐⭐ | ❌ 必要 |

### 各ツールの詳細評価

#### 1. tini（最軽量init）

**特徴**:
- PID 1用の最軽量init
- ゾンビプロセス回収が主な仕事

**判断**: ❌ **複数プロセス管理できないので不適**

---

#### 2. s6-overlay

**特徴**:
- skarnetのs6（プロセス監視ツール）のDocker用ラッパー
- LinuxServerなどの有名Dockerイメージで採用

**メリット**:
- ✅ 軽量
- ✅ 実績豊富

**デメリット**:
- ❌ 設定が独特（execlineb）
- ❌ Webモニタリングなし

**判断**: ⚠️ **Webモニタリングがないため、要件を満たさない**

---

#### 3. process-compose（Gemini推奨）

**特徴**:
- Go製
- docker-composeライクなYAML
- TUI標準搭載

**メリット**:
- ✅ YAML設定（親しみやすい）
- ✅ TUI（ログ見やすい）
- ✅ 特権モード不要

**デメリット**:
- ⚠️ Webモニタリングは半分（API提供、UI自作）
- ❌ 新しいツール（実績少ない）

**WebモニタリングについてUI**:
```yaml
# process-compose.yaml
# APIサーバーモード（実験的）
$ process-compose --port 8080
```
→ APIは提供されるが、Web UIは自分で作る必要あり

**判断**: ⚠️ **Webモニタリングが不完全。TUIで妥協するなら選択肢**

---

#### 4. PM2（Node.js製）

**特徴**:
- Node.js用プロセス管理ツール（任意のコマンドも管理可能）
- **Web UI標準搭載**（PM2 Plus）

**使い方**:
```javascript
// ecosystem.config.js
module.exports = {
  apps: [
    {
      name: 'code-server',
      script: 'code-server',
      args: '--bind-addr 0.0.0.0:4035 --auth password'
    },
    {
      name: 'difit',
      script: 'difit'
    }
  ]
}
```

**メリット**:
- ✅ 実績豊富
- ✅ ログ管理が強力
- ✅ Web UI（PM2 Plus）
- ✅ Node.js環境なら自然

**デメリット**:
- ⚠️ PM2 Plusのセルフホストは少し手間
- ⚠️ Node.js必須（ただし既にインストール済み）

**判断**: ⭐ **WebモニタリングありNode.js環境なら有力候補**

---

#### 5. supervisord（推奨）

**特徴**:
- Python製
- 古くからある定番
- **Web UI標準搭載**

**使い方**:
```ini
[inet_http_server]
port=*:9001
username=admin
password=admin

[supervisord]
nodaemon=true

[program:code-server]
command=code-server --bind-addr 0.0.0.0:4035 --auth password
autostart=true
autorestart=false  # 手動再起動したいのでfalse
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr

[program:difit]
command=difit
autostart=false  # 手動起動
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
```

**Webモニタリング**:
- http://localhost:9001 でアクセス
- プロセスの起動・停止・再起動をブラウザから操作可能
- ログもWeb上で見れる

**メリット**:
- ✅ **Web UI標準搭載**（要件に完全合致）
- ✅ シンプル（INI形式）
- ✅ 実績豊富（コンテナ環境での利用実績多数）
- ✅ `autorestart=false` で手動再起動可能
- ✅ ログをstdout/stderrに流せば見やすい
- ✅ 特権モード不要
- ✅ VS Code DevContainerとの相性問題なし

**デメリット**:
- ⚠️ systemdより機能は少ない → **しかし今回は不要**

**判断**: ⭐⭐⭐ **要件に最も合致。推奨**

---

#### 6. systemd（原案）

**メリット**:
- ✅ 機能豊富
- ✅ 実績豊富

**デメリット**:
- ❌ Webモニタリングなし
- ❌ 特権モード必要
- ❌ VS Code DevContainerとの相性リスク
- ❌ 今回必要な自動再起動・依存関係管理は過剰

**判断**: ❌ **要件（Webモニタリング）を満たさない。過剰設計**

---

## Geminiの指摘の再評価

### 正しかった指摘

1. ✅ **特権モードのリスク**
   - supervisordなら特権モード不要
   - systemdより安全

2. ✅ **VS Code相性のリスク**
   - supervisordならリスクなし
   - systemdは検証必要だった

3. ✅ **「本番との一致」は幻想**
   - どのツールも本番（Kubernetes）とは一致しない
   - 開発環境は開発環境として最適化すべき

### 誤っていた提案

1. ❌ **process-compose推奨**
   - TUIは確かに良いが、WebモニタリングではないWebモニタリングの方が便利
   - APIのみ提供でUI自作は手間

2. ❌ **systemdを「悪手」と断じた**
   - 確かに過剰ではあるが、「悪手」というほどではない
   - ただし今回の要件には合わない

---

## 最終推奨: supervisord

### 推奨理由

1. **要件に完全合致**
   - ✅ PID 1 問題を解決
   - ✅ 複数プロセス管理
   - ✅ ログ見やすい（stdout/stderr）
   - ✅ **Webモニタリング標準搭載**

2. **開発環境として適切**
   - ✅ `autorestart=false` で手動再起動（エラーが見える）
   - ✅ `autostart=false` で手動起動（必要なときだけ）
   - ✅ シンプルで理解しやすい

3. **リスクが低い**
   - ✅ 特権モード不要
   - ✅ VS Code DevContainerとの相性問題なし
   - ✅ 実績豊富（コンテナ環境）

4. **実装コストが低い**
   - ✅ INI形式の設定（簡単）
   - ✅ 学習コスト低い
   - ✅ イメージサイズ増加も小さい（+10-20MB）

### 他のツールとの比較

| 観点 | supervisord（推奨） | PM2 | process-compose | systemd |
|------|-------------------|-----|-----------------|---------|
| **要件充足度** | ⭐⭐⭐ 完全 | ⭐⭐⭐ 完全 | ⭐⭐ TUIのみ | ⭐⭐ Web UIなし |
| **シンプルさ** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐ |
| **実績** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐ | ⭐⭐⭐ |
| **リスク** | ⭐⭐⭐ 低い | ⭐⭐ 中程度 | ⭐⭐⭐ 低い | ⭐ 高い |
| **総合評価** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐ |

---

## 実装方針

### Phase 1: supervisord導入（推奨）

#### 実装内容

**Dockerfile**:
```dockerfile
# supervisordインストール
RUN apt-get update && \
    apt-get install -y supervisor

# 既存のツールインストール処理...

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

**supervisord.conf**:
```ini
[unix_http_server]
file=/var/run/supervisor.sock

[inet_http_server]
port=*:9001
username=admin
password=admin

[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/var/run/supervisord.pid

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

# docker-entrypoint.sh を最初に実行（初期化処理）
[program:docker-entrypoint]
command=/usr/local/bin/docker-entrypoint.sh
user=<一般ユーザー>
autostart=true
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# code-server
[program:code-server]
command=/usr/local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>
autostart=true
autorestart=false  # 手動再起動
environment=CODE_SERVER_PORT=4035
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# difit（必要なときだけ起動）
[program:difit]
command=/usr/local/bin/difit
user=<一般ユーザー>
autostart=false  # 手動起動
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

**docker-entrypoint.sh修正**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# 既存の初期化処理
# ... パーミッション修正、Docker Socket調整等 ...

# supervisordユニットとして実行される場合は、ここで終了
# （supervisordが管理するサービスとして実行されるため）
echo "✅ Docker entrypoint initialization completed"
exit 0
```

**docker-compose.yml**:
```yaml
services:
  dev:
    # 既存の設定...
    ports:
      - "4035:4035"
      - "8035:8035"
      - "8036:8036"
      - "8037:8037"
      - "8038:8038"
      - "9001:9001"  # supervisord Web UI
    # commandは削除（Dockerfileのshを使う）
```

#### 利用方法

1. **Web UIでモニタリング**
   - ブラウザで http://localhost:9001 にアクセス
   - プロセスの起動・停止・再起動をブラウザから操作
   - ログもWeb上で確認

2. **CLIでも操作可能**
   ```bash
   # コンテナ内で
   supervisorctl status        # 状態確認
   supervisorctl start difit   # difitを起動
   supervisorctl stop difit    # difitを停止
   supervisorctl restart code-server  # code-serverを再起動
   ```

---

## 次のステップ

1. **supervisord導入の実装**
   - Dockerfile修正
   - supervisord.conf作成
   - docker-compose.yml修正
   - docker-entrypoint.sh修正

2. **動作確認**
   - コンテナ起動
   - Web UI（http://localhost:9001）でプロセス確認
   - ログの視認性確認

3. **ドキュメント更新**
   - `foundations/onboarding/` にsupervisord使い方ガイド追加
   - 既存ドキュメントの更新

---

## 参考資料

- [Supervisor Documentation](http://supervisord.org/)
- [supervisord in Docker - Best Practices](https://docs.docker.com/config/containers/multi-service_container/)
- [25_0_systemd_process_management_proposal.md](25_0_systemd_process_management_proposal.md): systemd導入提案（原案）
- [25_1_systemd_process_management_proposal_fb_by_gemini.md](25_1_systemd_process_management_proposal_fb_by_gemini.md): Geminiによるフィードバック

---

## 変更履歴

### 2026-01-02 v2（改訂版）
- 議論を踏まえて全面改訂
- 本当に必要な要件を再定義
- supervisordを推奨に変更
- 不要な要件（自動再起動、依存関係管理）を削除

### 2026-01-02 v1
- 初版作成
- Geminiのフィードバックを検証
- systemd vs process-compose 比較
- systemd推奨（後に撤回）
