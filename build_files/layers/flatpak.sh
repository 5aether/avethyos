#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    flatpak flatpak-session-helper accountsservice /usr/bin/curl

mkdir -p /tmp/avethyos-flatpak-cache /tmp/avethyos-flatpak-triggers
# dconf uses XDG_RUNTIME_DIR for shared memory, independently of the cache.
# Keep it on the build's tmpfs instead of falling back to the absent root home.
install -d -m 0700 /tmp/avethyos-flatpak-runtime
export XDG_CACHE_HOME=/tmp/avethyos-flatpak-cache
export XDG_RUNTIME_DIR=/tmp/avethyos-flatpak-runtime
export FLATPAK_TRIGGERSDIR=/tmp/avethyos-flatpak-triggers

mkdir -p /etc/flatpak/installations.d /usr/share/flatpak/remotes.d
install -m644 /ctx/flatpak/build.conf /etc/flatpak/installations.d/avethyos-build.conf
curl --fail --location --retry 3 \
    https://dl.flathub.org/repo/flathub.flatpakrepo \
    --output /usr/share/flatpak/remotes.d/flathub.flatpakrepo
sed -i '/^CollectionID=/d; /^\[Flatpak Repo\]$/a CollectionID=org.flathub.Stable' \
    /usr/share/flatpak/remotes.d/flathub.flatpakrepo

flatpak remote-add --installation=avethyos-build --if-not-exists --from \
    flathub \
    /usr/share/flatpak/remotes.d/flathub.flatpakrepo
flatpak config --installation=avethyos-build --set languages '*'
for attempt in {1..5}; do
    if flatpak install --installation=avethyos-build -y --noninteractive --or-update flathub \
        io.github.kolunmi.Bazaar com.github.tchx84.Flatseal; then
        break
    else
        status=$?
    fi
    if (( attempt == 5 )); then
        exit "$status"
    fi
    printf 'Flatpak installation failed; retrying (%s/5)...\n' "$((attempt + 1))" >&2
    sleep "$((attempt * 10))"
done
mkdir -p /usr/share/avethyos/flatpak-seed
flatpak create-usb --installation=avethyos-build \
    /usr/share/avethyos/flatpak-seed \
    io.github.kolunmi.Bazaar com.github.tchx84.Flatseal
rm /etc/flatpak/installations.d/avethyos-build.conf
rm -rf /var/tmp/avethyos-flatpak-build

systemctl enable avethyos-flatpak-preinstall.service
