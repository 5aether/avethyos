#!/bin/bash
set -euo pipefail

# Keep desktop code in the deployment's read-only /usr, so bootc upgrades and
# rollbacks change the compositor integration and shell together. DESTDIR and
# DESKTOP_SOURCE_DIR allow checking the installation in a temporary directory.
desktop_source="${DESKTOP_SOURCE_DIR:-/defaults}"
image_root="${DESTDIR:-}"
desktop_root="${image_root}/usr/share/avethyos"
shell_root="${desktop_root}/quickshell"
hypr_root="${desktop_root}/hypr"
libdir="$(rpm --eval '%{_libdir}')"

install -d -m 0755 "$shell_root" "$hypr_root"
cp -R "${desktop_source}/quickshell/." "$shell_root/"
cp -R "${desktop_source}/hypr/." "$hypr_root/"

# The native plugins and precompiled shaders come from the build stage.
find "$shell_root" "$hypr_root" \
    -type d \( -name .git -o -name .vscode -o -name __pycache__ \) \
    -prune -exec rm -rf -- {} +

rm -rf "$shell_root/tests" "$shell_root/native/qt-theme/build-qt5" \
    "$shell_root/native/qt-theme/build-qt6"
find "$shell_root" "$hypr_root" -type f -name '*.pyc' -delete

for shader in "$shell_root"/shaders/*.qsb; do
    test -f "$shader"
    ln -sf "../../shaders/$(basename "$shader")" \
        "$shell_root/assets/shaders/$(basename "$shader")"
done
for major in 5 6; do
    ln -s "${libdir}/avethyos/qt-theme/qt${major}" \
        "$shell_root/native/qt-theme/build-qt${major}"
done

# Explicit modes prevent writable source checkout modes from reaching /usr.
find "$shell_root" "$hypr_root" -type d -exec chmod 0755 {} +
find "$shell_root" "$hypr_root" -type f -exec chmod 0644 {} +
find "$shell_root/scripts" -type f \( -name '*.sh' -o -name '*.py' \) \
    -exec chmod 0755 {} +

# Only editable preferences are seeded into home directories at login. Nothing
# in /etc/skel can shadow the image-managed shell or compositor entry point.
rm -rf "${image_root}/etc/skel/.config/quickshell" \
    "${image_root}/etc/skel/.config/hypr"
if [[ -z $image_root ]]; then
    chown -R root:root "$shell_root" "$hypr_root"
    systemctl --global enable avethyos-user-config.service
fi
