#!/bin/bash
set -euo pipefail

# Include rootless networking, storage, UID mapping, runtime and init helpers
# explicitly because image builds disable weak RPM dependencies.
dnf5 install -y --setopt=install_weak_deps=False \
    distrobox podman crun conmon catatonit passt fuse-overlayfs \
    shadow-utils shadow-utils-subid which pciutils

# Fedora useradd allocates subordinate IDs for new accounts automatically.
# This also prepares existing accounts when they upgrade to AvethyOS.
systemctl --no-reload enable avethyos-user-access.service
