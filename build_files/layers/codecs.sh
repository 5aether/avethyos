#!/bin/bash
set -euo pipefail

if rpm -q ffmpeg-free >/dev/null 2>&1; then
    dnf5 swap -y --setopt=install_weak_deps=False ffmpeg-free ffmpeg --allowerasing
else
    dnf5 install -y --setopt=install_weak_deps=False ffmpeg --allowerasing
fi

dnf5 install -y --setopt=install_weak_deps=False \
    --exclude=PackageKit-gstreamer-plugin @multimedia
