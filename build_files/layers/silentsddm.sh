#!/bin/bash
set -euo pipefail

git clone -b main --depth=1 https://github.com/uiriansan/SilentSDDM /tmp/SilentSDDM
mkdir -p /usr/share/sddm/themes/silent /usr/share/fonts/silent-sddm
cp -a /tmp/SilentSDDM/. /usr/share/sddm/themes/silent/
rm -rf /usr/share/sddm/themes/silent/.git /usr/share/sddm/themes/silent/.github
cp -a /usr/share/sddm/themes/silent/fonts/. /usr/share/fonts/silent-sddm/
fc-cache -f /usr/share/fonts/silent-sddm
install -Dm644 /ctx/sddm/silent.conf /etc/sddm.conf
