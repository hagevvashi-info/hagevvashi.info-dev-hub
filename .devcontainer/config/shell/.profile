# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login exists.
# See /usr/share/doc/bash/examples/startup-files for examples.

# Note: For Bash, .bash_profile handles loading .bashrc
# This file is primarily for:
# - Non-Bash shells (sh, dash, etc.)
# - Tools that explicitly source .profile (e.g., VSCode extensions)

# Load environment variables
if [ -f "${HOME}/env.sh" ]; then
  . "${HOME}/env.sh"
fi

# ============
# /root には コピーしてないので、 root ユーザーじゃないよね、分岐は不要
# ============

# VS Code (Claude Code) などの非対話型シェルからも mise 管理のツールを使いたい ので
# VS Code (Claude Code) などの非対話型シェルは ~/.bashrc をよまないけど、 ~/.profile はよんでくれる
# --shims: ディレクトリ監視フックが動かない環境でも、共通のパス（~/.local/share/mise/shims）を通してツールを使えるようにするため
# ~/.bashrc では --shims 不要
eval "$(mise activate bash --shims)"
