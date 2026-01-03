git のワーキングディレクトリの差分を確認し

重大な問題 ( 例: 秘匿情報が差分として出てきている、バグが含まれている ) がなければ

Pull Request を作成してください

## Pull Request 作成手順

- 差分の確認
- <新規ブランチ> の作成
- Commit作成
    - 複数回に分けてもいいです
- `origin/<新規ブランチ>` に push
- **【重要】Pull Request作成先のデフォルトリポジトリ設定**
    - `upstream`リポジトリの情報を`git remote -v`で確認する
        - 例: `upstream`のリポジトリが `hagevvashi-info/hagevvashi.info-dev-hub` の場合
    - **`gh repo set-default <upstream-owner>/<upstream-repo>`** コマンドで、Pull Requestを作成するターゲットリポジトリを明示的に設定します。
        - 例: `gh repo set-default hagevvashi-info/hagevvashi.info-dev-hub`
    - **設定の確認**: `gh repo view --json defaultBranchRef` を実行し、`"name": "main"` が表示され、現在のデフォルトリポジトリが`upstream`リポジトリであることを確認します。
- gh コマンドで Pull Request 作成
    - Pull Request 作成時の base と head は下記です
        - base: `main` (※ 事前に設定したデフォルトリポジトリのmainブランチを指します)
        - head: `<fork-owner>:<branch-name>` (※ あなたのフォークリポジトリのブランチを指定)
    - 例: `gh pr create --title "fix: ..." --body "..." --base main --head hagevvashi:fix/your-branch-name`
    - **再度注意**: `gh pr create`実行前に、必ず`gh repo view`で現在のデフォルトリポジトリが`upstream`リポジトリになっていることを確認してください。

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
