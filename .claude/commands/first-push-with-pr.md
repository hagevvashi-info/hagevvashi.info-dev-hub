git のワーキングディレクトリの差分を確認し

重大な問題 ( 例: 秘匿情報が差分として出てきている、バグが含まれている ) がなければ

Pull Request を作成してください

## Pull Request 作成手順

- 差分の確認
- <新規ブランチ> の作成
- Commit作成
    - 複数回に分けてもいいです
- `origin/<新規ブランチ>` に push
- gh コマンドで Pull Request 作成
    - Pull Request 作成時の base と head は下記です
        - base: `upstream/main`
        - head: `origin/<新規ブランチ>`
    - **注意**: forkされたリポジトリからupstreamへPRを作成する場合
        - `gh pr create --title "タイトル" --body "本文" --base main --head <fork-owner>:<branch-name>`
        - 例: `gh pr create --title "docs: clarify assistant modes" --base main --head hagevvashi:docs/clarify-assistant-modes`
        - 事前に `gh repo set-default <upstream-repo>` でデフォルトリポジトリを設定

## Pull Request のタイトルと本文のルール

### タイトル

コミットメッセージのように、`<prefix>: 概要` というフォーマットで書いてください

### 本文

本文は下記構成で書いてください

- Why
    - 課題―目標とのギャップ
    - 原因
    - 目的 (あるべき状態)
    - 仮説・設計・解決のアプローチ
    - 解決策
- Why not
    - 採用しなかった仮説・設計・解決のアプローチや解決策の候補
    - 採用しなかった理由
- What (ソリューション・イネーブルメント)
- 仮説の検証結果
- 結論
