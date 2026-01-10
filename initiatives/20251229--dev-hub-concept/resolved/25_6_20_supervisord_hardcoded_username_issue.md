# supervisord 設定ファイルのハードコードされたユーザー名問題

**作成日**: 2026-01-10
**目的**: `.devcontainer/supervisord/` 配下の設定ファイルにハードコードされたユーザー名 `<一般ユーザー>` を環境変数化し、他のユーザーでも使用可能にする

**関連ドキュメント**:
- `25_6_12_v10_completion_implementation_tracker.md` - 実装トラッカー
- `25_0_process_management_solution.v10.md` - v10設計

---

## 1. 問題の発見

**ユーザーからの指摘**:
> ".devcontainer/supervisord/seed.conf .devcontainer/supervisord/supervisord.conf これらのファイルに「hagevvashi」というユーザー名がハードコードされているの、絶対にやめたいのです これほかのユーザーで使えないから。それともダミーだから大丈夫？それならそれでダミーとわかる名前にしてほしいです"

**発見日時**: 2026-01-10T10:00:00+09:00

---

## 2. 現状分析

### 2.1 影響を受けるファイル

#### `.devcontainer/supervisord/seed.conf`

**ハードコードされている箇所**:

**Line 76, 81**:
```ini
[program:code-server]
command=code-server --bind-addr 0.0.0.0:4035 --auth password
user=<一般ユーザー>                                              # ← ハードコード
autostart=true
autorestart=false
priority=10
environment=CODE_SERVER_PORT="4035",HOME="/home/<一般ユーザー>" # ← ハードコード
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

**ファイルの役割**:
- **ビルド時検証用スタブ**: Dockerfile の `supervisord -t` による構文チェック
- **フォールバック機構（最重要）**: `workloads/supervisord/project.conf` の読み込み失敗時に自動的に使用される安全装置
- **セーフモード提供**: 構文エラーや削除があってもコンテナを起動可能に保つ
- **最小限の開発環境**: code-server を起動し、ブラウザ経由で問題修正を可能にする

---

#### `.devcontainer/supervisord/supervisord.conf`

**ハードコードされている箇所**:

**Line 12, 14, 22, 24**:
```ini
[program:process-compose]
command=process-compose -f /etc/process-compose/project.yaml
autostart=true
autorestart=true
user=<一般ユーザー>                      # ← ハードコード
priority=20
environment=HOME="/home/<一般ユーザー>"  # ← ハードコード
stdout_logfile=/var/log/supervisor/process-compose.log
stderr_logfile=/var/log/supervisor/process-compose.err

[program:code-server]
command=code-server --bind-addr 0.0.0.0:4035
autostart=true
autorestart=true
user=<一般ユーザー>                      # ← ハードコード
priority=20
environment=HOME="/home/<一般ユーザー>"  # ← ハードコード
stdout_logfile=/var/log/supervisor/code-server.log
stderr_logfile=/var/log/supervisor/code-server.err
```

**ファイルの役割**:
- **s6-overlay サービス定義の一部**: `.devcontainer/s6-rc.d/supervisord/run` から参照される
- **実行時設定**: 実際に supervisord が起動時に読み込む設定（`/etc/supervisor/conf.d/supervisord.conf` にコピーされる）
- **v10設計の一部**: s6-overlay → supervisord → code-server/process-compose の階層構造

---

### 2.2 問題の影響範囲

**影響度**: 🔴 **高** - 他のユーザーがこのリポジトリを使用できない

**具体的な問題**:
1. ❌ 他のユーザー（例: `alice`）が同じ設定を使用しても、`<一般ユーザー>` ユーザーとして code-server が起動してしまう
2. ❌ `/home/<一般ユーザー>` が存在しない環境では起動失敗する可能性
3. ❌ 汎用的な DevContainer として配布・共有できない

---

## 3. 解決策の選択肢

### 選択肢1: 環境変数化（第一推奨）

**概要**: `${UNAME}` 環境変数を使用して動的に設定

**修正後の設定例**:
```ini
[program:code-server]
user=%(ENV_UNAME)s
environment=HOME="/home/%(ENV_UNAME)s"
```

**メリット**:
1. ✅ **汎用性**: どのユーザーでも使用可能
2. ✅ **保守性**: ユーザー名変更時に設定ファイル修正不要
3. ✅ **一貫性**: 既存の `${UNAME}` 変数と統一

**デメリット**:
1. ⚠️ **要調査**: supervisord が環境変数展開をサポートしているか確認が必要
2. ⚠️ **構文**: supervisord 固有の環境変数参照構文を理解する必要

**supervisord の環境変数展開構文**:
- `%(ENV_VARIABLE)s` - 環境変数を参照
- 参考: http://supervisord.org/configuration.html#program-x-section-settings

**調査が必要な項目**:
1. `user` フィールドで環境変数展開が可能か
2. `environment` フィールドで環境変数展開が可能か
3. ビルド時（`supervisord -t`）に環境変数が未定義でもエラーにならないか

---

### 選択肢2: ダミーユーザー名に変更（第二推奨）

**概要**: `<一般ユーザー>` を明示的にダミーとわかる名前に変更

**修正例**:
```ini
user=devuser
environment=HOME="/home/devuser"
```

**メリット**:
1. ✅ **明確性**: ダミーであることが一目瞭然
2. ✅ **確実性**: 環境変数展開の対応不要、確実に動作

**デメリット**:
1. ❌ **実用性が低い**: フォールバック時に実際のユーザー名と合わず、問題が起きる可能性
2. ❌ **根本解決にならない**: 依然として他のユーザーで使えない
3. ❌ **中途半端**: seed.conf だけダミー名にしても、supervisord.conf は依然としてハードコード

**評価**: ⚠️ **非推奨** - 根本的な解決にならない

---

### 選択肢3: テンプレート化（代替案）

**概要**: 設定ファイルをテンプレート（`.conf.template`）として管理し、ビルド時に環境変数を注入

**実装例**:
```bash
# Dockerfile 内で
RUN envsubst < /path/to/seed.conf.template > /path/to/seed.conf
```

**メリット**:
1. ✅ **確実性**: 環境変数展開が確実に動作
2. ✅ **柔軟性**: supervisord の制約に依存しない

**デメリット**:
1. ❌ **複雑性**: テンプレートファイルの管理が必要
2. ❌ **既存構造との不整合**: 他の設定ファイル（devcontainer.json 等）と同様のテンプレート方式だが、supervisord だけ特別扱いになる
3. ❌ **ビルド時のステップ増加**: Dockerfile の RUN 命令が増える

**評価**: ⚠️ **代替案** - 選択肢1が不可能な場合の次善策

---

## 4. 推奨アプローチ

### Phase 1: 調査（優先度: 最高）

**目的**: supervisord の環境変数展開サポートを確認

**調査項目**:

#### 4-1: 公式ドキュメント確認
- supervisord 公式ドキュメントで `%(ENV_VAR)s` 構文の使用可否を確認
- `user` フィールドでの環境変数展開サポートを確認
- `environment` フィールド内での環境変数展開サポートを確認

#### 4-2: 実験的検証
- 最小限の設定ファイルで環境変数展開をテスト
- `supervisord -t` によるビルド時構文チェックが通るか確認
- 実行時に正しく展開されるか確認

**完了基準**:
- ✅ 環境変数展開がサポートされている → 選択肢1を採用
- ❌ 環境変数展開がサポートされていない → 選択肢3（テンプレート化）を採用

---

### Phase 2: 実装（調査結果に基づく）

#### パターンA: 環境変数展開がサポートされている場合

**修正対象ファイル**:
1. `.devcontainer/supervisord/seed.conf`
2. `.devcontainer/supervisord/supervisord.conf`

**修正内容**:
```ini
# seed.conf (line 76, 81)
[program:code-server]
user=%(ENV_UNAME)s
environment=CODE_SERVER_PORT="4035",HOME="/home/%(ENV_UNAME)s"

# supervisord.conf (line 12, 14, 22, 24)
[program:process-compose]
user=%(ENV_UNAME)s
environment=HOME="/home/%(ENV_UNAME)s"

[program:code-server]
user=%(ENV_UNAME)s
environment=HOME="/home/%(ENV_UNAME)s"
```

**環境変数の注入**:
- `docker-compose.yml` で既に `UNAME` 環境変数が定義されている
- s6-overlay サービス起動時に自動的に引き継がれる

**検証手順**:
1. ビルド時: `supervisord -t` で構文チェック
2. 起動時: code-server が正しいユーザーで起動しているか確認
3. フォールバック時: seed.conf が正しく機能するか確認

---

#### パターンB: 環境変数展開がサポートされていない場合

**代替案: テンプレート化**

**実装手順**:

1. テンプレートファイル作成:
   - `.devcontainer/supervisord/seed.conf.template`
   - `.devcontainer/supervisord/supervisord.conf.template`

2. テンプレート内容:
   ```ini
   user=${UNAME}
   environment=HOME="/home/${UNAME}"
   ```

3. Dockerfile 修正:
   ```dockerfile
   # テンプレートからコンフィグを生成
   RUN UNAME=${UNAME} envsubst < /path/to/seed.conf.template > /path/to/seed.conf && \
       UNAME=${UNAME} envsubst < /path/to/supervisord.conf.template > /path/to/supervisord.conf
   ```

4. .gitignore 更新:
   ```gitignore
   .devcontainer/supervisord/seed.conf
   .devcontainer/supervisord/supervisord.conf
   ```

---

### Phase 3: ドキュメント更新

**更新対象**:
1. `25_6_12_v10_completion_implementation_tracker.md` - 本問題の調査・実装タスクを追加
2. `seed.conf` のコメント - 環境変数化について説明追加
3. `25_0_process_management_solution.v10.md` - 環境変数化の設計意図を記録

---

## 5. 次のアクション

**immediate action**:
1. ✅ このドキュメント（25_6_20）の作成 - 完了
2. ⏳ 実装トラッカー（25_6_12）の更新 - 新規タスク追加
3. ⏳ supervisord 環境変数展開サポートの調査
4. ⏳ 調査結果に基づき実装方針決定
5. ⏳ 設定ファイル修正
6. ⏳ 検証

**モード**: mode-3（実装・検証モード）

---

**最終更新**: 2026-01-10T10:15:00+09:00
**ステータス**: 🔵 **Phase 1調査待ち** - supervisord 環境変数展開サポート確認が必要
**次のアクション**: 実装トラッカー更新 → 環境変数展開サポート調査
