#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    sddm sddm-wayland-generic \
    qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia qt6-qtimageformats \
    fontconfig

install -Dm644 /ctx/sddm/wayland.conf /etc/sddm.conf.d/10-avethyos.conf
install -Dm755 /ctx/sddm/start-hyprland.sh /usr/libexec/avethyos-start-hyprland
install -Dm644 /ctx/sddm/hyprland.desktop /usr/share/avethyos/wayland-sessions/hyprland.desktop
mkdir -p /usr/share/avethyos/xsessions
systemctl enable sddm.service
systemctl set-default graphical.target
