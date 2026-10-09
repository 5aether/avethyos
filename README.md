# Custom bootc image

Fedora 44 bootc with Hyprland and Quickshell, without a GNOME or KDE desktop. Standard and NVIDIA variants share the same base layers.

Each installation has its own `RUN` instruction in `Containerfile`:

- `build_files/build.sh`: system files only.
- `build_files/layers/repo-tools.sh`: DNF repository plugins.
- `build_files/pre-install.sh`: RPM Fusion, tainted repositories, Cisco OpenH264, and the Hyprland and Topgrade COPRs.
- `build_files/layers/appstream.sh`: RPM Fusion application metadata.
- `build_files/layers/codecs.sh`: FFmpeg and multimedia codecs.
- `build_files/layers/firmware.sh`: RPM Fusion nonfree tainted firmware.
- `build_files/layers/hyprland.sh`: Hyprland, portals, audio, networking, Bluetooth, Kitty, Thunar, screenshots, and locking.
- `build_files/layers/quickshell.sh`: Quickshell, its QML modules and helpers, adw-gtk3, Papirus icons, fonts, and the compiled Avethy Qt theme.
- `build_files/layers/neovim.sh`: Neovim.
- `build_files/layers/steam.sh`: Steam and 32/64-bit Mesa graphics drivers.
- `build_files/layers/flatpak.sh`: Flatpak, Flathub, Bazaar, Flatseal, and their bundled runtimes.
- `build_files/layers/homebrew.sh`: Homebrew, build tools, and writable installation setup.
- `build_files/layers/sddm.sh`: SDDM, its Wayland greeter, and the Hyprland login session.
- `build_files/layers/silentsddm.sh`: SilentSDDM, its fonts, and theme settings.
- `build_files/layers/topgrade.sh`: Topgrade.
- `build_files/layers/desktop-configs.sh`: default Hyprland and Quickshell configuration.
- `build_files/layers/nvidia.sh`: NVIDIA drivers, kernel modules, and initramfs; NVIDIA variant only.
- `build_files/post-install.sh`: repository definitions and cache cleanup.

The standard variant is the default build. Weak dependencies are disabled; required dependencies remain. Steam requires x86_64. The NVIDIA variant additionally installs the requested driver packages, 32-bit NVIDIA libraries for Steam, and the tools needed to build modules for the image's kernel. It rebuilds the image's initramfs and disables Nouveau. Secure Boot signing with a trusted, persistent key is not configured; build-time signing keys are kept outside the final image.

Post-install removes the added repository definitions and the Cisco OpenH264 definition. Repository release RPMs and installed software remain. Fedora's main repositories remain available. Future rebuilds restore the added repositories through pre-install.

Add each future installation in a separate script and `RUN` instruction before post-install. Layers share dependencies and are deployed together as one bootc image. Rechunking changes these layer boundaries; CI preserves them.

Set your image name and organization in `image-template.env`, then use `just build`. Disk and generic installer builds use `disk_config/disk.toml` and `disk_config/iso.toml`.

The container build and GHCR publishing workflow builds both variants daily at 09:00 Europe/Rome, following daylight saving time. Publishing happens after the build completes. The default tags are `latest` and `nvidia`; custom default tags receive an `-nvidia` suffix for the NVIDIA variant.

The disk workflow builds both variants as QCOW2 disks and installer ISOs, with separate artifact names. Both ISOs use the same installer configuration and retain their selected image tag for updates.

To build both ISOs on GitHub:

1. Push the configuration and desktop folders to the repository's default branch.
2. Open **Actions → Build container image → Run workflow** and wait for both variants to publish successfully. Publishing requires the existing `SIGNING_SECRET` repository secret.
3. Open **Actions → Build disk images → Run workflow**, leaving S3 upload disabled.
4. Download the `standard-anaconda-iso` and `nvidia-anaconda-iso` artifacts, prefixed with your image name, from the completed run.

The local `quickshell/` folder contains a separate Git checkout. Commit its contents as ordinary files in this repository, or register it as a submodule with a `.gitmodules` file and publish its changes in that repository. GitHub checkout includes registered submodules recursively; an unregistered Git link does not supply the desktop files to CI.

Build both ISOs locally:

```bash
just rebuild-iso
just rebuild-iso-nvidia
```

The standard ISO is written to `output/bootiso/install.iso`; the NVIDIA ISO is written to `output/nvidia/bootiso/install.iso`. Use `just build-nvidia` to build only the NVIDIA container image, or `just build-iso-nvidia` to make its ISO from an existing image. Local builds use local image references; after installation, switch to the matching GHCR image tag to receive registry updates.

The root `hypr/` and `quickshell/` folders are copied into `/etc/skel/.config` in their own layer. New users receive them when their home directory is created. A globally enabled user service also copies missing files into existing users' `~/.config` directories at login, preserving existing files. Git data, editor settings, tests, Python caches, and local Qt build directories are excluded. Select a wallpaper after login; the original user's wallpaper is not bundled.

`quickshell-build.sh` builds the Avethy Qt 5 and Qt 6 plugins and regenerates the shell's shaders in a separate build stage. Tests are disabled there. Qt development packages stay in that stage; Homebrew adds its own compiler and build tools to the final image. The Quickshell layer installs the plugins under `/usr/lib64/avethyos/qt-theme` and shaders under `/usr/share/avethyos/quickshell/shaders`. Default configs link to these system artifacts; the palette generator copies the plugins into each user's theme directory. The runtime Qt base packages match the versions used for compilation. SF Pro Text falls back to the installed Noto Sans font.

Hyprland requires version 0.55 or newer for the Lua configuration, and the shell requires Quickshell 0.3 or newer for its Bluetooth, Polkit, and Lua integrations. It starts the shell through `/usr/libexec/avethyos-hyprland-session`, which imports the session environment and starts the portal session target. Hypridle handles the shell's lock button and locking before suspend. The default file manager is Thunar. DDC brightness needs a monitor that supports DDC/CI; ddcutil supplies the I2C module and permission rules.

SDDM is enabled and the default boot target is graphical. Its session chooser offers Hyprland, and configuration seeding completes before the compositor starts. The greeter uses Fedora's [generic Wayland backend](https://packages.fedoraproject.org/pkgs/sddm/sddm-wayland-generic/) with Weston. [SilentSDDM](https://github.com/uiriansan/SilentSDDM) is installed from its `main` branch, including fonts and the requested virtual keyboard settings in `/etc/sddm.conf`. The greeter account does not receive user desktop configuration.

The Homebrew layer runs the official installer non-interactively as the dedicated `linuxbrew` account and stores the result under `/usr/share/avethyos/homebrew`. At boot, `avethyos-homebrew.service` restores it to writable `/home/linuxbrew/.linuxbrew` before user sessions start. Existing installations and packages survive image updates. This uses [Homebrew's default Linux prefix](https://docs.brew.sh/Homebrew-on-Linux) and [dedicated owner setup](https://docs.brew.sh/Installation#running-as-the-homebrew-owner). Homebrew tools are on the user session and login shell paths. Users in `wheel` can run `brew install`, `brew upgrade`, and other Brew commands through a wrapper that runs them as `linuxbrew`; other users can run installed tools.

Topgrade is installed in its own layer. Its `lilay/topgrade` COPR is enabled in pre-install and removed in post-install for both variants.

The Flatpak layer downloads Bazaar, Flatseal, and their dependencies into `/usr/share/avethyos/flatpak-seed`. At boot, `avethyos-flatpak-preinstall.service` uses Flatpak's preinstall support and this local repository to install them into writable `/var/lib/flatpak` for all users. This keeps the applications usable by Bazaar across bootc updates and honors applications users uninstall. Their GNOME runtime is a sandbox dependency and does not add a GNOME desktop to the host. Flathub remains configured for future app installations and updates.

The wallpaper palette generator seeds both Flatpak profiles before first launch, writes their GTK 3/4 CSS and settings, and grants read-only access to the generated host theme directories. Host Qt plugins are used by native applications; Flatpak Qt runtimes need their own compatible theme plugins. Existing GTK applications may need reopening after changing the palette. The Flatpak layer follows [Flatpak's sideload and preinstall support](https://docs.flatpak.org/en/latest/flatpak-command-reference.html); the theme setup follows the [GTK CSS lookup paths](https://docs.gtk.org/gtk4/class.CssProvider.html).
