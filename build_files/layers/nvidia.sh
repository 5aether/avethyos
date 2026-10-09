#!/bin/bash
set -euo pipefail

kernel_version=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')

dnf5 install -y --setopt=install_weak_deps=False \
    akmod-nvidia-open \
    xorg-x11-drv-nvidia-cuda \
    vulkan \
    xorg-x11-drv-nvidia-cuda-libs \
    libva-nvidia-driver \
    libva-utils \
    vdpauinfo \
    xorg-x11-drv-nvidia-libs.i686 \
    xorg-x11-drv-nvidia-cuda-libs.i686 \
    "kernel-devel-${kernel_version}" \
    gcc \
    make \
    elfutils-libelf-devel \
    dracut

akmods --force --kernels "$kernel_version"
depmod -a "$kernel_version"

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

DRACUT_NO_XATTR=1 dracut --force --no-hostonly \
    "/usr/lib/modules/${kernel_version}/initramfs.img" "$kernel_version"
