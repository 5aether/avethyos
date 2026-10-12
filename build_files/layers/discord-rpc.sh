#!/bin/bash
set -euo pipefail

# RPC needs live client discovery; static tmpfiles links cannot choose a client.
rm -f /usr/lib/tmpfiles.d/discord-rpc-universal.conf
chmod +x /usr/libexec/avethyos-discord-rpc
systemctl --global enable systemd-tmpfiles-setup.service avethyos-discord-rpc.service
