#!/bin/bash
set -euo pipefail

kernel_version=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n')
if [[ $kernel_version == *$'\n'* || $kernel_version != *-ogc* ]]; then
    printf 'Expected one installed OGC kernel-core package, got: %s\n' "$kernel_version" >&2
    exit 1
fi

kernel_devel_rpm="/kernel-rpms/kernel-devel-${kernel_version}.rpm"
kernel_devel_matched_rpm="/kernel-rpms/kernel-devel-matched-${kernel_version}.rpm"
for kernel_rpm in "$kernel_devel_rpm" "$kernel_devel_matched_rpm"; do
    if [[ ! -r $kernel_rpm ]]; then
        printf 'Missing matching OGC kernel development package: %s\n' "$kernel_rpm" >&2
        exit 1
    fi
done

# Select RPM Fusion's bundled open modules before its package or akmods runs.
install -d /etc/rpm
printf '%%_with_kmod_nvidia_open 1\n' > /etc/rpm/macros.nvidia-kmod

dnf5 install -y --setopt=install_weak_deps=False \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    vulkan \
    xorg-x11-drv-nvidia-cuda-libs \
    libva-nvidia-driver \
    libva-utils \
    vdpauinfo \
    xorg-x11-drv-nvidia-libs.i686 \
    xorg-x11-drv-nvidia-cuda-libs.i686 \
    "$kernel_devel_rpm" \
    "$kernel_devel_matched_rpm" \
    gcc \
    make \
    elfutils-libelf-devel \
    dracut

if [[ $(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n') != "$kernel_version" ]]; then
    printf 'NVIDIA dependencies changed the selected OGC kernel: %s\n' "$kernel_version" >&2
    exit 1
fi
if [[ ! -r /usr/lib/modules/${kernel_version}/build/Makefile ]]; then
    printf 'Missing development files for OGC kernel: %s\n' "$kernel_version" >&2
    exit 1
fi
dnf5 versionlock add kernel-devel kernel-devel-matched

akmods --force --kernels "$kernel_version"
depmod -a "$kernel_version"
driver_version=$(rpm -q xorg-x11-drv-nvidia --queryformat '%{VERSION}')
for module in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
    vermagic=$(modinfo -k "$kernel_version" -F vermagic "$module")
    if [[ "${vermagic%% *}" != "$kernel_version" ||
          "$(modinfo -k "$kernel_version" -F version "$module")" != "$driver_version" ]]; then
        printf 'NVIDIA module %s does not match driver %s and kernel %s.\n' \
            "$module" "$driver_version" "$kernel_version" >&2
        exit 1
    fi
done
if [[ "$(modinfo -k "$kernel_version" -F license nvidia)" != 'Dual MIT/GPL' ]]; then
    echo 'The NVIDIA build did not select the open kernel module.' >&2
    exit 1
fi

# Kernel modules are built into the image; runtime builds cannot modify /usr.
# Build-time signing keys are ephemeral, so runtime key generation is unnecessary.
systemctl --no-reload mask \
    akmods.service \
    akmods@.service \
    akmods-shutdown.service \
    akmods-keygen@.service \
    akmods-keygen.target

mkdir -p /usr/lib/modprobe.d /usr/lib/dracut/dracut.conf.d

cat > /usr/lib/modprobe.d/avethyos-nvidia.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
options nvidia_drm modeset=1 fbdev=1
EOF

cat > /usr/lib/dracut/dracut.conf.d/90-avethyos-nvidia.conf <<'EOF'
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
omit_drivers+=" nouveau "
EOF
