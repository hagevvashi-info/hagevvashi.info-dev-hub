# プロセス管理の改善提案：コンテナの世界観からの考察

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

---

## ２．原因

**PID 1としてアプリケーションプロセスを直接起動する「単一プロセスコンテナ」のパターンを採用している**

### コンテナ設計パターンの誤用

| パターン | 説明 | 適用範囲 |
|---------|------|---------|
| **単一プロセスコンテナ** | 1コンテナ＝1プロセス | マイクロサービス、ステートレスアプリ |
| **マルチプロセスコンテナ** | 1コンテナ＝複数プロセス | **開発環境**、モノリシックアプリ |

**Monolithic DevContainerは後者であるべきなのに、前者のパターンで実装されている**

---

## ３．目的（あるべき状態）

**複数のサービスを統合管理できる、真の「Monolithic DevContainer」を実現する**

### 具体的な要求

1. **複数サービスの並行稼働**
   - code-server（VSCode Server）
   - difit（開発支援ツール）
   - 各プロダクトのアプリケーションサーバー
   - バックグラウンドジョブ

2. **サービスライフサイクル管理**
   - 自動起動・自動再起動
   - 依存関係の制御（起動順序）
   - ゾンビプロセスの適切な処理

3. **コンテナの世界観との整合性**
   - 軽量であること
   - コンテナ文化のベストプラクティスに準拠
   - Kubernetes等への将来的な移行を妨げないこと

---

## ４．コンテナの世界観からの俯瞰

**参考記事**: [Docker お気に入りの init process](https://qiita.com/mumoshu/items/064cd93ce116d8e04169)

### コンテナ vs VM の根本的な違い

| 観点 | VM（Virtual Machine） | コンテナ（Container） |
|------|---------------------|-------------------|
| **思想** | OSそのものを仮想化 | **プロセス分離** |
| **PID 1の役割** | 完全なinitシステム（systemd等） | **軽量なinit process** |
| **起動対象** | 複数の常駐デーモン | **主要プロセス + 必要最小限** |
| **管理方法** | OS標準のサービス管理 | **コンテナオーケストレーション** |

### systemdの「重すぎる」問題

当初、systemdを検討しましたが、**コンテナの世界観から見ると不適切**です：

```
systemd in Docker:
- イメージサイズ: +50-100MB
- 起動時間: +3-5秒
- 複雑性: cgroup設定、特権モード等
- 思想的な乖離: コンテナ=軽量プロセス分離、systemd=完全なOS管理
```

**→ 「VM的発想」をコンテナに持ち込んでいる**

### 開発環境コンテナの特殊性

#### 通常のコンテナ（本番環境）
```
1コンテナ = 1マイクロサービス = 1主要プロセス
↓
軽量init（tini、dumb-init）で十分
```

#### 開発環境コンテナ（この設計）
```
1コンテナ = 統合開発環境 = 複数サービス
↓
プロセススーパーバイザが必要
```

**しかし、それでもコンテナの軽量性は保つべき**

---

## ５．解決策（コンテナの世界観に基づく比較）

### 解決策1: s6-overlay導入（**推奨**）

**アプローチ**: コンテナの世界観に沿った軽量プロセススーパーバイザ

#### s6-overlayとは

[s6-overlay](https://github.com/just-containers/s6-overlay)は、**コンテナ専用に設計**されたプロセススーパーバイザです：

- **軽量**: バイナリサイズ約3.4MB（systemdの1/20以下）
- **コンテナネイティブ**: Docker/Kubernetesエコシステムで広く採用
- **PID 1対応**: ゾンビプロセス回収を適切に処理
- **実績豊富**: [LinuxServer.io](https://www.linuxserver.io/)等の多数の公式イメージで採用

#### 実装イメージ

**Dockerfile**:
```dockerfile
FROM debian:12.7

ARG S6_OVERLAY_VERSION=3.1.6.2

# s6-overlayのインストール
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && \
    rm /tmp/s6-overlay-*.tar.xz

# ... 既存のツールインストール処理 ...

# s6サービス定義をコピー
COPY .devcontainer/s6-rc.d /etc/s6-overlay/s6-rc.d

# s6-overlayをPID 1として起動
ENTRYPOINT ["/init"]
```

**サービス定義例** (.devcontainer/s6-rc.d/):
```bash
# code-server/type
longrun

# code-server/run
#!/command/execlineb -P
s6-setuidgid hagevvashi
code-server --bind-addr 0.0.0.0:4035 --auth password
```

#### メリット

- ✅ **軽量**: 3.4MB（systemdの1/20）
- ✅ **コンテナネイティブ**: Docker/Kubernetes文化に適合
- ✅ **起動高速**: ほぼオーバーヘッドなし
- ✅ **複雑性低い**: cgroup設定、特権モード不要
- ✅ **実績豊富**: LinuxServer.io等で広く採用
- ✅ **複数プロセス管理**: 自動再起動、依存関係管理
- ✅ **ゾンビプロセス回収**: PID 1として適切に動作

#### デメリット

- ⚠️ **学習曲線**: s6特有の記法（execlineb）
- ⚠️ **本番との不一致**: 本番がVMでsystemdの場合（ただしコンテナ本番ならs6も選択肢）

---

### 解決策2: supervisord導入

**アプローチ**: Pythonベースの軽量プロセススーパーバイザ

#### 実装イメージ

**Dockerfile**:
```dockerfile
RUN apt-get install -y supervisor

COPY .devcontainer/supervisord.conf /etc/supervisor/conf.d/

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

**設定例**:
```ini
[supervisord]
nodaemon=true

[program:code-server]
command=/usr/local/bin/code-server --bind-addr 0.0.0.0:4035 --auth password
user=hagevvashi
autostart=true
autorestart=true
```

#### メリット

- ✅ **学習コスト低い**: INI形式の設定（最も理解しやすい）
- ✅ **軽量**: +10-20MB
- ✅ **実績豊富**: Dockerfileでの使用例多数

#### デメリット

- ⚠️ **s6-overlayより機能が劣る**: 依存関係管理が弱い
- ⚠️ **PID 1問題**: supervisord自体はPID 1を想定していない（tiniと併用推奨）

---

### 解決策3: systemd全面導入

**アプローチ**: VM的な完全なinitシステム

#### メリット

- ✅ 本番環境との完全一致（VMベースの本番の場合）
- ✅ journalctlによる統一ログ管理

#### デメリット

- ❌ **コンテナの思想と乖離**: 「軽量プロセス分離」の原則に反する
- ❌ **重い**: +50-100MB、起動+3-5秒
- ❌ **複雑**: cgroup設定、場合によっては特権モード

**→ コンテナ文化からは推奨されない**

---

### 解決策4: Docker公式の`--init`フラグ + スクリプト管理

**アプローチ**: Docker標準機能 + シンプルなスクリプト

#### 実装イメージ

**docker-compose.yml**:
```yaml
services:
  dev:
    init: true  # tiniを自動挿入
```

**docker-entrypoint.sh**:
```bash
#!/usr/bin/env bash
# バックグラウンドでdifitを起動
nohup difit > /var/log/difit.log 2>&1 &

# code-serverをフォアグラウンドで起動
exec code-server --bind-addr 0.0.0.0:4035 --auth password
```

#### メリット

- ✅ **最軽量**: 追加パッケージ不要
- ✅ **公式サポート**: Dockerの標準機能

#### デメリット

- ❌ **プロセス管理が弱い**: 自動再起動、依存関係管理なし
- ❌ **スケーラビリティ低い**: サービス追加のたびにスクリプト修正

---

## 比較表

| 観点 | s6-overlay<br>（**推奨**） | supervisord | systemd | --init |
|------|------------------------|-------------|---------|--------|
| **コンテナ思想との整合性** | ⭐⭐⭐ 完全一致 | ⭐⭐ やや適合 | ⭐ VM的発想 | ⭐⭐⭐ 適合 |
| **軽量性** | ⭐⭐⭐ 3.4MB | ⭐⭐⭐ 10-20MB | ⭐ 50-100MB | ⭐⭐⭐ 0MB |
| **起動速度** | ⭐⭐⭐ 高速 | ⭐⭐⭐ 高速 | ⭐ やや遅い | ⭐⭐⭐ 高速 |
| **複雑性** | ⭐⭐ 中程度 | ⭐⭐⭐ 低い | ⭐ 高い | ⭐⭐⭐ 低い |
| **複数プロセス管理** | ⭐⭐⭐ 完全対応 | ⭐⭐⭐ 対応 | ⭐⭐⭐ 完全対応 | ⭐ 限定的 |
| **自動再起動** | ⭐⭐⭐ 対応 | ⭐⭐⭐ 対応 | ⭐⭐⭐ 対応 | ❌ 未対応 |
| **依存関係管理** | ⭐⭐⭐ 対応 | ⭐ 限定的 | ⭐⭐⭐ 完全対応 | ❌ 未対応 |
| **コンテナ文化での実績** | ⭐⭐⭐ 豊富 | ⭐⭐⭐ 豊富 | ⭐ 限定的 | ⭐⭐⭐ 標準 |
| **学習曲線** | ⭐⭐ 中程度 | ⭐⭐⭐ 易しい | ⭐⭐ 中程度 | ⭐⭐⭐ 易しい |

---

## 推奨: s6-overlay

### 推奨理由

1. **コンテナの世界観に完全適合**
   - 軽量（3.4MB）、高速、cgroup設定不要
   - Docker/Kubernetesエコシステムで広く採用
   - コンテナ専用設計のため安定性が高い

2. **本来の目的も達成**
   - 複数プロセス管理（code-server、difit等）
   - 自動再起動、依存関係管理
   - ゾンビプロセス適切処理

3. **実績と信頼性**
   - LinuxServer.io等、多数の公式イメージで採用
   - GitHub Stars 3k+、活発な開発

4. **学習投資の価値**
   - s6はコンテナ時代のプロセス管理標準の一つ
   - Kubernetesへの移行時も知見が活きる

### systemdを選ぶべきケース

以下の場合は**systemdも選択肢**:

1. **本番がVM（非コンテナ）でsystemd管理**
   - 開発環境と本番の完全一致が最優先
   - イメージサイズ・起動時間のコストを許容

2. **チーム全員がsystemdに精通**
   - 学習コストがゼロ
   - s6の学習コストを避けたい

### supervisordを選ぶべきケース

1. **最も学習コストを下げたい**
   - INI形式の設定ファイル（最も理解しやすい）
   - s6のexeclineb記法を避けたい

---

## 意思決定のポイント

### 質問1: 本番環境はどうなっている？

- **本番がKubernetes/ECS等のコンテナオーケストレーション**
  → **s6-overlay推奨**（コンテナ文化に統一）

- **本番がVM（EC2、オンプレサーバー等）でsystemd管理**
  → **systemd検討の余地あり**（ただしコストとのトレードオフ）

### 質問2: チームのスキルセットは？

- **コンテナ文化に親和性が高い**
  → **s6-overlay推奨**

- **systemd運用経験が豊富**
  → **systemd検討の余地あり**

- **どちらも未経験**
  → **s6-overlay推奨**（コンテナ時代の標準を学ぶ）
  → または **supervisord**（最も学習コスト低い）

### 質問3: 何を最優先するか？

- **軽量性・起動速度・コンテナ文化との整合性**
  → **s6-overlay**

- **本番との完全一致**
  → **本番環境次第**

- **学習コスト最小化**
  → **supervisord**

---

## 次のアクション

### フェーズ1: 意思決定（即座）

上記の意思決定ポイントに基づき、どの解決策を採用するか決定

### フェーズ2: 検証（1-2日）

選択した解決策の動作検証
- 最小限のDockerfileで動作確認
- 既存のdocker-entrypoint.shとの統合方法確認

### フェーズ3: 実装（2-3日）

- サービス定義作成
- Dockerfile修正
- docker-compose.yml修正
- ドキュメント更新

---

## 参考資料

- [Docker お気に入りの init process](https://qiita.com/mumoshu/items/064cd93ce116d8e04169)
- [s6-overlay GitHub](https://github.com/just-containers/s6-overlay)
- [LinuxServer.io](https://www.linuxserver.io/) - s6-overlay採用の実例
- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)

---

## 変更履歴

### 2026-01-02
- 初版作成
- 当初はsystemdを推奨していたが、コンテナの世界観から見直し
- s6-overlayを新しい推奨として追加
- systemdの位置づけを「VM的アプローチ」として再定義
- 意思決定のポイントを追加
