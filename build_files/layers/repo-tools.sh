#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False dnf5-plugins
