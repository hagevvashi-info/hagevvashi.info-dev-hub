# v10プロセス管理設計 実装トラッカー

このドキュメントは「[25_4_v10_implementation_plan.v1.md](25_4_v10_implementation_plan.v1.md)」の進捗状況を追跡するためのものです。
実装が進むたびに更新してください。

---

## 進捗サマリー

- ✅ **完了**: Phase 0, Phase 1
- 🟡 **進行中 (差異あり)**: Phase 2
- 🔴 **未着手**: Phase 3, Phase 4, Phase 5, Phase 6

---

## フェーズ別タスクリスト

### Phase 0: ディレクトリ構成設計の更新
- [x] `14_詳細設計_ディレクトリ構成.v11.md` を作成する

### Phase 1: s6-overlay導入（PID 1変更）
- [x] Dockerfileにs6-overlayをインストールし、ENTRYPOINTを`/init`に変更
- [x] `.devcontainer/s6-rc.d/` にサービス定義を作成

### Phase 2: 2層構造実装（seed + project）
- [x] `workloads/` ディレクトリと実運用設定 (`project.conf`, `project.yaml`) を作成
- [x] ビルド時検証用の `seed.conf` を作成
- [x] `seed.yaml` を `.devcontainer/process-compose/` 配下に配置する
    - **Note:** 現在、`workloads/process-compose/` に誤って配置されています。
- [x] 設定ファイル名を計画書通りにリネームする (`*.default` -> `seed.*`)

## 進捗サマリー

- ✅ **完了**: Phase 0, Phase 1, Phase 2
- 🔴 **未着手**: Phase 3, Phase 4, Phase 5, Phase 6

- [x] `workloads/supervisord/project.conf` から `[program:process-compose]` の定義を削除する
- [x] `workloads/supervisord/project.conf` から `[program:difit]` の定義を削除し、管理を `process-compose` に一本化する

## 進捗サマリー

- ✅ **完了**: Phase 0, Phase 1, Phase 2, Phase 3
- 🔴 **未着手**: Phase 4, Phase 5, Phase 6

- [x] `docker-entrypoint.sh` を修正し、`workloads/` の設定を読み込むようにする
- [x] `docker-entrypoint.sh` に、設定読み込み失敗時に `seed` 設定へフォールバックするロジックを実装する

## 進捗サマリー

- ✅ **完了**: Phase 0, Phase 1, Phase 2, Phase 3, Phase 4
- 🔴 **未着手**: Phase 5, Phase 6

### Phase 5: docker-compose.yml調整
- [x] `tmpfs` 設定を追加する

## 進捗サマリー

- ✅ **完了**: Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, Phase 5
- 🔴 **未着手**: Phase 6

- [x] `workloads/` 配下の各ディレクトリに `README.md` を作成し、使い方を記述する
- [x] `foundations/onboarding/` に全体のアーキテクチャと使い方ガイドを作成する

## 進捗サマリー

- ✅ **完了**: Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, Phase 5, Phase 6
