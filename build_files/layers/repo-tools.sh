#!/bin/bash
set -euo pipefail

# The bootc base ships only C locales; the installer defaults to en_US.UTF-8.
dnf5 install -y --setopt=install_weak_deps=False \
    dnf5-plugins glibc-langpack-en python3 nano just openssh-server fastfetch \
    'bootc >= 1.16.13' 'ostree >= 2026.1'

# Remote login is available through avethyos service ssh on when requested.
systemctl --no-reload disable sshd.service

# Refuse images without the API used by avethyos kernel/fnmode. This only prints help.
bootc loader-entries set-options-for-source --help >/dev/null
chmod 0755 /usr/bin/avethyos
