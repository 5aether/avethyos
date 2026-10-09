#!/bin/bash
set -euo pipefail

mkdir -p /etc/skel/.config
cp -R /defaults/hypr /defaults/quickshell /etc/skel/.config/
for shader in /usr/share/avethyos/quickshell/shaders/*.qsb; do
    ln -sf "$shader" "/etc/skel/.config/quickshell/assets/shaders/$(basename "$shader")"
done

find /etc/skel/.config/hypr /etc/skel/.config/quickshell \
    -type d \( -name .git -o -name .vscode -o -name __pycache__ \) \
    -prune -exec rm -rf -- {} +

rm -rf /etc/skel/.config/quickshell/tests \
    /etc/skel/.config/quickshell/native/qt-theme/build-qt*

libdir="$(rpm --eval '%{_libdir}')"
for major in 5 6; do
    ln -s "$libdir/avethyos/qt-theme/qt${major}" \
        "/etc/skel/.config/quickshell/native/qt-theme/build-qt${major}"
done

find /etc/skel/.config/hypr /etc/skel/.config/quickshell \
    -type f -name '*.pyc' -delete

chmod -R a+rX /etc/skel/.config/hypr /etc/skel/.config/quickshell
find /etc/skel/.config/hypr/scripts /etc/skel/.config/quickshell/scripts \
    -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} +
systemctl --global enable avethyos-user-config.service
