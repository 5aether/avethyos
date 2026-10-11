#!/bin/sh
# Launches the shell, failing loudly on missing dependencies instead of
# degrading silently. Optimised to stay portable across GPU vendors: no
# hardware-acceleration flag is set here, because QtMultimedia probes the
# driver itself and falls back to software decoding when there is none.
#
# Usage: scripts/run.sh [extra qs args...]

set -u

root=$(cd "$(dirname "$0")/.." && pwd)

# Code lives in the bootc image; settings survive deployments in user state.
case ${XDG_STATE_HOME:-} in
    /*) state_root=$XDG_STATE_HOME ;;
    *) state_root="$HOME/.local/state" ;;
esac
config="$state_root/avethyos/quickshell/config.ini"
mkdir -p "$(dirname "$config")" || exit 1
if [ ! -f "$config" ]; then
    case ${XDG_CONFIG_HOME:-} in
        /*) config_root=$XDG_CONFIG_HOME ;;
        *) config_root="$HOME/.config" ;;
    esac
    legacy_config="$config_root/quickshell/config.ini"
    seed_source=""
    if [ -f "$legacy_config" ]; then
        seed_source="$legacy_config"
    elif [ -f "$root/config.ini" ]; then
        seed_source="$root/config.ini"
    fi
    if [ -n "$seed_source" ]; then
        pending=$(mktemp "$(dirname "$config")/.config.XXXXXX") || exit 1
        if ! cp "$seed_source" "$pending"; then
            rm -f "$pending"
            exit 1
        fi
        # Publish a complete seed atomically. A concurrent initializer or shell
        # can win this race; its settings always take precedence over defaults.
        if ! ln "$pending" "$config" 2>/dev/null && [ ! -f "$config" ]; then
            rm -f "$pending"
            exit 1
        fi
        rm -f "$pending"
    fi
fi

missing=""
for tool in qs; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "missing required command(s):$missing" >&2
    echo "install with: sudo dnf install quickshell" >&2
    exit 1
fi

# Optional helpers. Each one only affects the panel that uses it, so a missing
# tool degrades that panel instead of the whole shell.
warn_missing() {
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || \
            echo "warning: $tool not found, the feature using it stays disabled" >&2
    done
}
warn_missing nmcli bluetoothctl ddcutil ffmpeg ffprobe gsettings gio hyprctl playerctl python3 wl-copy wl-paste

# Apply before Quickshell captures the environment used by desktop launchers.
# The helper serializes startup against wallpaper/theme changes and emits only
# safely quoted exports on stdout. A failed apply must not look successful.
if ! theme_exports=$(python3 "$root/scripts/material-palette.py" --startup --shell-environment); then
    echo "Avethy: could not apply desktop themes; shell startup stopped" >&2
    exit 1
fi
eval "$theme_exports"
export AVETHY_THEME_READY=1

# Qt's native providers also serve tray/menu icons. Select the same pack before
# Qt starts; application and notification icons additionally update live in QML.
if ! icon_pack=$(python3 "$root/scripts/icon-theme.py" --config "$config"); then
    echo "Avethy: could not read the shell icon pack; shell startup stopped" >&2
    exit 1
fi
if [ -n "$icon_pack" ]; then
    export QS_ICON_THEME="$icon_pack"
else
    unset QS_ICON_THEME
fi

# Keep the Qt multimedia backend on FFmpeg. Without this, a distribution that
# defaults to GStreamer may pick a backend without hardware decoding, which is
# the most common cause of a stuttering video wallpaper.
export QT_MEDIA_BACKEND="${QT_MEDIA_BACKEND:-ffmpeg}"
# Make the shell-wide Qt default text family SF Pro Text. Icon glyphs use
# their explicit Material font and are unaffected by this fontconfig alias.
export FONTCONFIG_FILE="${root}/assets/sf-pro-text-fontconfig.xml"

exec qs -p "$root" "$@"
