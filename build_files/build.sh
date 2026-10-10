#!/bin/bash

set -euo pipefail

cp -avf /ctx/system_files/. /
systemctl --no-reload enable avethyos-fstab-compat.service
