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
    - 以下のコマンドを実行し、必要なリポジトリ情報をシェル変数に格納します。
        ```bash
        UPSTREAM_REMOTE_URL=$(git remote -v | grep '^upstream' | awk '{print $2}' | head -n 1)
        UPSTREAM_OWNER_REPO=$(echo "$UPSTREAM_REMOTE_URL" | sed -E 's/.*[:/]([^/]+\/[^/]+)\.git/\1/')
        FORK_REMOTE_URL=$(git remote -v | grep '^origin' | awk '{print $2}' | head -n 1)
        FORK_OWNER=$(echo "$FORK_REMOTE_URL" | sed -E 's/.*[:/]([^/]+)\/[^/]+\.git/\1/')
        CURRENT_BRANCH=$(git branch --show-current)
        ```
    - **`gh repo set-default ${UPSTREAM_OWNER_REPO}`** コマンドで、Pull Requestを作成するターゲットリポジトリを明示的に設定します。
        ```bash
        gh repo set-default ${UPSTREAM_OWNER_REPO}
        ```
    - **設定の確認**: 以下のコマンドを実行し、現在のデフォルトリポジトリが`upstream`リポジトリであることを確認します。
        ```bash
        echo "現在のデフォルトリポジリ: $(gh repo view --json name,owner --jq '.owner.login + "/" + .name')"
        echo "ベースブランチ: $(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
        ```
        確認後、表示されたリポジトリ名が`upstream`リポジリ（例: `<some_org>/<repo_name>`）と一致し、ベースブランチが`main`であることを確認してください。
- gh コマンドで Pull Request 作成
    - Pull Request 作成時の base と head は下記です
        - base: `main` (※ 事前に設定したデフォルトリポジトリのmainブランチを指します)
        - head: `${FORK_OWNER}:${CURRENT_BRANCH}` (※ あなたのフォークリポジトリのブランチを指定)
    - 以下のコマンドでPull Requestを作成します。**実行前に、必ず表示される情報を確認してください。**
        ```bash
        gh pr create \
          --title "fix: ..." \
          --body "..." \
          --base main \
          --head ${FORK_OWNER}:${CURRENT_BRANCH} \
          --fill # または `--body "Why: ..."` で本文を記述
        ```
    - **再度注意**: `gh pr create`実行前に、必ず表示されるタイトル、本文、`base`、`head`が意図通りであることを確認してください。

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
