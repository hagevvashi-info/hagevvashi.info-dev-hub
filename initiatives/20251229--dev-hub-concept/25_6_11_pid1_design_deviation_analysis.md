# PID 1設計乖離問題の分析: supervisordがPID 1として動作している

**作成日**: 2026-01-09
**発見経緯**: Dockerfile と docker-entrypoint.sh のレビュー
**影響範囲**: プロセス管理設計全体

---

## 1. 背景

### 1.1 プロジェクトの目標

**initiatives/20251229--dev-hub-concept** における「Monolithic DevContainer」プロジェクトでは、以下の設計思想が確立されている：

- **v10設計** (25_0_process_management_solution.v10.md)で、s6-overlayをPID 1として採用
- **s6-overlay**がコンテナの初期化とプロセス監視を担当
- **supervisord**と**process-compose**はs6-overlay配下のlongrunサービスとして動作
- **docker-entrypoint.sh**はs6-overlay配下のoneshotサービスとして初期化処理を実行

### 1.2 設計ドキュメントで確立された構造

**25_0_process_management_solution.v10.md**（2026-01-04作成）より:

```
┌─────────────────────────────────────────────┐
│           s6-overlay (PID 1)                │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ docker-entrypoint (oneshot)         │   │
│  │ - Phase 1-5の初期化処理             │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ supervisord (longrun)               │   │
│  │ - code-server 管理                  │   │
│  │ - Web UI (port 9001)                │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ process-compose (longrun)           │   │
│  │ - TUI プロセス管理                  │   │
│  │ - Web UI (port 8080)                │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**期待される起動フロー**:

1. Dockerコンテナ起動
2. `/init` (s6-overlay) がPID 1として起動
3. s6-overlayが`docker-entrypoint`をoneshotサービスとして実行
4. `docker-entrypoint`完了後、s6-overlayが`supervisord`と`process-compose`をlongrunサービスとして起動
5. s6-overlayがすべてのプロセスを監視

---

## 2. 問題: 現在のDockerfileとdocker-entrypoint.sh

### 2.1 Dockerfileの実装（line 299）

```dockerfile
# ENTRYPOINTを最後に設定（ユーザー切り替え後）
# これにより、コンテナ起動時のデフォルトユーザーがhagevvashiになる
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# s6-overlay を PID 1 として起動
# s6-overlay が docker-entrypoint, supervisord, process-compose を管理
```

**問題点1**: ENTRYPOINTが`/usr/local/bin/docker-entrypoint.sh`を指している
- v10設計では`/init`であるべき

**問題点2**: コメントが矛盾している
- Line 301-302のコメントは「s6-overlayがPID 1」と記載
- しかし実際のENTRYPOINTは`docker-entrypoint.sh`

### 2.2 docker-entrypoint.shの実装（line 228-229）

```bash
# supervisordをフォアグラウンドで起動（PID 1として実行）
exec sudo supervisord -c "${TARGET_CONF}" -n
```

**問題点3**: supervisordがPID 1として起動している
- `exec`により、`docker-entrypoint.sh`のプロセスを`supervisord`で置き換え
- 結果として、`supervisord`がPID 1となる
- s6-overlayは完全にバイパスされる

### 2.3 実際の起動フロー

**現在の実装における実際の動作**:

1. Dockerコンテナ起動
2. `/usr/local/bin/docker-entrypoint.sh` がPID 1として起動
3. Phase 1-5の初期化処理を実行
4. Phase 6で`exec sudo supervisord`により、プロセスをsupervisordで置き換え
5. **supervisordがPID 1として動作**
6. s6-overlayは一切関与しない

**s6-overlayは完全に無視されている**。

---

## 3. 原因

### 3.1 直接的原因

**ENTRYPOINTの設定ミス**:
- Dockerfile line 299で`ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]`と設定
- v10設計では`ENTRYPOINT ["/init"]`であるべき

**docker-entrypoint.shの役割の混乱**:
- v10設計では、`docker-entrypoint.sh`はs6-overlayのoneshotサービスとして動作すべき
- しかし現在の実装では、PID 1として起動し、最終的にsupervisordを直接起動

### 3.2 設計進化の過程での混乱

**設計の変遷**:

1. **25_6_6（2026-01-04）**: docker-entrypoint.shがsupervisordを起動する設計
   - この時点では、s6-overlayはまだ統合されていない可能性

2. **25_6_7（2026-01-04）**: sudo削除問題の分析
   - docker-entrypoint.shがrootで実行されることを前提に、sudoを削除
   - しかし、s6-overlay統合については言及なし

3. **25_6_10（2026-01-08）**: ユーザー切り替え問題の分析
   - ENTRYPOINTをUSER後に移動する提案
   - しかし、s6-overlayを考慮していない

**推測される原因**:
- v10設計（2026-01-04作成）が策定された後、実装が追いついていない
- または、25_6シリーズの問題解決時に、v10設計を見落とした

### 3.3 ドキュメントと実装の乖離

**設計ドキュメント（v10）**: s6-overlayをPID 1として使用
**実装（Dockerfile + docker-entrypoint.sh）**: supervisordをPID 1として使用

この乖離は、以下のリスクを引き起こす:
- プロセス管理の堅牢性が損なわれる（s6-overlayの利点が失われる）
- ゾンビプロセスの発生リスク
- graceful shutdownの問題
- プロセス監視・再起動機能の欠如

---

## 4. 仮説

### 仮説1: v10設計策定後、実装が未完了

**仮説内容**:
v10設計は2026-01-04に策定されたが、その後25_6_6〜25_6_10のトラブルシューティングに注力し、s6-overlay統合の実装が後回しになった。

**根拠**:
- 25_6_6でsudo問題を修正
- 25_6_7でsudo削除を実施
- 25_6_10でユーザー切り替え問題を分析
- これらの修正では、s6-overlayへの言及がない

**検証方法**:
- 25_4_2_v10_implementation_tracker.mdを確認
- s6-overlay統合のタスクが「未完了」または「未着手」となっているか確認

### 仮説2: s6-overlayインストールは完了したが、ENTRYPOINTの切り替えを忘れた

**仮説内容**:
Dockerfileでs6-overlayのインストールは実施したが、ENTRYPOINTを`/init`に変更する作業を忘れた。

**根拠**:
- Dockerfile line 90-110でs6-overlayをインストール済み
- Dockerfile line 301-302のコメントは「s6-overlayがPID 1」と記載
- しかしENTRYPOINTは`docker-entrypoint.sh`のまま

**検証方法**:
- `.devcontainer/s6-rc.d/`ディレクトリが存在するか確認
- s6-overlayのサービス定義ファイル（`docker-entrypoint/up`, `supervisord/run`等）が存在するか確認

### 仮説3: 意図的にsupervisordをPID 1として使用している（v10設計を変更した）

**仮説内容**:
何らかの理由（例: s6-overlayの複雑性、デバッグの困難さ）により、v10設計を放棄し、supervisordをPID 1として使用する方針に変更した。

**根拠**:
- docker-entrypoint.sh line 228のコメント「supervisordをフォアグラウンドで起動（PID 1として実行）」は明示的

**検証方法**:
- 25_4_2_v10_implementation_tracker.mdに「v10設計を変更」という記載があるか確認
- 最新のドキュメントに「supervisordをPID 1として使用」という記載があるか確認

---

## 5. 検証方法

### 検証1: s6-overlay統合の実装状況確認

```bash
# s6-rc.d ディレクトリが存在するか確認
ls -la .devcontainer/s6-rc.d/

# サービス定義ファイルが存在するか確認
find .devcontainer/s6-rc.d/ -type f
```

**期待結果**:
- `.devcontainer/s6-rc.d/docker-entrypoint/`ディレクトリが存在
- `.devcontainer/s6-rc.d/supervisord/`ディレクトリが存在
- `.devcontainer/s6-rc.d/process-compose/`ディレクトリが存在

### 検証2: 実装トラッカー確認

```bash
# 25_4_2_v10_implementation_tracker.md を確認
cat initiatives/20251229--dev-hub-concept/25_4_2_v10_implementation_tracker.md
```

**期待結果**:
- s6-overlay統合タスクの状態が明記されている

### 検証3: 実際のコンテナでのPID 1確認

```bash
# コンテナ起動
docker compose -f .devcontainer/docker-compose.yml up -d

# PID 1を確認
docker exec -it <container-name> ps aux | head -n 2
```

**期待結果**（v10設計準拠の場合）:
```
PID   USER     COMMAND
1     root     s6-svscan
```

**実際の結果**（現在の実装）:
```
PID   USER     COMMAND
1     root     supervisord
```

---

## 6. 次のアクション（仮説立案モード）

このドキュメントは**mode-1: 仮説立案モード**で作成されたため、**ファイルの変更は行いません**。

### 推奨する次のステップ

1. **検証1-3を実施**して、仮説1-3のどれが正しいか確認
2. **25_4_2_v10_implementation_tracker.md**を確認し、s6-overlay統合の進捗を把握
3. **ユーザーと相談**して、以下のどちらかを選択:
   - **選択肢A**: v10設計を維持し、s6-overlay統合を完了させる（推奨）
   - **選択肢B**: v10設計を変更し、supervisordをPID 1として正式に採用する

### 推奨: 選択肢A（v10設計の完全実装）

**理由**:
- s6-overlayは既にインストール済み（Dockerfile line 90-110）
- v10設計は詳細に策定されている
- PID 1保護とプロセス監視の利点が大きい

**必要な作業**:
1. ENTRYPOINTを`/init`に変更
2. `.devcontainer/s6-rc.d/`にサービス定義を作成
3. `docker-entrypoint.sh`をoneshotサービスとして実装
4. `supervisord`と`process-compose`をlongrunサービスとして実装

---

**このドキュメントは、Dockerfileとdocker-entrypoint.shの実装がv10設計と乖離していることを分析し、3つの仮説を立てるものです。次のステップとして、検証を実施し、適切な対応策を決定する必要があります。**
