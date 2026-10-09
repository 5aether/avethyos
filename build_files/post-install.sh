#!/bin/bash
set -euo pipefail

dnf5 copr remove -y lionheartp/Hyprland
dnf5 copr remove -y lilay/topgrade
dnf5 config-manager unsetopt fedora-cisco-openh264.enabled

for repo_dir in /etc/yum.repos.d /etc/distro.repos.d /usr/share/dnf5/repos.d; do
    rm -f "${repo_dir}"/rpmfusion-*.repo \
        "${repo_dir}/fedora-cisco-openh264.repo"
done

dnf5 clean all
