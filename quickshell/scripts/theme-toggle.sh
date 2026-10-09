#!/bin/sh

set -eu
mode="${1:-}"
case "$mode" in
    dark|light) ;;
    *) echo "usage: $0 dark|light" >&2; exit 2 ;;
esac

# The helper writes every toolkit palette before notifying applications.
# Existing applications may need reopening to reload CSS.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec python3 "$root/scripts/material-palette.py" --apply-only --mode "$mode"
