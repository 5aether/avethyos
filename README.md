# AvethyOS

AvethyOS is a Fedora desktop made for everyday use and gaming. Hyprland arranges
windows, and the Quickshell bar gives you your apps, settings, music, notifications,
and wallpapers. The operating system arrives as one tested image. Your files,
installed apps, and personal settings stay separate from that image.

You do not need to learn Linux commands to use the desktop. The examples below
are optional shortcuts: open the terminal with **Windows + T**, paste a command,
and press Enter. `sudo` asks for your login password when a system change needs it.

## Choose your version

| Your graphics card | Image | What it includes |
| --- | --- | --- |
| AMD or Intel | `ghcr.io/5aether/avethyos:latest` | The standard desktop and gaming tools. |
| NVIDIA | `ghcr.io/5aether/avethyos:nvidia` | The same desktop, with the NVIDIA driver built for its kernel. |

The standard image contains no NVIDIA driver. The NVIDIA image uses the open
NVIDIA kernel driver, so your card must support that driver.

Installer ISOs are created automatically after a successful image release.
Open **Actions → Build installer ISOs**, choose a successful run, and download
the artifact for your version. Extract it and write the named `.iso` file to a
USB drive with an image-writing application. Start your PC from that drive and
choose your disk, language, and account in the installer. The artifact also
includes a SHA-256 checksum. Maintainers can run the ISO workflow manually to
recreate an installer from a previous successful release.

## What is included

- Hyprland, the Quickshell desktop, the SilentSDDM login screen, screen locking,
  screenshots, and clipboard history for text and images.
- A launcher that finds native, Flatpak, and exported Distrobox applications.
  Installing or removing an app updates the launcher without restarting it.
- Wi-Fi, Ethernet, Bluetooth, audio controls, monitor brightness, night light,
  notifications, a system tray, and controls for compatible music/video players.
- Image and video wallpapers, wallpaper colors, Papirus icons, fonts, and matching
  GTK and Qt appearance.
- Nautilus for files, GNOME Disks for drives, archive tools, file previews,
  thumbnails, online-account support, and access to supported network shares.
- Steam, Gamescope, GameMode, MangoHud, graphics libraries for 64-bit and 32-bit
  games, media codecs, firmware, and the Open Gaming Collective kernel.
- Flatpak with Flathub, Bazaar as an app store, and Flatseal for app permissions.
- Distrobox and its host dependencies for running software from other Linux
  distributions, BoxBuddy for managing containers with a graphical interface,
  plus Homebrew for command-line tools and Topgrade.
- Fedora's real Fastfetch RPM package, using its normal upstream output.
- Discord RPC integration between native and Flatpak apps and clients that
  provide a Discord-compatible RPC service.

## Everyday shortcuts

**Windows** means the Super key, often marked with the Windows logo.

| Shortcut | Action |
| --- | --- |
| Windows + T | Open the terminal. |
| Windows + E | Open files. |
| Windows + W | Open the control center. |
| Windows + N | Open notifications and the clock. |
| Windows + V | Open clipboard history. |
| Windows + C | Close the current window. |
| Windows + F | Toggle fullscreen. |
| Windows + Space | Toggle a floating window. |
| Windows + 1…0 | Switch to workspaces 1…10. |
| Windows + Ctrl + 1…0 | Move the current window to that workspace. |
| Windows + A | Restart the desktop bar. |

Click the bar's app button to open the launcher. The control center has network,
Bluetooth, audio, display, and other desktop controls. Media controls appear when
a compatible player is running. Hold Windows to see workspace numbers in place of
app icons.

## Apps and extra tools

Open **Bazaar** from the launcher to find and install desktop apps. **Flatseal**
lets you review their permissions.

The same tasks work from the terminal:

```bash
avethyos apps store
avethyos apps search firefox
avethyos apps install org.mozilla.firefox
avethyos apps list
avethyos apps remove org.mozilla.firefox
```

New CLI installs use your account's Flatpak installation. Add `--system` to an
install/remove command to manage apps shared by all users, or use Bazaar.
Flatpak apps update independently of the operating
system. Run `flatpak update` when you want to update them.

For command-line tools, use Homebrew:

```bash
avethyos tools search ripgrep
avethyos tools install ripgrep
avethyos tools list
```

Native RPM packages belong in the image: add them to your personal image's
`packages.txt`, described below. Installing host packages with rpm-ostree creates
local layering and can prevent bootc updates. [Bootc and rpm-ostree](https://bootc.dev/bootc/bootc-relationships.7.html)

## Software from other Linux distributions

Distrobox runs a Linux environment inside a container while sharing your desktop,
home folder, sound, and graphics. Its host tools are already installed. Creating
a container downloads its image; its first start may install that distribution's
internal integration packages automatically. Nothing extra needs installing on
the host.

Open **BoxBuddy** from the launcher to create and manage containers with buttons.
`avethyos box gui` opens the same interface from the terminal.

Create and open a Fedora box:

```bash
avethyos box create my-apps
avethyos box enter my-apps
```

Inside it, install the app with that distribution's package manager. For example:

```bash
sudo dnf install gimp
exit
```

Back on AvethyOS, add it to the launcher:

```bash
avethyos box export my-apps gimp
```

The exported app appears in Quickshell automatically, with its icon, and opens
inside the box when clicked. Only apps with a desktop entry can be exported.
`avethyos box unexport my-apps gimp` removes the launcher shortcut.
[How Distrobox exports work](https://distrobox.it/usage/distrobox-export/)

Use `avethyos box create my-apps --nvidia` on an NVIDIA system when the container
needs the host driver. `--image` selects another distribution; inside it, use its
own package manager. Run `avethyos box list`, `avethyos box upgrade my-apps`, or
`avethyos box remove my-apps` to manage your boxes.

## Gaming

Steam is included. GameMode adjusts system settings while a supported game is
running. MangoHud displays performance information. Gamescope runs games in a
separate compositor, which can help with fullscreen and resolution handling.

In **Steam → game Properties → Launch Options**, choose what you need:

| Launch options | Result |
| --- | --- |
| `gamemoderun %command%` | Use GameMode. |
| `gamemoderun mangohud %command%` | Use GameMode and MangoHud. |
| `gamemoderun gamescope -f --mangoapp -- %command%` | Use fullscreen Gamescope with its MangoHud overlay. |

To test GameMode, run `avethyos gaming test`. For a game outside Steam:

```bash
avethyos gaming run --hud --gamescope -- /path/to/game
```

Edit your own gaming preferences with `avethyos config edit mangohud` or
`avethyos config edit gamemode`. Flatpak games use their own runtimes and may need
the corresponding Flatpak extensions; host RPM tools do not inject libraries
into a sandbox automatically.

## Discord activity and RPC

RPC is the connection an app uses to send activity to Discord, such as a game
name, song, or playback position. AvethyOS connects the standard Discord IPC
sockets across native and Flatpak locations. Discovery follows the running
client's sockets rather than a fixed list of Discord client names.

Open your Discord client, enable its activity/Rich Presence setting, and enable
RPC in the sending app or its plugin. Official Discord and alternative clients
must actually provide an RPC service. Steam games, media-player integrations,
and other apps that already send Discord RPC use the same connection.
A media player that only exposes desktop media controls needs its own Rich
Presence integration to publish that information to Discord.

Steam's Linux runtime is given read-only access to the RPC directory. For Windows
games, select **GE-Proton 11 or newer** in the game's **Properties → Compatibility**.
Its built-in Discord bridge is enabled by the AvethyOS session. You can install
GE-Proton through **ProtonUp-Qt**, available in Bazaar. Standard Valve Proton does
not provide that bridge; the Linux IPC connection alone cannot replace it.
[GE-Proton's built-in bridge](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-1),
[Steam runtime directory sharing](https://github.com/ValveSoftware/steam-runtime/blob/master/doc/steamlinuxruntime-known-issues.md#sharing-directories-with-the-container)

`avethyos service rpc status` shows the integration service. Permission changes
apply when Flatpak apps next start: fully close and reopen an already-running
Flatpak after updating the image. App-specific permission denials in Flatseal
can still block access. A browser tab by itself does not provide Discord's local
IPC service.

## Make the desktop yours

Most everyday changes are available in the control center and wallpaper menu.
The terminal also exposes every setting in the shell's settings file:

```bash
avethyos config list
avethyos wallpaper ~/Pictures/wallpaper.png
avethyos config set appearance.icon-pack Papirus
avethyos config set notifications.doNotDisturb on
avethyos config set display.nightLightEnabled on
avethyos config set display.nightLightTemperature 3500
```

The running shell reads these changes automatically. To change shortcuts, screen
layout, keyboard/mouse preferences, window appearance, or lock/idle settings, open
the corresponding commented file:

```bash
avethyos config edit shortcuts
avethyos config edit monitors
avethyos config edit input
avethyos config edit appearance
avethyos config edit rules
avethyos config edit custom
avethyos config edit lock
avethyos config edit idle
```

The editor defaults to Nano. **Ctrl + O**, then Enter saves; **Ctrl + X** closes it.
These are user commands: run them without `sudo`. `avethyos shell reload` reloads
Hyprland, and `avethyos shell restart` restarts the bar. You can toggle a panel with
`avethyos shell apps`, `settings`, `notifications`, `clipboard`, or `media`.

For the computer itself:

```bash
avethyos system hostname my-pc
avethyos system timezone Europe/Rome
avethyos system locale en_US.UTF-8
avethyos service bluetooth status
avethyos service ssh on
```

System changes ask for administrative access. Services accept `status`, `on`, and
`off`; available names are `bluetooth`, `network`, `ssh`, `auto-updates`, and `rpc`.
SSH is installed but stays disabled until you enable it. A chosen language needs
its matching Fedora language package in the image.

## Updates and recovery

Automatic updates download and stage the next OS in the background. They stay
quiet and never restart the computer. You choose when to restart. This policy
applies to standard, NVIDIA, and personal images. To turn background downloads
off, run `avethyos service auto-updates off`; use `on` to enable them again.
On an older image, turn automatic updates off before staging your first update
to this version. Re-enable them after your own manual restart into the new OS.

When you choose to update, run:

```bash
avethyos update
```

This downloads and stages the new OS. It never reboots automatically. Restart
your PC when you are ready. `avethyos status` shows the current and staged images.
Your files and preferences stay in place, and bootc keeps the previous OS for
recovery. `avethyos rollback` stages that previous version for the next boot.

`avethyos update --all` also updates Flatpaks, Homebrew tools, and Distrobox
containers. Updates inside a container follow that distribution's rules.
The underlying OS update command remains `sudo bootc upgrade`.

The image's shell and Hyprland code update together with the OS. Your shortcuts,
monitor layout, wallpaper, and other personal settings survive updates. On the
first upgrade from the old home-folder desktop layout, supported preferences are
migrated and old files are backed up in `~/.local/state/avethyos/legacy-desktop/`.

If something needs checking, run `avethyos doctor`. `avethyos --help` lists all
commands, and adding `--help` after any group explains its options. Short
maintenance recipes are available through `avethyos recipes`, following the
[Just/ujust approach used by Bazzite](https://github.com/ublue-os/bazzite/tree/main/system_files/desktop/shared/usr/share/ublue-os/just).
`avethyos readme` opens this guide even without an internet connection.

## Kernel preferences

The kernel controls hardware. Only change a kernel setting when you know which
setting your hardware needs. For Apple keyboards, this selects F1–F12 first:

```bash
sudo avethyos fnmode 2
```

Use `default` to remove that override. Other modes are `0` disabled, `1` media
first, `3` automatic, and `4` F keys disabled.

```bash
avethyos kernel show
sudo avethyos kernel set hid_apple.fnmode=2
sudo avethyos kernel add console=tty0 console=ttyS0
sudo avethyos kernel remove console=ttyS0
sudo avethyos kernel remove console
sudo avethyos kernel reset
```

`set` replaces your values for the named setting; `add` allows repeated names;
`remove` accepts a name or an exact value; `reset` clears only arguments managed
by this command. Pass each argument separately. Whitespace, quotes, and
backslashes inside argument values are rejected.

Preferences are saved in `/etc/avethyos/kernel-arguments.json` and applied with
bootc's native argument-source API. They survive image updates. Changes take
effect on your next boot. If applying fails, resolve the reported error and retry
with `sudo avethyos kernel apply`. [Bootc argument sources](https://bootc.dev/bootc/internals/bootc_lib/loader_entries/index.html)

## Your own AvethyOS image

The separate [avethyos-personal repository](https://github.com/5aether/avethyos-personal)
is a small template that starts from a successfully published AvethyOS image.
Fork or copy it to keep your changes and its build workflow in a public or private
GitHub repository. You do not need the main operating system sources.

Choose exactly one version in `image.conf`:

```ini
VARIANT=standard
IMAGE_NAME=avethyos-personal
```

Change `standard` to `nvidia` only when you want the NVIDIA version. The workflow
builds one image; it does not build an unused second version.

Add Fedora package names to `packages.txt`, one per line. Change image-wide kernel
arguments in `kernel-arguments.toml`. Put additional system files under `files/`,
following their destination paths. Every configuration file includes examples.
Flatpak app IDs go in `flatpak-packages.txt`; use `remove-flatpak-packages.txt`
to remove apps managed by your image. These lists also apply after OS upgrades.

Follow the [personal-image guide](https://github.com/5aether/avethyos-personal#readme)
to fork or clone the template, enable Actions, and use your image. Your default
branch publishes your image and then creates its installer ISO. The separate
personal repository builds its own image; the main OS repository never builds
personal images.

For a private registry, save a GitHub token with `read:packages` on the PC:

```bash
avethyos image login YOUR-GITHUB-NAME
```

The command asks for the token without displaying it and saves it in
`/etc/ostree/auth.json`, readable only by root. Bootc uses this persistent file for
future manual and automatic updates. Your token needs access to the private
package; repository visibility and package visibility are separate settings.
Credentials are never added to an image or its source files.
[Bootc registry authentication](https://bootc.dev/bootc/registries-and-offline.html)

After your personal image finishes building, switch once:

```bash
avethyos image switch ghcr.io/YOUR-GITHUB-NAME/avethyos-personal:latest
```

Restart when you choose. Continue using `avethyos update` or `sudo bootc upgrade`
afterward; they follow your personal image's `latest` tag.

## Daily builds and personal build order

The main build is scheduled **every day at 09:00 Europe/Rome**, including daylight
saving changes. It also builds on main-branch changes and manual runs. Both image
variants must pass the release checks.

Personal images use an exact image digest from a completed, successful main
release. They never build on top of a failed or still-running main release. An
unchanged base and unchanged personal files do not cause another image build.

For immediate triggering across repositories, the main repository's maintainer
configures `PERSONAL_IMAGE_REPOS` and `PERSONAL_IMAGE_DISPATCH_TOKEN` as explained
in the personal guide. A separate completion workflow sends the event only after
the whole main release succeeds. Without that connection, personal repositories
check for successful releases every five minutes. GitHub does not send another
repository's `workflow_run` event to a fork automatically.

GitHub can delay or drop scheduled jobs, and may disable schedules in inactive
public repositories. The 09:00 schedule is configured, but GitHub Actions cannot
guarantee an exact daily start time. Strict timing requires an external scheduler
that calls the workflow-dispatch API. [GitHub scheduling behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

## For contributors

| Path | Purpose |
| --- | --- |
| `Containerfile` | Image stages, including standard and NVIDIA endings. |
| `build_files/layers/` | Small build steps grouped by feature. |
| `build_files/ci/` | Source, image, inventory, and release-notification checks. |
| `system_files/` | Files installed into the OS, including the modular CLI. |
| `hypr/` | Managed Hyprland integration and commented user defaults. |
| `quickshell/` | Desktop code, helpers, assets, and desktop tests. |
| `tests/` | Isolated system-helper and release-notification tests. |
| `.github/workflows/` | Image releases, installer creation, and personal notifications. |

Local image work needs Podman, Skopeo, Just, and jq:

```bash
just build
just rechunk
just check-image
```

For NVIDIA, use `just build-nvidia`, `just rechunk avethyos nvidia`, and
`just check-image avethyos nvidia nvidia`. `just build-iso` creates an installer
from a local image. `just` lists the other development commands.

CI checks source syntax and tests, resolves upstream images to digests, checks
the kernel/initramfs and package dependencies, validates installed desktop assets,
runs offscreen shell integration, and generates software inventories. Releases
are signed using `SIGNING_SECRET`, checked against `cosign.pub`, and verified
before the update tags move. Pull requests validate images without publishing.
Build evidence is retained for 14 days. These checks do not replace testing a
booted system on hardware.

Published images use reusable content layers to reduce update downloads. A small
change can reuse most of the previous image; large package or Fedora upgrades can
still require large downloads.

Installed system code lives in `/usr/share/avethyos/`. Writable preferences live
in `~/.config/hypr/` and `~/.local/state/avethyos/`. Custom `XDG_CONFIG_HOME`,
`XDG_STATE_HOME`, and `XDG_DATA_HOME` paths are supported. User files are seeded
only when missing; updates do not overwrite them.
