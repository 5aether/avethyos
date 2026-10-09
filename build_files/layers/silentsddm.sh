#!/bin/bash
set -euo pipefail

git clone -b main --depth=1 https://github.com/uiriansan/SilentSDDM /tmp/SilentSDDM
mkdir -p /usr/share/sddm/themes/silent /usr/share/fonts/silent-sddm
cp -a /tmp/SilentSDDM/. /usr/share/sddm/themes/silent/
rm -rf /usr/share/sddm/themes/silent/.git /usr/share/sddm/themes/silent/.github \
    /usr/share/sddm/themes/silent/docs
sed -i '/^Screenshot=/d' /usr/share/sddm/themes/silent/metadata.desktop
cp -a /usr/share/sddm/themes/silent/fonts/. /usr/share/fonts/silent-sddm/
rm -rf /usr/share/sddm/themes/silent/fonts
ln -s /usr/share/fonts/silent-sddm /usr/share/sddm/themes/silent/fonts
fc-cache -f /usr/share/fonts/silent-sddm
install -Dm644 /ctx/sddm/silent.conf /etc/sddm.conf
