#!/bin/bash
set -euo pipefail

systemctl --user start avethyos-user-config.service
exec /usr/bin/Hyprland
