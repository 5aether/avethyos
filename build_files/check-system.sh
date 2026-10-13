#!/bin/bash
set -euo pipefail

variant="${1:?Specify standard or nvidia}"
case "$variant" in
    standard|nvidia) ;;
    *) printf 'Unknown image variant: %s\n' "$variant" >&2; exit 1 ;;
esac

# Inspect the pristine filesystem before runtime checks create their caches.
# systemd-analyze verify runs generators and writes into /run and root's cache.
bootc container lint --fatal-warnings

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
    python3 nano just openssh-server fastfetch steam gamescope \
    gamemode.x86_64 gamemode.i686 mangohud.x86_64 mangohud.i686 \
    distrobox podman crun conmon catatonit passt fuse-overlayfs \
    shadow-utils shadow-utils-subid which pciutils
command -v python3 avethyos nano just sudo hostnamectl timedatectl localectl hyprctl \
    Hyprland qs sddm fastfetch gamescope gamemoded gamemoderun mangoapp mangohud \
    distrobox-create distrobox-enter distrobox-export podman pasta \
    fuse-overlayfs newuidmap newgidmap getsubids kitty which lspci
[[ "$(rpm -qf --queryformat '%{NAME}' /usr/bin/python3)" == python3 ]]
# Import every command group using the installed Python and installed modules.
# Help parses all options without touching the running system or user files.
/usr/bin/avethyos --help >/dev/null
for command in kernel fnmode config wallpaper shell apps tools box gaming status update \
    rollback image system service doctor readme recipes; do
    /usr/bin/avethyos "$command" --help >/dev/null
done
[[ "$(rpm -qf --queryformat '%{NAME}' /usr/bin/fastfetch)" == fastfetch ]]
test -s /usr/share/dbus-1/services/com.feralinteractive.GameMode.service
getent group gamemode
[[ "$(systemctl --root=/ is-enabled sshd.service || true)" == disabled ]]
test -s /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/90-stage-only.conf
systemd-analyze verify bootc-fetch-apply-updates.service
dnf5 --setopt=logdir=/run/dnf check --dependencies

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
test -s /usr/share/doc/avethyos/LICENSE
test -x /usr/libexec/avethyos-discord-rpc
test -s /usr/lib/user-tmpfiles.d/avethyos-discord-rpc.conf
test -s /usr/share/avethyos/recipes.just
test -x /usr/libexec/avethyos-homebrew-bootstrap
test -s /usr/share/flatpak/remotes.d/flathub.flatpakrepo
test -d /usr/share/avethyos/flatpak-seed
[[ -n "$(find /usr/share/avethyos/flatpak-seed -type f -print -quit)" ]]
grep -Fq '[Flatpak Preinstall io.github.dvlv.boxbuddyrs]' \
    /usr/share/flatpak/preinstall.d/avethyos.preinstall
# The temporary build policy must not replace the installed package policy.
test ! -s /etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf

if [[ "$variant" == nvidia ]]; then
    rpm -q akmod-nvidia xorg-x11-drv-nvidia-cuda libva-nvidia-driver
    [[ "$(modinfo -k "$kernel_version" -F license nvidia)" == 'Dual MIT/GPL' ]]
    driver_version=$(rpm -q xorg-x11-drv-nvidia --queryformat '%{VERSION}')
    for module in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        vermagic=$(modinfo -k "$kernel_version" -F vermagic "$module")
        if [[ "${vermagic%% *}" != "$kernel_version" ||
              "$(modinfo -k "$kernel_version" -F version "$module")" != "$driver_version" ]]; then
            printf 'NVIDIA module %s does not match driver %s and kernel %s.\n' \
                "$module" "$driver_version" "$kernel_version" >&2
            exit 1
        fi
        module_file=$(basename "$(modinfo -k "$kernel_version" -F filename "$module")")
        if ! grep -Fq "/${module_file}" "$initramfs_listing"; then
            printf 'The initramfs is missing NVIDIA module %s.\n' "$module_file" >&2
            exit 1
        fi
    done
    # Upgrades must use the prebuilt drivers instead of rebuilding in /usr.
    [[ "$(systemctl --root=/ is-enabled akmods.service || true)" == masked ]]
elif rpm -q akmod-nvidia >/dev/null 2>&1 || rpm -q akmod-nvidia-open >/dev/null 2>&1; then
    echo 'The standard image unexpectedly contains the NVIDIA driver.' >&2
    exit 1
fi

printf 'System checks passed: %s, Fedora %s, kernel %s.\n' "$variant" "$VERSION_ID" "$kernel_version"
