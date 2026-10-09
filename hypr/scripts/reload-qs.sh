#!/bin/bash
set -eu
exec python3 "$HOME/.config/quickshell/scripts/restart-shell.py" --daemonize
