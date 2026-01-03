# systemd導入によるプロセス管理の改善提案

**作成日**: 2026-01-02
**関連**: [00_Monolithic DevContainerの本質.v2.md](00_Monolithic%20DevContainerの本質.v2.md)

## １．課題（目標とのギャップ）

**現在の実装は「code-server専用コンテナ」であり、Monolithic DevContainerの本来の目的と矛盾している**

### 現状の問題

現在のDockerfile及びdocker-compose.ymlでは、**code-serverがPID 1として起動**しています：

```dockerfile
# Dockerfile (line 215-217)
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth password"]
```

```yaml
# docker-compose.yml (line 30)
command: code-server --bind-addr 0.0.0.0:4035 --auth password
```

### 具体的な問題点

1. **単一プロセス構造の制約**
   - code-serverが落ちるとコンテナ全体が停止
   - 複数サービスを同時起動できない（difit、アプリケーションサーバー等）
   - バックグラウンドプロセスの管理が困難

2. **Monolithic DevContainerの目的との矛盾**

   設計ドキュメント（[00_Monolithic DevContainerの本質.v2.md](00_Monolithic%20DevContainerの本質.v2.md)）では：

   > **Monolithic DevContainer = 「すべてをコンテナ上で開発する」**
   > 1つの「全部入り」コンテナに入れば、その中で複数プロダクトを自由に行き来できる

   しかし、現状は：
   - ❌ code-server専用コンテナのような構造
   - ❌ 複数のサービスを並行稼働できない
   - ❌ サービス間の依存関係を管理できない

3. **運用上の課題**
   - プロセスの自動起動・再起動の仕組みがない
   - ログ管理が統一されていない
   - サービスの起動順序を制御できない

### 影響範囲

- **開発効率**: 複数サービスを起動するために複雑なスクリプトが必要
- **安定性**: 一つのプロセス障害がコンテナ全体に影響
- **拡張性**: 新しいサービス追加が困難

---

## ２．原因

**PID 1としてアプリケーションプロセスを直接起動する「単一プロセスコンテナ」のパターンを採用している**

### アンチパターンの採用

現在の構造は、以下のコンテナ設計アンチパターンに該当します：

| パターン | 説明 | 適用範囲 |
|---------|------|---------|
| **単一プロセスコンテナ** | 1コンテナ＝1プロセス | マイクロサービス、ステートレスアプリ |
| **マルチプロセスコンテナ** | 1コンテナ＝複数プロセス | 開発環境、モノリシックアプリ |

**Monolithic DevContainerは後者であるべきなのに、前者のパターンで実装されている**

### 設計意図の不整合

- **設計意図**: 複数プロダクトを横断的に開発できる統合環境
- **実装**: code-server単一プロセスの専用コンテナ
- **ギャップ**: プロセス管理層が欠落している

---

## ３．目的（あるべき状態）

**複数のサービスを統合管理できる、真の「Monolithic DevContainer」を実現する**

### 具体的な要求

1. **複数サービスの並行稼働**
   - code-server（VSCode Server）
   - difit（開発支援ツール）
   - 各プロダクトのアプリケーションサーバー
   - バックグラウンドジョブ（cron的処理）

2. **サービスライフサイクル管理**
   - 自動起動・自動再起動
   - 依存関係の制御（起動順序）
   - ヘルスチェック

3. **統一的な運用インターフェース**
   - ログ管理（集約・ローテーション）
   - ステータス確認
   - サービスの起動・停止

4. **本番環境との一貫性**
   - 開発環境と本番環境で同じプロセス管理方式
   - systemdユニットファイルの知見が本番でも活きる

---

## ４．戦略・アプローチ（解決の方針）

**systemdをPID 1として採用し、複数サービスを統合管理する**

### なぜsystemdか？

| 観点 | systemd | supervisord | tmux/screen |
|------|---------|-------------|-------------|
| **複数プロセス管理** | ⭐⭐⭐ 優秀 | ⭐⭐⭐ 優秀 | ⭐ 手動管理 |
| **自動起動・再起動** | ⭐⭐⭐ 完全対応 | ⭐⭐⭐ 対応 | ❌ 未対応 |
| **依存関係管理** | ⭐⭐⭐ 完全対応 | ⭐ 限定的 | ❌ 未対応 |
| **ログ管理** | ⭐⭐⭐ journalctl | ⭐⭐ 独自 | ⭐ 限定的 |
| **本番環境との一貫性** | ⭐⭐⭐ 同一 | ⭐ 異なる | ⭐ 異なる |
| **学習曲線** | ⭐⭐ 中程度 | ⭐⭐⭐ 易しい | ⭐⭐⭐ 易しい |
| **イメージサイズ** | ⭐ 大きい | ⭐⭐⭐ 小さい | ⭐⭐⭐ 小さい |

### systemd採用の決定理由

1. **本来の目的に最も合致**
   - 複数サービスを統合管理する「Monolithic DevContainer」の思想と完全一致
   - 依存関係管理が明確（After=, Requires=）

2. **DevOps的な一貫性**
   - 本番環境でもsystemdが標準
   - 開発環境と本番環境で同じプロセス管理方式を学べる
   - systemdユニットファイルの知見が本番でも活きる

3. **拡張性**
   - 新しいサービス追加が容易（ユニットファイル追加だけ）
   - タイマー機能でcron的な処理も可能
   - socket activation等の高度な機能も利用可能

4. **運用性**
   - `systemctl status`, `journalctl` による統一的な管理
   - サービスの起動順序制御
   - 自動再起動、ログローテーション

---

## ５．解決策（最低3つ、異なる観点で比較可能なもの）

### 解決策1: systemd全面導入（推奨）

**アプローチ**: systemdをPID 1として採用し、すべてのサービスをsystemdユニットとして管理

#### 実装内容

**Dockerfile**:
```dockerfile
FROM debian:12.7

# systemdインストール
RUN apt-get update && \
    apt-get install -y systemd systemd-sysv && \
    # 不要なsystemdユニット無効化（軽量化）
    systemctl mask \
      systemd-logind.service \
      getty.target \
      systemd-remount-fs.service \
      sys-kernel-debug.mount \
      sys-kernel-tracing.mount

# ... 既存のツールインストール処理 ...

# systemdユニットファイル配置
COPY .devcontainer/systemd/code-server.service /etc/systemd/system/
COPY .devcontainer/systemd/difit.service /etc/systemd/system/
COPY .devcontainer/systemd/docker-entrypoint.service /etc/systemd/system/

# サービス有効化
RUN systemctl enable code-server.service && \
    systemctl enable difit.service && \
    systemctl enable docker-entrypoint.service

# systemdをPID 1として起動
CMD ["/lib/systemd/systemd"]
```

**systemdユニット例**:

```ini
# .devcontainer/systemd/code-server.service
[Unit]
Description=code-server - VS Code in the browser
Documentation=https://github.com/coder/code-server
After=network.target docker-entrypoint.service
Requires=docker-entrypoint.service

[Service]
Type=simple
User=hagevvashi
Group=staff
Environment="CODE_SERVER_PORT=4035"
ExecStart=/usr/local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
Restart=always
RestartSec=10

# ログ設定
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```ini
# .devcontainer/systemd/docker-entrypoint.service
[Unit]
Description=DevContainer initialization script
Before=code-server.service difit.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/docker-entrypoint.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**docker-compose.yml**:
```yaml
services:
  dev:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
      args:
        UID: ${UID:-1000}
        GID: ${GID:-1000}
        UNAME: ${UNAME:-vscode}
        GNAME: ${GNAME:-vscode}
    volumes:
      - type: bind
        source: ..
        target: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}
        consistency: cached
      - type: volume
        source: repos
        target: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}/repos
    working_dir: /home/${UNAME:-vscode}/${REPO_NAME:-dev-hub}
    ports:
      - "4035:4035"
      - "8035:8035"
      - "8036:8036"
      - "8037:8037"
      - "8038:8038"
    user: "${UID:-1000}:${GID:-1000}"
    tty: true
    # systemdを起動（特権モード不要な場合）
    tmpfs:
      - /run
      - /run/lock
      - /tmp
    # cgroup v2対応
    cgroup: host
    # または特権モード（必要な場合）
    # privileged: true
```

**docker-entrypoint.sh修正**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# 既存の初期化処理
# ... パーミッション修正、Docker Socket調整等 ...

# systemdユニットとして実行される場合は、ここで終了
# （systemdが管理するサービスとして実行されるため）
exit 0
```

#### メリット

- ✅ 複数サービスを統合管理可能
- ✅ 本番環境との一貫性（systemdスキル習得）
- ✅ 自動起動・再起動・依存関係管理が完全
- ✅ ログ管理が統一（journalctl）
- ✅ 拡張性が高い（新サービス追加が容易）
- ✅ タイマー機能でcron的処理も可能

#### デメリット

- ⚠️ イメージサイズ増加（systemd関連パッケージ）
- ⚠️ 起動時間若干増加（systemd初期化）
- ⚠️ 学習曲線（systemdユニットファイルの理解必要）
- ⚠️ 場合によっては特権モードまたはcgroup設定が必要

#### 想定される影響

- イメージサイズ: +50-100MB（既に大きいので許容範囲）
- 起動時間: +3-5秒（開発環境なので許容範囲）
- 学習コスト: 中程度（しかし本番でも活きるスキル）

---

### 解決策2: supervisord導入（軽量代替案）

**アプローチ**: supervisordをプロセス管理ツールとして採用

#### 実装内容

**Dockerfile**:
```dockerfile
FROM debian:12.7

# supervisordインストール
RUN apt-get update && \
    apt-get install -y supervisor

# ... 既存のツールインストール処理 ...

# supervisord設定配置
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

**supervisord.conf**:
```ini
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:docker-entrypoint]
command=/usr/local/bin/docker-entrypoint.sh
user=hagevvashi
autostart=true
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:code-server]
command=/usr/local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=hagevvashi
autostart=true
autorestart=true
environment=CODE_SERVER_PORT=4035
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:difit]
command=/usr/local/bin/difit
user=hagevvashi
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

#### メリット

- ✅ 軽量（systemdより小さいイメージサイズ）
- ✅ 設定がシンプル
- ✅ 複数プロセス管理可能
- ✅ コンテナ環境での実績が多い
- ✅ 特権モード不要

#### デメリット

- ❌ 本番環境との不一致（本番はsystemd）
- ❌ 依存関係管理が弱い
- ❌ systemdほど高機能ではない
- ❌ ログ管理がsystemdほど統一的でない

#### 想定される影響

- イメージサイズ: +10-20MB
- 起動時間: ほぼ変化なし
- 学習コスト: 低い

---

### 解決策3: ハイブリッドアプローチ（最小限の変更）

**アプローチ**: 現状のdocker-entrypoint.shを拡張し、バックグラウンドプロセスを起動後、code-serverをフォアグラウンドで実行

#### 実装内容

**docker-entrypoint.sh修正**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# 既存の初期化処理
# ... パーミッション修正、Docker Socket調整等 ...

# バックグラウンドでdifitを起動
if command -v difit >/dev/null 2>&1; then
    echo "Starting difit in background..."
    nohup difit > /var/log/difit.log 2>&1 &
fi

# その他のバックグラウンドサービスを起動
# ...

# code-serverをフォアグラウンドで起動（PID 1として）
exec "$@"
```

#### メリット

- ✅ 既存構造への影響が最小
- ✅ 追加パッケージ不要
- ✅ イメージサイズ・起動時間への影響なし
- ✅ 実装が単純

#### デメリット

- ❌ プロセス管理が不完全（再起動、依存関係管理がない）
- ❌ ログ管理が統一されない
- ❌ スケーラビリティが低い（サービス追加のたびにスクリプト修正）
- ❌ code-serverが落ちるとコンテナ全体が停止（根本解決にならない）

#### 想定される影響

- 既存環境への影響: 最小
- 運用性: 改善されるが不完全

---

## 比較表

| 観点 | 解決策1<br>systemd全面導入（推奨） | 解決策2<br>supervisord導入 | 解決策3<br>ハイブリッド |
|------|--------------------------------|------------------------|-------------------|
| **複数プロセス管理** | ⭐⭐⭐ 完全対応 | ⭐⭐⭐ 対応 | ⭐⭐ 限定的 |
| **自動再起動** | ⭐⭐⭐ 完全対応 | ⭐⭐⭐ 対応 | ❌ 未対応 |
| **依存関係管理** | ⭐⭐⭐ 完全対応 | ⭐ 限定的 | ❌ 未対応 |
| **ログ管理** | ⭐⭐⭐ journalctl | ⭐⭐ 独自 | ⭐ バラバラ |
| **本番環境との一貫性** | ⭐⭐⭐ 同一 | ⭐ 異なる | ⭐ 異なる |
| **学習曲線** | ⭐⭐ 中程度 | ⭐⭐⭐ 易しい | ⭐⭐⭐ 易しい |
| **イメージサイズ** | ⭐ +50-100MB | ⭐⭐⭐ +10-20MB | ⭐⭐⭐ 変化なし |
| **既存環境への影響** | ⭐⭐ 大きい | ⭐⭐ 中程度 | ⭐⭐⭐ 小さい |
| **拡張性** | ⭐⭐⭐ 高い | ⭐⭐ 中程度 | ⭐ 低い |
| **根本解決** | ⭐⭐⭐ 完全解決 | ⭐⭐⭐ 解決 | ⭐ 部分的 |

---

## 推奨: 解決策1（systemd全面導入）

### 推奨理由

1. **本来の目的に最も合致**
   - Monolithic DevContainerの思想を完全に実現
   - 複数サービスの統合管理が可能

2. **長期的な価値**
   - 本番環境との一貫性（systemdスキル習得）
   - 拡張性が高い（新サービス追加が容易）
   - 将来的なニーズ（タイマー、socket activation等）にも対応可能

3. **運用性**
   - ログ管理が統一（journalctl）
   - ステータス確認が容易（systemctl status）
   - 依存関係管理が明確

4. **DevOps文化との親和性**
   - 開発環境と本番環境で同じツール
   - Infrastructure as Codeの一環

### トレードオフの評価

**デメリット（許容可能）**:

1. **イメージサイズ増加（+50-100MB）**
   - 評価: Monolithicコンテナなので既に大きい（数GB）、許容範囲
   - 対策: 不要なsystemdユニットをmaskして軽量化

2. **起動時間増加（+3-5秒）**
   - 評価: 開発環境なので許容範囲
   - 対策: 不要なサービスを無効化して最適化

3. **学習曲線（中程度）**
   - 評価: 本番でも使うスキルなので投資価値あり
   - 対策: `foundations/onboarding/` にsystemd基本ガイドを追加

4. **cgroup設定が必要な場合がある**
   - 評価: docker-compose.ymlで `cgroup: host` 設定で対応可能
   - 対策: 必要に応じて `privileged: true` も検討

---

## 次のアクション

### Phase 1: 調査・検証（1-2日）

1. **systemd in Dockerの実現可能性検証**
   - 最小限のDockerfileでsystemdが起動するか確認
   - cgroup設定の必要性を確認
   - 既存のdocker-compose.yml設定との互換性確認

2. **既存サービスの棚卸し**
   - 現在起動すべきサービスをリストアップ
   - code-server、difit以外に必要なサービスの確認
   - 各サービスの依存関係整理

### Phase 2: 設計（2-3日）

1. **systemdユニットファイル設計**
   - code-server.service
   - difit.service
   - docker-entrypoint.service
   - その他必要なサービス

2. **Dockerfile設計**
   - systemdインストール手順
   - 不要なユニットのmask
   - 既存のツールインストール処理との統合

3. **docker-compose.yml設計**
   - cgroup設定
   - tmpfs設定
   - その他systemd稼働に必要な設定

4. **ADR作成**
   - `foundations/adr/004_systemd_process_management.md`
   - 設計判断の記録

### Phase 3: 実装（3-5日）

1. **systemdユニットファイル作成**
2. **Dockerfile修正**
3. **docker-compose.yml修正**
4. **docker-entrypoint.sh修正**
5. **ドキュメント更新**
   - `foundations/onboarding/` にsystemd基本ガイド追加
   - 既存ドキュメントの更新

### Phase 4: テスト・検証（2-3日）

1. **動作確認**
   - コンテナ起動確認
   - 各サービスの起動確認
   - ログ確認（journalctl）
   - 再起動動作確認

2. **既存機能の回帰テスト**
   - code-serverへのアクセス
   - difitの動作
   - Docker Socket経由のDocker操作
   - Git操作

3. **問題修正**

### Phase 5: ドキュメント化・展開（1-2日）

1. **最終ドキュメント作成**
   - 実装結果のまとめ
   - 運用ガイド
   - トラブルシューティング

2. **PR作成・レビュー**
3. **マージ・デプロイ**

**合計所要時間**: 9-15日

---

## 参考資料

- [systemd in Docker - Best Practices](https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container)
- [systemd.unit(5) - Manual Page](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [Docker and systemd](https://docs.docker.com/config/containers/multi-service_container/)
- [00_Monolithic DevContainerの本質.v2.md](00_Monolithic%20DevContainerの本質.v2.md): Monolithic DevContainerの設計思想
- [14_詳細設計_ディレクトリ構成.v10.md](14_詳細設計_ディレクトリ構成.v10.md): 設計v10の詳細

---

## 変更履歴

### 2026-01-02
- 初版作成
- systemd導入の課題・原因・目的・戦略・解決策を整理
- 3つの解決策（systemd、supervisord、ハイブリッド）を比較
- systemd全面導入を推奨
