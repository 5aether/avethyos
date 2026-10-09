#!/bin/bash
set -euo pipefail

cd /home/linuxbrew

if [[ "$(id -un)" == linuxbrew ]]; then
    exec /home/linuxbrew/.linuxbrew/bin/brew "$@"
fi

exec /usr/bin/sudo -n -H -u linuxbrew /home/linuxbrew/.linuxbrew/bin/brew "$@"
