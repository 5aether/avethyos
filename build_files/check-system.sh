#!/bin/bash
set -euo pipefail

variant="${1:?Specify standard or nvidia}"
case "$variant" in
    standard|nvidia) ;;
    *) printf 'Unknown image variant: %s\n' "$variant" >&2; exit 1 ;;
esac

# These checks inspect the image's kernel, never the runner's running kernel.
# shellcheck source=/dev/null
source /usr/lib/os-release
[[ "$ID" == fedora && "$NAME" == AvethyOS ]]
[[ "$VERSION_ID" == "$(rpm --eval '%fedora')" ]]
if [[ -n "${EXPECTED_FEDORA_VERSION:-}" ]]; then
    [[ "$VERSION_ID" == "$EXPECTED_FEDORA_VERSION" ]]
fi

rpm -q bootc ostree kernel-core kernel-modules hyprland hypridle hyprlock quickshell sddm \
    gnome-disk-utility NetworkManager bluez pipewire wireplumber flatpak \
    nano just openssh-server fastfetch steam gamescope \
    gamemode.x86_64 gamemode.i686 mangohud.x86_64 mangohud.i686 \
    distrobox podman crun conmon catatonit passt fuse-overlayfs \
    shadow-utils shadow-utils-subid
command -v Hyprland qs sddm fastfetch gamescope gamemoderun mangoapp mangohud \
    distrobox-create distrobox-enter distrobox-export podman pasta \
    fuse-overlayfs newuidmap newgidmap getsubids
[[ "$(rpm -qf --queryformat '%{NAME}' /usr/bin/fastfetch)" == fastfetch ]]
test -s /usr/share/dbus-1/services/com.feralinteractive.GameMode.service
getent group gamemode
[[ "$(systemctl --root=/ is-enabled sshd.service || true)" == disabled ]]
dnf5 check --dependencies
bootc container lint

kernel_version=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n')
architecture=$(rpm --eval '%{_arch}')
[[ "$kernel_version" != *$'\n'* && "$kernel_version" == *-ogc*.fc${VERSION_ID}.${architecture} ]]
test -s "/usr/lib/modules/${kernel_version}/vmlinuz"
test -s "/usr/lib/modules/${kernel_version}/initramfs.img"
initramfs_listing=$(mktemp)
trap 'rm -f "$initramfs_listing"' EXIT
lsinitrd "/usr/lib/modules/${kernel_version}/initramfs.img" > "$initramfs_listing"

# Query enablement on disk; no system bus or running services are needed.
for service in sddm.service NetworkManager.service bluetooth.service \
    avethyos-fstab-compat.service avethyos-flatpak-preinstall.service \
    avethyos-homebrew.service avethyos-user-access.service; do
    [[ "$(systemctl --root=/ is-enabled "$service")" == enabled ]]
done
[[ "$(basename "$(readlink -f /etc/systemd/system/display-manager.service)")" == sddm.service ]]
[[ "$(basename "$(readlink -f /etc/systemd/system/default.target)")" == graphical.target ]]
for service in avethyos-user-config.service avethyos-discord-rpc.service \
    systemd-tmpfiles-setup.service pipewire.socket pipewire-pulse.socket wireplumber.service; do
    [[ "$(systemctl --root=/ --global is-enabled "$service")" == enabled ]]
done

test -s /usr/share/doc/avethyos/README.md
test -s /usr/share/doc/avethyos/personal/README.md
test -s /usr/share/doc/avethyos/LICENSE
test -x /usr/libexec/avethyos-discord-rpc
test -s /usr/lib/user-tmpfiles.d/avethyos-discord-rpc.conf
test -s /usr/share/avethyos/recipes.just
test -x /usr/libexec/avethyos-homebrew-bootstrap
test -s /usr/share/flatpak/remotes.d/flathub.flatpakrepo
test -d /usr/share/avethyos/flatpak-seed
[[ -n "$(find /usr/share/avethyos/flatpak-seed -type f -print -quit)" ]]
# The temporary build policy must not replace the installed package policy.
test ! -s /etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf

if [[ "$variant" == nvidia ]]; then
    rpm -q akmod-nvidia-open xorg-x11-drv-nvidia-cuda libva-nvidia-driver
    for module in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        vermagic=$(modinfo -k "$kernel_version" -F vermagic "$module")
        [[ "${vermagic%% *}" == "$kernel_version" ]]
        grep -Eq "/${module}\.ko(\.(xz|zst|gz))?$" "$initramfs_listing"
    done
    # Upgrades must use the prebuilt drivers instead of rebuilding in /usr.
    [[ "$(systemctl --root=/ is-enabled akmods.service || true)" == masked ]]
elif rpm -q akmod-nvidia-open >/dev/null 2>&1; then
    echo 'The standard image unexpectedly contains the NVIDIA driver.' >&2
    exit 1
fi

printf 'System checks passed: %s, Fedora %s, kernel %s.\n' "$variant" "$VERSION_ID" "$kernel_version"
