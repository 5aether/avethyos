#!/bin/bash
set -euo pipefail

fedora_release=$(rpm --eval '%fedora')

dnf5 install -y --setopt=install_weak_deps=False \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_release}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"

dnf5 config-manager setopt fedora-cisco-openh264.enabled=1

dnf5 install -y --setopt=install_weak_deps=False \
    rpmfusion-free-release-tainted \
    rpmfusion-nonfree-release-tainted

dnf5 copr enable -y lionheartp/Hyprland
dnf5 copr enable -y lilay/topgrade
