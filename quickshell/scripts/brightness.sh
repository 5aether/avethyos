#!/usr/bin/env bash
# Brightness control wrapper that triggers OSD via IPC
# Usage: brightness.sh <display> <+|-|set> <value>
#   brightness.sh 1 + 5      # Increase display 1 by 5%
#   brightness.sh 1 - 5      # Decrease display 1 by 5%
#   brightness.sh 1 set 50   # Set display 1 to 50%

DISPLAY_NUM="${1:-1}"
ACTION="$2"
VALUE="$3"

if [ -z "$ACTION" ] || [ -z "$VALUE" ]; then
    echo "Usage: $0 <display> <+|-|set> <value>" >&2
    exit 1
fi

# Find ddcutil in PATH
DDCUTIL=$(command -v ddcutil)
if [ -z "$DDCUTIL" ]; then
    echo "Error: ddcutil not found in PATH" >&2
    exit 1
fi

# Execute the ddcutil command
if [ "$ACTION" = "set" ]; then
    "$DDCUTIL" setvcp 10 "$VALUE" --display "$DISPLAY_NUM" --noverify 2>&1
else
    "$DDCUTIL" setvcp 10 "$ACTION" "$VALUE" --display "$DISPLAY_NUM" --noverify 2>&1
fi

# Get the new brightness level
BRIGHTNESS_OUTPUT=$("$DDCUTIL" getvcp 10 --terse --noverify --display "$DISPLAY_NUM" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$BRIGHTNESS_OUTPUT" ]; then
    # Parse: VCP 10 C 50 100
    if [[ "$BRIGHTNESS_OUTPUT" =~ VCP[[:space:]]+10[[:space:]]+C[[:space:]]+([0-9]+)[[:space:]]+([0-9]+) ]]; then
        CURRENT="${BASH_REMATCH[1]}"
        MAX="${BASH_REMATCH[2]}"
        PERCENT=$((CURRENT * 100 / MAX))
        
        # Trigger OSD via IPC
        QUICKSHELL_IPC=$(command -v qs)
        if [ -n "$QUICKSHELL_IPC" ]; then
            "$QUICKSHELL_IPC" ipc call osd brightness "$PERCENT" 2>/dev/null
        fi
    fi
fi
