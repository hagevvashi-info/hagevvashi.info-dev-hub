# ~/.bash_profile: executed by bash(1) for login shells.

# Load .profile for environment variables (shell-independent settings)
if [ -f ~/.profile ]; then
    . ~/.profile
fi

# Load .bashrc for interactive shell settings
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
