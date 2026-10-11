#!/usr/bin/env bash
set -euo pipefail

mkdir -p /usr/lib/tmpfiles.d

TMPFILES_CONF="/usr/lib/tmpfiles.d/discord-rpc-universal.conf"
rm -f "${TMPFILES_CONF}"

CLIENTS=(
    "org.equicord.equibop"
    "dev.vencord.Vesktop"
    "com.discordapp.Discord"
    "com.discordapp.DiscordCanary"
    "com.discordapp.DiscordPTB"
    "io.github.spacingbat3.webcord"
)

for i in {0..9}; do
    for client in "${CLIENTS[@]}"; do
        echo "L%? %t/discord-ipc-${i} - - - - .flatpak/${client}/xdg-run/discord-ipc-${i}" >> "${TMPFILES_CONF}"
    done
done

mkdir -p /var/lib/flatpak/overrides

cat <<'EOF' > /var/lib/flatpak/overrides/global
[Context]
filesystems=xdg-run;xdg-run/discord-ipc-*:create;
EOF
