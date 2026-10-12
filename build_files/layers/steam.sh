#!/bin/bash
set -euo pipefail

if [[ $(rpm --eval '%{_arch}') != x86_64 ]]; then
    echo 'Steam requires an x86_64 image.' >&2
    exit 1
fi

dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    gamescope \
    gamemode.x86_64 \
    gamemode.i686 \
    mangohud.x86_64 \
    mangohud.i686 \
    mesa-dri-drivers.x86_64 \
    mesa-dri-drivers.i686 \
    mesa-vulkan-drivers.x86_64 \
    mesa-vulkan-drivers.i686
