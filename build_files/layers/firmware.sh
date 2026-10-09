#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    --from-repo=rpmfusion-nonfree-tainted '*-firmware'
