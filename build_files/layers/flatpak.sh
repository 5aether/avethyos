#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    flatpak flatpak-session-helper accountsservice /usr/bin/curl

mkdir -p /etc/flatpak/installations.d /usr/share/flatpak/remotes.d
install -m644 /ctx/flatpak/build.conf /etc/flatpak/installations.d/avethyos-build.conf
curl --fail --location --retry 3 \
    https://dl.flathub.org/repo/flathub.flatpakrepo \
    --output /usr/share/flatpak/remotes.d/flathub.flatpakrepo
sed -i '/^CollectionID=/d; /^\[Flatpak Repo\]$/a CollectionID=org.flathub.Stable' \
    /usr/share/flatpak/remotes.d/flathub.flatpakrepo

flatpak remote-add --installation=avethyos-build --if-not-exists \
    --collection-id=org.flathub.Stable flathub \
    /usr/share/flatpak/remotes.d/flathub.flatpakrepo
flatpak config --installation=avethyos-build --set languages '*'
flatpak install --installation=avethyos-build -y --noninteractive flathub \
    io.github.kolunmi.Bazaar com.github.tchx84.Flatseal
mkdir -p /usr/share/avethyos/flatpak-seed
flatpak create-usb --installation=avethyos-build \
    /usr/share/avethyos/flatpak-seed \
    io.github.kolunmi.Bazaar com.github.tchx84.Flatseal
rm /etc/flatpak/installations.d/avethyos-build.conf
rm -rf /var/tmp/avethyos-flatpak-build

systemctl enable avethyos-flatpak-preinstall.service
