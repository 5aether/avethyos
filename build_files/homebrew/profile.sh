if [ "$(id -u)" -ne 0 ] && [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    export HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
    export HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar
    export HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew
    export PATH="/usr/libexec/avethyos-homebrew/bin:$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
    export MANPATH="$HOMEBREW_PREFIX/share/man:${MANPATH:-}"
    export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"
fi
