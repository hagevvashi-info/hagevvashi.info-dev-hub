# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login exists.
# See /usr/share/doc/bash/examples/startup-files for examples.

# Note: For Bash, .bash_profile handles loading .bashrc
# This file is primarily for:
# - Non-Bash shells (sh, dash, etc.)
# - Tools that explicitly source .profile (e.g., VSCode extensions)

# Load PATH configuration
# Note: In Bash, this will also be loaded via .bashrc -> paths.sh
# For non-Bash shells, we load it here directly
if [ -f "$HOME/paths.sh" ]; then
    . "$HOME/paths.sh"
fi

# Load environment variables
if [ -f "$HOME/env.sh" ]; then
    . "$HOME/env.sh"
fi

# Load asdf for non-interactive shells (e.g., code-server, VSCode extensions)
if [ -f "$HOME/.asdf/asdf.sh" ]; then
    . "$HOME/.asdf/asdf.sh"
fi
