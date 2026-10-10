#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    'hyprland >= 0.55' hyprshot hyprpicker hyprland-guiutils \
    kitty grim slurp wl-clipboard jq \
    xorg-x11-server-Xwayland xdg-utils xdg-user-dirs \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    dbus-tools polkit libnotify \
    NetworkManager NetworkManager-wifi bluez \
    pipewire pipewire-pulseaudio pipewire-alsa wireplumber

systemctl enable NetworkManager.service bluetooth.service
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
