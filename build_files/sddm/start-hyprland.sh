#!/bin/bash
set -euo pipefail

# XDG base directories must be absolute. Keep the initializer, compositor and
# shell on the same fallback paths when the login environment contains an
# invalid value.
for variable in XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME; do
    case "${!variable:-}" in
        /*) ;;
        *) unset "$variable" ;;
    esac
done

# Include system-wide and per-user Flatpak launchers for existing users too.
data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for exports_dir in /var/lib/flatpak/exports/share "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share"; do
    case ":${data_dirs}:" in
        *":${exports_dir}:"*) ;;
        *) data_dirs="${exports_dir}:${data_dirs}" ;;
    esac
done
export XDG_DATA_DIRS="$data_dirs"

# Run on every login even if the user manager survived logout. The initializer
# preserves existing preferences and seeds only files that are missing.
/usr/bin/python3 /usr/libexec/avethyos-user-config
exec /usr/bin/dbus-run-session -- /usr/bin/start-hyprland -- \
    --config /usr/share/avethyos/hypr/hyprland.lua
