#!/bin/bash
set -euo pipefail

# Remove unwanted desktop apps and their Nautilus extensions after all installs.
unwanted_apps=()
for package in gnome-control-center gnome-terminal gnome-terminal-nautilus \
    file-roller file-roller-nautilus; do
    if rpm -q "$package" >/dev/null 2>&1; then
        unwanted_apps+=("$package")
    fi
done
if (( ${#unwanted_apps[@]} > 0 )); then
    dnf5 remove -y --no-autoremove "${unwanted_apps[@]}"
fi

dnf5 copr remove -y lionheartp/Hyprland
dnf5 copr remove -y lilay/topgrade
dnf5 config-manager unsetopt fedora-cisco-openh264.enabled

for repo_dir in /etc/yum.repos.d /etc/distro.repos.d /usr/share/dnf5/repos.d; do
    rm -f "${repo_dir}"/rpmfusion-*.repo \
        "${repo_dir}"/*copr*lionheartp*Hyprland*.repo \
        "${repo_dir}"/*copr*lilay*topgrade*.repo
done

# /var/cache is a build cache mount, so these downloads never enter the image.
# Keep them for later builds rather than erasing the runner's package cache.

install -Dm644 /ctx/docs/README.md /usr/share/doc/avethyos/README.md
install -Dm644 /ctx/docs/LICENSE /usr/share/doc/avethyos/LICENSE
chmod 0755 /usr/libexec/avethyos-image-cleanup

# Apply branding after package installs so the initramfs includes AvethyOS names.
bash /ctx/layers/branding.sh

kernel_version=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n')
if [[ $kernel_version == *$'\n'* || $kernel_version != *-ogc* ]]; then
    printf 'Expected one installed OGC kernel-core package, got: %s\n' "$kernel_version" >&2
    exit 1
fi

# Generate one generic bootc initramfs after all layers, including NVIDIA.
install -d -m 0700 /var/roothome
depmod -a "$kernel_version"
# Keep unchanged initramfs contents identical across daily rebuilds.
DRACUT_NO_XATTR=1 dracut --force --no-hostonly --reproducible \
    --add-confdir /ctx/kernel/dracut.conf.d \
    "/usr/lib/modules/${kernel_version}/initramfs.img" "$kernel_version"
test -s "/usr/lib/modules/${kernel_version}/vmlinuz"
test -s "/usr/lib/modules/${kernel_version}/initramfs.img"
