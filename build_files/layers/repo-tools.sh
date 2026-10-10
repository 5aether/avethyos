#!/bin/bash
set -euo pipefail

# The bootc base ships only C locales; the installer defaults to en_US.UTF-8.
dnf5 install -y --setopt=install_weak_deps=False dnf5-plugins glibc-langpack-en
