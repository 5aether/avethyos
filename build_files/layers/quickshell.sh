#!/bin/bash
set -euo pipefail

mapfile -t qt_packages < /theme/qt-packages
dnf5 install -y --setopt=install_weak_deps=False \
    "${qt_packages[@]}" 'quickshell >= 0.3' \
    qt5-qtwayland qt6-qtwayland qt6-qtdeclarative \
    qt6-qt5compat qt6-qtmultimedia qt6-qtsvg qt6-qtimageformats \
    python3 playerctl ddcutil brightnessctl \
    glib2 gsettings-desktop-schemas dconf \
    adw-gtk3-theme papirus-icon-theme google-noto-sans-fonts

libdir="$(rpm --eval '%{_libdir}')"
mkdir -p "$libdir/avethyos" /usr/share/avethyos/quickshell
cp -R /theme/qt-theme "$libdir/avethyos/"
cp -R /theme/shaders /usr/share/avethyos/quickshell/
