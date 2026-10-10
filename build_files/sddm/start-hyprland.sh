#!/bin/bash
set -euo pipefail

# Include system-wide and per-user Flatpak launchers for existing users too.
data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for exports_dir in /var/lib/flatpak/exports/share "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share"; do
    case ":${data_dirs}:" in
        *":${exports_dir}:"*) ;;
        *) data_dirs="${exports_dir}:${data_dirs}" ;;
    esac
done
export XDG_DATA_DIRS="$data_dirs"

systemctl --user start avethyos-user-config.service
exec /usr/bin/dbus-run-session -- /usr/bin/start-hyprland
