# ユーザー切り替え問題の分析: rootログイン問題とAtuin設定エラー

**作成日**: 2026-01-08
**目的**: コンテナ起動時にrootユーザーでログインしてしまう問題と、それに伴うAtuin設定エラーを分析し、解決策を提示する

**関連ドキュメント**:
- [25_6_3_docker_entrypoint_fix_implementation_tracker.md](25_6_3_docker_entrypoint_fix_implementation_tracker.md) - セクションJ
- [25_6_7_sudo_privilege_escalation_issue_analysis.md](25_6_7_sudo_privilege_escalation_issue_analysis.md) - sudo問題の分析
- [25_6_8_current_situation_summary.md](25_6_8_current_situation_summary.md) - 現状サマリー

---

## 1. 問題の発見と症状

### 1.1 ユーザー報告

**日時**: 2026-01-08
**報告内容**:
```bash
bash: /root/.atuin/bin/env: No such file or directory
bash: /root/.atuin/bin/env: No such file or directory
root@6d2ce443203a:/home/<一般ユーザー>/<MonolithicDevContainerレポジトリ名>#
```

**問題の要約**:
- コンテナ起動時にrootユーザーでログインしている
- Atuinの設定がrootユーザー用に設定されていない
- 本来は<一般ユーザー>ユーザーでログインすべき

### 1.2 ユーザーの指摘

> もともと、ある一定の root での操作後、 UNAME に切り替えて操作してましたよね？それがなくなっていてすごく嫌です
> また、258行目以降などで su - にしているのが嫌です

**重要な指摘**:
1. 以前はrootでの操作後、適切にUNAME（<一般ユーザー>）に切り替えていた
2. 現在はその切り替えが機能していない
3. su -コマンドの使用が不適切

---

## 2. 根本原因の分析

### 2.1 Dockerfileの構造問題

現在のDockerfile（`.devcontainer/Dockerfile`）を分析した結果、以下の問題を発見：

#### 問題1: s6-overlay重複インストール

```dockerfile
# 6-27行目: 最初のs6-overlayインストール
ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz

# 280-297行目: 重複したs6-overlayインストール
ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz
```

**影響**: ビルド時間の無駄、構造の不明瞭化

#### 問題2: ENTRYPOINTとUSERディレクティブの順序

```dockerfile
# 238行目: ENTRYPOINTがUSER切り替え前に設定
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 242行目: USER切り替え（ENTRYPOINTの後）
USER ${UNAME}
WORKDIR /home/${UNAME}
```

**問題**: ENTRYPOINTはUSER切り替え前に設定されているため、rootで実行される

#### 問題3: su -コマンドの不適切な使用

```dockerfile
# 258行目以降
RUN curl -s 'https://get.sdkman.io' | bash && \
    bash -c "source /home/${UNAME}/.sdkman/bin/sdkman-init.sh && sdk install java 11.0.26-tem && sdk use java 11.0.26-tem && sdk default java 11.0.26-tem"
```

**問題**: USER切り替え後にsu -を使用する必要がない構造になっている

### 2.2 docker-entrypoint.shの実行コンテキスト

**現在の実行フロー**:
1. Dockerコンテナ起動
2. ENTRYPOINTとして `/usr/local/bin/docker-entrypoint.sh` がrootで実行
3. docker-entrypoint.sh内でPhase 1-6を実行（すべてroot権限）
4. Phase 6でsupervisordを起動（root権限）
5. supervisordがcode-serverを<一般ユーザー>ユーザーで起動

**問題**: 
- ユーザーがコンテナにログインする際、デフォルトでrootになる
- Atuinの設定は<一般ユーザー>ユーザー用に作成されているが、rootでアクセスしようとしてエラー

### 2.3 Atuin設定の問題

**Atuinインストール箇所**（Dockerfile 119-125行目）:
```dockerfile
# Atuinのインストール（システム全体にインストール）
RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh && \
    # バイナリをシステムパスに移動
    mv /root/.atuin/bin/atuin /usr/local/bin/ && \
    chmod +x /usr/local/bin/atuin && \
    # rootのAtuinディレクトリをクリーンアップ
    rm -rf /root/.atuin
```

**Atuin初期化箇所**（docker-entrypoint.sh Phase 3）:
```bash
# Phase 3: Atuin初期化
if command -v atuin >/dev/null 2>&1; then
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin
    # ... 設定ファイル作成
fi
```

**問題**: 
- Atuinバイナリはシステム全体にインストール済み
- しかし初期化（設定ファイル作成）はrootユーザーの環境で実行される
- ユーザーが<一般ユーザー>でログインした場合、設定ファイルが存在しない

---

## 3. 設計意図の推測と問題の発生経緯

### 3.1 本来の設計意図

**推測される設計**:
1. **ビルド時**: rootでシステム全体のセットアップ
2. **実行時**: ENTRYPOINTでrootとして初期化処理を実行
3. **ログイン時**: <一般ユーザー>ユーザーでログイン
4. **サービス**: supervisordが<一般ユーザー>ユーザーでアプリケーションを起動

### 3.2 問題の発生経緯

**25_6_7での変更の影響**:
- sudo削除により、docker-entrypoint.shがrootで実行されることが明確になった
- しかし、ユーザーログイン時のデフォルトユーザーは変更されていない
- 結果として、rootでログインしてしまう状況が発生

**Dockerfileの変更履歴**:
- 以前はUSER切り替えが適切に機能していた可能性
- 複数回の修正により、ENTRYPOINTとUSERの順序が逆転
- s6-overlay導入時に構造が複雑化

---

## 4. 解決策の検討

### 4.1 解決策1: ENTRYPOINTをUSER切り替え後に移動（推奨）

**アプローチ**: Dockerfileの構造を整理し、適切な順序に修正

**変更内容**:
```dockerfile
# 現在（問題のある構造）
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]  # 238行目
USER ${UNAME}                                       # 242行目

# 修正後（推奨構造）
USER ${UNAME}                                       # USER切り替えを先に
WORKDIR /home/${UNAME}
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]  # ENTRYPOINTを後に
```

**メリット**:
- ✅ シンプルで確実
- ✅ Dockerのベストプラクティスに準拠
- ✅ ユーザーログイン時のデフォルトユーザーが<一般ユーザー>になる
- ✅ 既存のdocker-entrypoint.shを大幅に変更する必要がない

**デメリット**:
- ⚠️ docker-entrypoint.shが<一般ユーザー>ユーザーで実行されるため、一部の処理でsudoが必要になる
- ⚠️ Phase 1のパーミッション修正でsudoが必要

**実装の詳細**:
1. Dockerfileの238行目のENTRYPOINTを削除
2. 242行目のUSER切り替え後にENTRYPOINTを追加
3. docker-entrypoint.shでsudoが必要な箇所を特定し、追加
4. s6-overlay重複インストールを削除

### 4.2 解決策2: docker-entrypoint.sh内でユーザー切り替えを実装

**アプローチ**: ENTRYPOINTはrootのまま、スクリプト内でユーザー切り替え

**変更内容**:
```bash
# docker-entrypoint.sh の最後に追加
echo "🔄 Switching to user ${UNAME}..."
exec su - ${UNAME} -c "bash"
```

**メリット**:
- ✅ Dockerfileの構造を大幅に変更する必要がない
- ✅ 初期化処理はroot権限で実行可能

**デメリット**:
- ❌ supervisordの起動がrootで行われるため、プロセス管理が複雑
- ❌ s6-overlayとの統合が困難
- ❌ ユーザー切り替え後のプロセス管理が不明瞭

### 4.3 解決策3: s6-overlayの設定でユーザー切り替えを実装

**アプローチ**: s6-overlayのサービス定義でユーザー切り替えを管理

**変更内容**:
```bash
# .devcontainer/s6-rc.d/supervisord/run
#!/command/with-contenv bash
exec s6-setuidgid ${UNAME} /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
```

**メリット**:
- ✅ s6-overlayの機能を活用
- ✅ プロセス管理が明確

**デメリット**:
- ❌ s6-overlayの学習コストが高い
- ❌ 複雑性が増加
- ❌ デバッグが困難

### 4.4 解決策の比較

| 観点 | 解決策1 | 解決策2 | 解決策3 |
|------|---------|---------|---------|
| **実装の簡単さ** | ✅ 高 | 🟡 中 | ❌ 低 |
| **保守性** | ✅ 高 | 🟡 中 | ❌ 低 |
| **Dockerベストプラクティス** | ✅ 準拠 | 🟡 部分的 | 🟡 部分的 |
| **既存コードへの影響** | 🟡 中 | ✅ 小 | ❌ 大 |
| **デバッグの容易さ** | ✅ 高 | 🟡 中 | ❌ 低 |
| **s6-overlay統合** | ✅ 良好 | ❌ 困難 | ✅ 良好 |

**推奨**: 解決策1（ENTRYPOINTをUSER切り替え後に移動）

---

## 5. 推奨解決策の詳細実装

### 5.1 Dockerfileの修正

#### 修正1: s6-overlay重複削除

```dockerfile
# 削除対象: 280-297行目の重複したs6-overlayインストール
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay: PID 1 保護・プロセス監視
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz

# アーキテクチャ別のバイナリ
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "x86_64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "x86_64" ;; \
    esac) && \
    curl -L "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz" \
    -o /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    rm /tmp/s6-overlay-arch.tar.xz
```

#### 修正2: ENTRYPOINTとUSERの順序修正

```dockerfile
# 修正前（238-242行目）
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 一般ユーザーに切り替え
USER ${UNAME}
WORKDIR /home/${UNAME}

# 修正後
COPY .devcontainer/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 一般ユーザーに切り替え
USER ${UNAME}
WORKDIR /home/${UNAME}

# ENTRYPOINTを最後に設定
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

#### 修正3: su -コマンドの見直し

```dockerfile
# 修正前（258行目以降）
RUN curl -s 'https://get.sdkman.io' | bash && \
    bash -c "source /home/${UNAME}/.sdkman/bin/sdkman-init.sh && sdk install java 11.0.26-tem && sdk use java 11.0.26-tem && sdk default java 11.0.26-tem"

# 修正後（USER切り替え後なのでsu -不要）
RUN curl -s 'https://get.sdkman.io' | bash && \
    bash -c "source ~/.sdkman/bin/sdkman-init.sh && sdk install java 11.0.26-tem && sdk use java 11.0.26-tem && sdk default java 11.0.26-tem"
```

### 5.2 docker-entrypoint.shの修正

#### 修正1: sudoの追加（必要箇所のみ）

```bash
# Phase 1: パーミッション修正（sudoが必要）
for item in "${CONFIG_ITEMS[@]}"; do
    if [ -e "$item" ]; then
        echo "  Updating ownership for $item"
        sudo chown -R ${UNAME}:${GNAME} "$item"  # sudo追加
    fi
done

# Phase 2: Docker Socket調整（sudoが必要）
if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock  # sudo追加
    
    if ! groups | grep -q docker; then
        sudo usermod -a -G docker ${UNAME}  # sudo追加
    fi
fi

# Phase 4, 5: シンボリックリンク作成（sudoが必要）
sudo ln -sf "${PROJECT_CONF}" "${TARGET_CONF}"  # sudo追加
sudo mkdir -p /etc/process-compose  # sudo追加
sudo ln -sf "${PROJECT_YAML}" "${TARGET_YAML}"  # sudo追加
```

#### 修正2: Atuin初期化の調整

```bash
# Phase 3: Atuin初期化（ユーザー環境で実行）
echo ""
echo "⏱️  Phase 3: Initializing Atuin configuration for user ${UNAME}..."
if command -v atuin >/dev/null 2>&1; then
    # <一般ユーザー>ユーザーの環境で初期化
    mkdir -p ~/.config/atuin
    mkdir -p ~/.local/share/atuin
    
    # 設定ファイルが存在しない場合のみデフォルト設定を作成
    if [ ! -f ~/.config/atuin/config.toml ]; then
        echo "  Creating default Atuin config for ${UNAME}..."
        cat > ~/.config/atuin/config.toml <<'EOF'
# Atuin設定ファイル（${UNAME}ユーザー用）
sync_address = ""
sync_frequency = "0"
search_mode = "fuzzy"
filter_mode = "host"
filter_mode_shell_up_key_binding = "directory"
style = "compact"
inline_height = 25
show_preview = true
show_help = true
history_filter = []
show_stats = true
timezone = "+09:00"
EOF
        echo "  ✅ Created default Atuin configuration for ${UNAME}"
    else
        echo "  ℹ️  Atuin config already exists for ${UNAME}"
    fi
fi
echo "✅ Atuin initialization complete for ${UNAME}"
```

### 5.3 検証手順

#### 検証1: ビルドの成功

```bash
cd <repo_root>/.devcontainer
docker compose --progress plain -f docker-compose.yml -f docker-compose.dev-vm.yml build --no-cache
```

**期待結果**: エラーなくビルド完了

#### 検証2: コンテナ起動

```bash
cd <repo_root>/.devcontainer
docker compose --project-name <MonolithicDevContainerレポジトリ名>_devcontainer -f docker-compose.yml -f docker-compose.dev-vm.yml up -d
```

**期待結果**: コンテナが正常起動

#### 検証3: ユーザー確認

```bash
docker exec -it <MonolithicDevContainerレポジトリ名>_devcontainer-dev-1 whoami
```

**期待結果**: `<一般ユーザー>`

#### 検証4: Atuinエラーの解消

```bash
docker exec -it <MonolithicDevContainerレポジトリ名>_devcontainer-dev-1 bash
# プロンプトでAtuinエラーが出ないことを確認
```

**期待結果**: Atuinエラーが表示されない

#### 検証5: supervisord動作確認

```bash
docker exec <MonolithicDevContainerレポジトリ名>_devcontainer-dev-1 supervisorctl status
```

**期待結果**: code-serverが正常に動作

---

## 6. リスクと緩和策

### 6.1 リスク1: docker-entrypoint.shでのsudo失敗

**リスク**: <一般ユーザー>ユーザーでsudoを実行する際、権限不足でエラー

**緩和策**:
- Dockerfileで `echo "${UNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers` が設定済み
- 事前にsudo権限を確認するテストを追加

### 6.2 リスク2: supervisordの起動失敗

**リスク**: <一般ユーザー>ユーザーでsupervisordを起動する際、権限不足

**緩和策**:
- supervisord設定でユーザー指定を明確化
- 必要に応じてs6-overlayでの権限管理を検討

### 6.3 リスク3: 既存の動作への影響

**リスク**: ユーザー切り替えにより、既存の機能が動作しなくなる

**緩和策**:
- 段階的な実装とテスト
- ロールバック手順の準備
- 詳細な検証項目の実施

---

## 7. 実装計画

### Phase 1: Dockerfile修正

1. **s6-overlay重複削除**
   - 280-297行目の重複部分を削除
   - ビルドテストで確認

2. **ENTRYPOINTとUSERの順序修正**
   - 238行目のENTRYPOINTを242行目以降に移動
   - ビルドテストで確認

3. **su -コマンドの見直し**
   - 不要なsu -コマンドを削除
   - パス指定を相対パスに修正

### Phase 2: docker-entrypoint.sh修正

1. **sudo追加**
   - Phase 1, 2, 4, 5の必要箇所にsudoを追加
   - 権限が必要な操作を特定

2. **Atuin初期化の調整**
   - ユーザー環境での初期化に変更
   - 設定ファイルパスの確認

### Phase 3: 統合テスト

1. **ビルドテスト**
   - エラーなくビルド完了することを確認

2. **ユーザー確認テスト**
   - ログイン時のデフォルトユーザーが<一般ユーザー>であることを確認

3. **Atuinテスト**
   - Atuinエラーが解消されることを確認

4. **supervisordテスト**
   - supervisordとcode-serverが正常動作することを確認

---

## 8. 成功基準

| 項目 | 成功基準 | 確認方法 |
|------|---------|---------|
| **ユーザー切り替え** | ログイン時のデフォルトユーザーが<一般ユーザー> | `docker exec -it devcontainer-dev-1 whoami` |
| **Atuinエラー解消** | bashプロンプトでAtuinエラーが表示されない | コンテナ内でbash起動 |
| **supervisord動作** | supervisorctlが正常動作 | `supervisorctl status` |
| **code-server動作** | code-serverが正常起動 | supervisorctl確認 + ポート4035アクセス |
| **docker-entrypoint実行** | Phase 1-6すべて正常実行 | `docker logs` 確認 |
| **ビルド成功** | エラーなくビルド完了 | `docker compose build --no-cache` |

---

## 9. 参考資料

### 関連ドキュメント
- [25_6_3_docker_entrypoint_fix_implementation_tracker.md](25_6_3_docker_entrypoint_fix_implementation_tracker.md) - 実装トラッカー
- [25_6_7_sudo_privilege_escalation_issue_analysis.md](25_6_7_sudo_privilege_escalation_issue_analysis.md) - sudo問題の分析
- [25_6_8_current_situation_summary.md](25_6_8_current_situation_summary.md) - 現状サマリー

### Dockerベストプラクティス
- [Docker公式ドキュメント: USER](https://docs.docker.com/engine/reference/builder/#user)
- [Docker公式ドキュメント: ENTRYPOINT](https://docs.docker.com/engine/reference/builder/#entrypoint)

### s6-overlay関連
- [s6-overlay公式ドキュメント](https://github.com/just-containers/s6-overlay)
- [s6-setuidgid](https://skarnet.org/software/s6/s6-setuidgid.html)

---

## 10. 変更履歴

### v1 (2026-01-08)
- 初版作成
- 問題の分析と解決策の検討
- 推奨解決策の詳細実装計画

---

**最終更新**: 2026-01-08
**ステータス**: 🔴 **分析完了・実装待ち**
**次のアクション**: Phase 1（Dockerfile修正）の実施
