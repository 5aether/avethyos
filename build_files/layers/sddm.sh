#!/bin/bash
set -euo pipefail

# Remove an inherited GDM installation without autoremoving desktop libraries.
if rpm -q gdm >/dev/null 2>&1; then
    dnf5 remove -y --no-autoremove gdm
fi

# Clear the previous display manager before SDDM's package preset runs.
rm -f /etc/systemd/system/display-manager.service

dnf5 install -y --setopt=install_weak_deps=False \
    sddm sddm-wayland-generic \
    qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia qt6-qtimageformats \
    fontconfig

install -Dm644 /ctx/sddm/wayland.conf /etc/sddm.conf.d/10-avethyos.conf
install -Dm755 /ctx/sddm/start-hyprland.sh /usr/libexec/avethyos-start-hyprland
install -Dm644 /ctx/sddm/hyprland.desktop /usr/share/avethyos/wayland-sessions/hyprland.desktop
mkdir -p /usr/share/avethyos/xsessions
systemctl --no-reload --force enable sddm.service
systemctl --no-reload set-default graphical.target
