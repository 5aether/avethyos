#!/bin/bash
set -euo pipefail

# OGC's official Fedora artifact contains the kernel and its matching RPMs.
shopt -s nullglob
core_rpms=(/kernel-rpms/kernel-core-*.rpm)
if (( ${#core_rpms[@]} != 1 )); then
    echo 'Expected exactly one OGC kernel-core RPM' >&2
    exit 1
fi

kernel_version=$(rpm -qp --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "${core_rpms[0]}")
fedora_release=$(rpm --eval '%fedora')
architecture=$(rpm --eval '%{_arch}')
if [[ $kernel_version != *-ogc*.fc${fedora_release}.${architecture} ]]; then
    printf 'OGC kernel does not match Fedora %s/%s: %s\n' "$fedora_release" "$architecture" "$kernel_version" >&2
    exit 1
fi

kernel_rpms=()
for package in kernel kernel-core kernel-modules; do
    kernel_rpm="/kernel-rpms/${package}-${kernel_version}.rpm"
    if [[ ! -r $kernel_rpm ]] || [[ $(rpm -qp --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$kernel_rpm") != "${package}-${kernel_version}" ]]; then
        printf 'Missing or mismatched OGC kernel RPM: %s\n' "$kernel_rpm" >&2
        exit 1
    fi
    kernel_rpms+=("$kernel_rpm")
done

# Kernel RPM scriptlets update a host's bootloader. Skip them in these kernel
# transactions and generate the bootc initramfs explicitly after all layers.

old_kernel_versions=()
if rpm -q kernel-core >/dev/null 2>&1; then
    mapfile -t old_kernel_versions < <(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n')
fi
old_kernel_packages=()
for package in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-devel kernel-devel-matched kernel-uki-virt; do
    if rpm -q "$package" >/dev/null 2>&1; then
        old_kernel_packages+=("$package")
    fi
done
if (( ${#old_kernel_packages[@]} )); then
    dnf5 remove -y --no-autoremove \
        --setopt=protect_running_kernel=False \
        --setopt=tsflags=nodocs,noscripts "${old_kernel_packages[@]}"
fi
# The base initramfs is generated content outside the old RPM file lists.
for old_kernel_version in "${old_kernel_versions[@]}"; do
    rm -rf "/usr/lib/modules/${old_kernel_version}"
done

dnf5 install -y --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs,noscripts "${kernel_rpms[@]}"
if [[ $(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}') != "$kernel_version" ]]; then
    echo 'The image must contain exactly the selected OGC kernel' >&2
    exit 1
fi
test -s "/usr/lib/modules/${kernel_version}/vmlinuz"
# bootc deploys the kernel from /usr/lib/modules and requires an empty /boot.
# Keep the copy next to vmlinuz; OGC also packages a redundant copy in /boot.
rm -f "/boot/.vmlinuz-${kernel_version}.hmac"
# Later image layers must not pull a stock Fedora kernel back in.
dnf5 versionlock add kernel kernel-core kernel-modules
