#!/bin/bash
set -euo pipefail

# An optional root path also supports branding an unpacked image.
image_root="${1:-}"
os_release="${image_root}/usr/lib/os-release"
. "$os_release"
release_version="${VERSION_ID:?The base image must provide VERSION_ID}"

# Keep Fedora's ID, VERSION_ID and CPE metadata for package and image builders.
# OSTree reads PRETTY_NAME from /usr/lib/os-release for its boot menu titles.
sed -i \
    -e '/^NAME=/d' \
    -e '/^PRETTY_NAME=/d' \
    -e '/^VERSION=/d' \
    -e '/^DEFAULT_HOSTNAME=/d' \
    -e '/^LOGO=/d' \
    -e '/^HOME_URL=/d' \
    -e '/^DOCUMENTATION_URL=/d' \
    -e '/^SUPPORT_URL=/d' \
    -e '/^BUG_REPORT_URL=/d' \
    -e '/^REDHAT_BUGZILLA_PRODUCT=/d' \
    -e '/^REDHAT_SUPPORT_PRODUCT=/d' \
    "$os_release"
cat >> "$os_release" <<EOF
NAME="AvethyOS"
PRETTY_NAME="AvethyOS ${release_version}"
VERSION="${release_version}"
DEFAULT_HOSTNAME="avethyos"
LOGO="avethyos-logo"
HOME_URL="https://github.com/5aether/avethyos"
DOCUMENTATION_URL="https://github.com/5aether/avethyos"
SUPPORT_URL="https://github.com/5aether/avethyos/issues"
BUG_REPORT_URL="https://github.com/5aether/avethyos/issues"
REDHAT_BUGZILLA_PRODUCT="AvethyOS"
REDHAT_SUPPORT_PRODUCT="AvethyOS"
EOF

printf 'AvethyOS release %s\n' "$release_version" > "${image_root}/usr/lib/fedora-release"
printf '%s\n' "AvethyOS ${release_version}" 'Kernel \r on an \m (\l)' > "${image_root}/usr/lib/issue"
printf 'AvethyOS %s\n' "$release_version" > "${image_root}/usr/lib/issue.net"

mkdir -p "${image_root}/etc/default"
ln -sfn ../usr/lib/os-release "${image_root}/etc/os-release"
ln -sfn ../usr/lib/fedora-release "${image_root}/etc/fedora-release"
ln -sfn fedora-release "${image_root}/etc/system-release"
ln -sfn fedora-release "${image_root}/etc/redhat-release"
ln -sfn ../usr/lib/issue "${image_root}/etc/issue"
ln -sfn ../usr/lib/issue.net "${image_root}/etc/issue.net"

grub_defaults="${image_root}/etc/default/grub"
if [[ -f "$grub_defaults" ]]; then
    sed -i '/^[[:space:]]*GRUB_DISTRIBUTOR=/d' "$grub_defaults"
fi
printf 'GRUB_DISTRIBUTOR="AvethyOS"\n' >> "$grub_defaults"
