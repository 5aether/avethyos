# Quickshell desktop shell

A Wayland desktop shell for Hyprland, written in QML for
[Quickshell](https://github.com/quickshell-mirror/quickshell). Video wallpaper
plays through Qt Multimedia's FFmpeg backend.

## Layout

Each directory holds one role, so a file's location tells you what it is.

| Path | Contents |
| --- | --- |
| `shell.qml` | Entry point. Creates the bar on every output, shared overlays, and IPC routes. |
| `bar/` | The top bar and everything inside it (launcher, workspaces, clock, media, tray, control center). |
| `overlays/` | Transient panels drawn above the bar: notification toasts and the polkit prompt. |
| `background/` | The wallpaper video surface, one instance per output. |
| `components/` | **Singletons only.** Shared state and services; no windows live here. |
| `widgets/` | Shared visual surfaces for bar popups and overlays. |
| `modules/` | Pure JavaScript helpers with no Qt dependency, so they can be unit tested. |
| `assets/` | Fonts and compiled Qt shaders. |
| `scripts/` | The launcher and helpers that cannot use native Quickshell APIs. |
| `tests/` | Unit tests and a structural QML check. |
| `config.ini` | Initial defaults, copied only when user state has no settings yet. |

The bootc image installs this tree at `/usr/share/avethyos/quickshell` and
native Qt plugins at `/usr/lib64/avethyos/qt-theme`. Launchers, IPC helpers,
QML imports, fonts and shaders use those image assets, so deploying a new image
updates the shell on the next boot. Run `scripts/run.sh` from a checkout for
development; code paths are resolved relative to that checkout.

### Why the singletons are separate

`components/qmldir` declares the shared singletons: `Theme`, `Config`,
`WallpaperManager`, `NotificationManager`, `NotificationStore` and
`PolkitManager`. Each must be the **only** instance of its type in the shell —
a second `NotificationServer` or `PolkitAgent` would fight over the D-Bus name
with the first. Keeping them in one module that every window imports makes that
impossible to get wrong by accident.

### Every directory is a QML module

Each of `components/`, `bar/`, `overlays/` and `background/` has its own
`qmldir` listing the types it provides, and `shell.qml` imports the module by
directory (`import "bar"`). This matters: a directory import without a `qmldir`
resolves no types at all, which fails as `PolkitDialog is not a type`.

When you add a QML file to one of those directories, **add it to that
directory's `qmldir`** in the same step or it will not be found.

## Settings

Settings live at `${XDG_STATE_HOME:-~/.local/state}/avethyos/quickshell/config.ini`.
They are read on startup and re-read whenever the file changes, so edits apply
without a restart. Image upgrades preserve this file; initial login migrates an
existing `~/.config/quickshell/config.ini` before retiring the old code tree.
Notification history, clipboard entries and media, and application launch
counts live beside these settings in the same user state directory.

```ini
[appearance]
icon-pack = Papirus

[wallpaper]
path = file:///absolute/path/to/wallpaper.mp4
folder = ~/Videos/Wallpapers
fillMode = cover        ; cover | fit | stretch
enabled = true

[notifications]
maxVisibleToasts = 4    ; 1-10
toastDurationMs = 5200  ; minimum 1500
doNotDisturb = false

[display]
nightLightEnabled = false
nightLightTemperature = 4000
```

`appearance.icon-pack` selects the installed icon theme for the shell and GTK
and Qt applications. Names are case sensitive. An empty value follows the
desktop's GTK icon theme. Pack changes apply live, including GTK 2/3/4 settings,
GNOME's icon setting and KDE's icon loader. Qt uses its `gtk3` platform theme;
qt6ct is not required. Wallpaper and light/dark changes preserve the exact pack
you selected. Missing icons use inherited packs and `hicolor`; the shell's
Material control glyphs keep their own font.

`scripts/run.sh` also applies the pack to Qt's native tray/menu icon provider
on startup. Restart the shell after changing the pack to refresh those icons.
Applications that cache icons may also need to be reopened. Existing Flatpak
app settings are synchronized, but each sandbox must have access to the pack.

To synchronize desktop icons while the shell is stopped:

```sh
python3 scripts/material-palette.py --icons-only
```

List installed packs and their exact config names with the shell running:

```sh
qs -p /usr/share/avethyos/quickshell ipc call icons list
qs -p /usr/share/avethyos/quickshell ipc call icons current
```

The list includes `~/.icons`, `~/.local/share/icons`, `/usr/local/share/icons`,
`/usr/share/icons`, custom XDG data paths, and Flatpak/host icon directories.
Each name is followed by all its installation paths in lookup order. Copy the
name into `icon-pack`, for example `Papirus` or `Papirus-Dark` if installed.
To list packs while the shell is stopped, run `python3 scripts/icon-theme.py --list`.

The Control Center's wallpaper library browses `wallpaper.folder` directly,
including its subfolders, with searchable image and video thumbnails. It accepts
`~/` paths, absolute paths and local `file://` URLs. Folder changes apply live.
Choose a thumbnail to apply it; the fit controls select cover, fit or stretch.
Video previews use cached still frames, so browsing never starts extra video
players. Links outside the configured folder are excluded from the library.

The Internet menu lists every NetworkManager interface. Each wired connection
has its own connect/disconnect switch, so multiple Ethernet ports can stay
active together or be switched independently. Connection cards show profiles,
IP addresses, and expandable gateway, IPv6 and hardware-address details. Wi-Fi
provides scanning, password entry and controls for each adapter.

Bluetooth uses live BlueZ state for connected, saved and nearby devices, with
battery levels when available. Device actions support pairing codes, PIN entry,
connect/disconnect, cancellation and forgetting. Shared controls live in
`widgets/Control*.qml`; the expanded menus live in `bar/*Menu.qml`.

Night Light uses Hyprland's output color transform (CTM), keeping screenshots,
recordings and screen sharing in their original colors. Quickshell owns the
small `scripts/night-light.py` Wayland helper; no hyprsunset or separate daemon
is required. It uses Python's standard library and requires
[`hyprland-ctm-control-v1` version 2](https://github.com/hyprwm/hyprland-protocols/blob/main/protocols/hyprland-ctm-control-v1.xml).
Newly connected displays inherit the selected temperature. Disabling Night
Light or exiting Quickshell releases the transform and restores neutral colors;
6500 K is neutral. Another application's CTM ownership is reported in the panel
and retried without interrupting it. Only Quickshell's previous night-light
screen shader is automatically removed during migration.

## Wallpaper Material colors

`scripts/material-palette.py` samples the current wallpaper and generates a
complete light and dark Material-style role set. Images, animated images and
videos use the same FFmpeg decoder; videos are sampled at six representative
timestamps rather than using only their first frame. Colors are clustered in
the perceptual Oklab space and expanded into primary, secondary, tertiary,
neutral, neutral-variant, error, success and warning tonal families.
Sampling preserves the whole frame. Cluster population limits the influence
of tiny saturated details, gamut mapping preserves hue, and each tone is
matched to its actual CIE L* luminance. Achromatic wallpapers stay neutral.

Choosing a wallpaper in the Control Center launches one palette generation
and apply operation. The helper exits when it finishes; there is no polling or
long-running wallpaper watcher. It installs colors into:

- the shell (live through `~/.cache/avethy/palette.ini`)
- GTK 2 (`~/.gtkrc-2.0`)
- GTK 3 and GTK 4, including libadwaita named colors
- KDE/Qt (`kdeglobals` and a full KDE `.colors` scheme)
- the project's native Qt 5/6 widget style and Qt Quick Controls style
- qt5ct (21 `QPalette` roles) and qt6ct (22 roles, including Qt 6.6's Accent),
  with active, inactive and disabled states
- existing Flatpak per-application GTK and Qt configuration homes
- Hyprland's active and inactive border colors

Each regeneration is one ordered desktop-theme transaction: write GTK/Qt and
the complete KDE `KColorScheme` (including every `[Colors:*]` group inline in
`kdeglobals`), toggle and restore GNOME's theme/color-scheme keys so live GTK
and Qt-GTK applications rebuild their palette, broadcast KDE palette/style/icon
change signals, run `nautilus -q`, then explicitly stop and start
`xdg-desktop-portal-gtk` and the portal broker. If Nautilus was running, wait for
it to exit and relaunch it with its previously open folder URIs. The relaunch
uses a separate process session with disconnected standard streams (equivalent
to disowning it); systemd owns the portal processes independently of Quickshell.
Closed Nautilus stays closed. Other GTK applications receive the live theme
notification. The same refresh happens when switching light/dark appearance;
preview generation never restarts applications.

The GTK stylesheet defines both GTK 3 legacy names and the complete
libadwaita-facing color namespace and GTK 4.16+ CSS variables, with explicit
hover, disabled, backdrop, selection, file chooser and sidebar states. Nautilus
paints its translucent window tint once; empty-folder, search/error status
pages and populated list/grid/network views use transparent content layers,
so switching pages keeps compositor blur visible. Verify those backgrounds
in both modes with `python3 tests/check-gtk-nautilus-glass.py` (requires
PyGObject, GTK 4, libadwaita and `gtk4-broadwayd`). The
bar's primary/on-primary pair also colors sidebar selections, checked
controls, suggested actions and Qt highlights. Unfocused selections retain
the same accent. GTK windows, dialogs (including Nautilus properties) and
popovers use translucent background fills with fully opaque text. Flat toolbar
buttons, soft borders and rounded menu surfaces
retain the toolkit's layout and control sizing. Quickshell watches the palette
cache so command-line generation also updates the bar.
`hyprland-portals.conf` routes
Settings/FileChooser/AppChooser to the GTK portal and compositor-specific
capture/shortcut interfaces to the Hyprland portal. A managed Hyprland
systemd target keeps all portal processes inside the graphical session, so a
palette change can restart the GTK settings backend instead of leaving stale
theme data cached in an orphan process.

`native/qt-theme` provides the `Avethy` widget style and the
`Avethy` Qt Quick Controls style. Both use the GTK palette's exact
primary/on-primary colors, flat rounded controls, subtle borders, translucent
windows and floating menus. The shared style name also supports applications
that combine Qt Widgets and Qt Quick, such as KDE Connect; it is distinct from
the shell's `Quickshell` QML module. The native startup plugin migrates the old
style name in environments inherited from existing terminals and sets
`KDE_COLOR_SCHEME_PATH` before KDE initializes its color manager, reconciles
application and widget palette/style overrides, and watches the generated
palette for live wallpaper updates. Saved KDE GUI color schemes, including
Dolphin's, are synchronized without replacing editor or terminal themes.

Palette installation exports the style, startup plugin, QML import paths and
palette path through `${XDG_STATE_HOME:-~/.local/state}/avethyos/hypr/theme.lua`,
`environment.d`, systemd
and D-Bus activation environments. Every `scripts/run.sh` launch reapplies
Avethy before the shell captures its application-launch environment. It reuses
the cached wallpaper colors, generating them when missing or when the configured
wallpaper changes. Direct `qs` launches also restore desktop settings during
initialization. Startup and wallpaper changes share a lock so theme files cannot
be mixed by simultaneous applies. The reload shortcut uses the same launcher.
Host applications load plugins and QML styles directly from the current image.
Existing Flatpak app homes receive a refreshed copy of the plugins, QML style
and palette at each startup/theme apply, with corresponding per-app overrides.
`QT_QPA_PLATFORMTHEME=gtk3` retains GTK native dialogs; `QT_GUI_GTK_JSON`
supplies the GTK platform bridge with complete Qt palette roles.
GTK theme variants are named `Avethy` and `Avethy-dark`; the KDE scheme and both
Qt styles are named `Avethy`. GTK 3 retains the installed adw-gtk3 geometry and
assets under these names, with generated palette overrides. Menus and tooltips
use one palette surface, exact primary/on-primary selection, and opaque muted
disabled text. Verify GTK menus in both modes with
`python3 tests/check-gtk-menus.py`; GTK 2's generated RC mappings are covered by
`python3 -m unittest discover -s tests -p 'test_*.py'`.

The image builds native plugins for both Qt versions. For local development,
build them in a checkout with CMake, a C++ compiler and the matching Qt
development libraries, then apply the palette:

```sh
sh scripts/build-qt-theme.sh 6
sh scripts/build-qt-theme.sh 5  # for Qt 5 applications
python3 scripts/material-palette.py --apply-only
```

Qt loads plugins built for its own major version and a compatible minor
version. Rebuild after Qt upgrades when needed; no theme manager or external
style engine is required. Reopen applications that were running before the
plugin was first installed. Subsequent palette changes reload in apps using
the startup plugin. Applications that draw their own interface or explicitly
load a separate QML style can retain that interface's styling.

Manual commands:

```sh
# Generate from the configured wallpaper and apply it now
python3 scripts/material-palette.py

# Generate from a particular image/video
python3 scripts/material-palette.py --source /path/to/wallpaper.mp4

# Reapply the cached palette after changing appearance
python3 scripts/material-palette.py --apply-only --mode light

# Inspect both themes without changing desktop settings
python3 scripts/material-palette.py --preview-dir /tmp/material-preview
```

## Video wallpaper and GPU vendors

Qt Multimedia's FFmpeg backend **probes the hardware at runtime and picks the
decoder itself**. On Linux it tries CUDA first (NVIDIA NVDEC), then VAAPI (AMD
and Intel), and it only commits to a device type after confirming the driver
actually initialises. If nothing works it falls back to software decoding.

That probe is why this configuration runs unchanged on AMD, Intel and NVIDIA:
there is deliberately **no per-vendor configuration to set**, and forcing a
device type would break machines whose driver behaves differently.

Two things worth knowing:

- Set `QT_MEDIA_BACKEND=ffmpeg` (the launcher does this). A distribution that
  defaults to GStreamer can otherwise select a backend without hardware
  decoding, which is the most common cause of a stuttering wallpaper.
- The wallpaper is one `MediaPlayer` per output. On a multi-monitor setup the
  same file is decoded once per screen, which costs real GPU on 4K video.

To watch Qt's own hardware-acceleration decisions live:

```sh
QT_LOGGING_RULES='qt.multimedia.ffmpeg.hwaccel.debug=true' /usr/share/avethyos/quickshell/scripts/run.sh
```

### Monitor names

`ddcutil detect` reports a DRM connector, which identifies
the port rather than the panel. The control centre shows the monitor's real
product name instead, read from the EDID "monitor name" descriptor:

```sh
python3 scripts/monitor-names.py
card0-DP-1	DISPLAY NAME
```

This works for any vendor and needs no extra package: it reads
`/sys/class/drm/card*-*/edid` directly. The connector is kept as a dim
subtitle, and if a panel reports no name the connector is shown on its own.

### Audio devices

Audio state, readable names, volume, and default-device switching use the
native PipeWire integration. Changes arrive as events; there is no `wpctl`,
`pactl`, Python helper, or periodic subprocess. Monitor sources (`.monitor`)
are filtered out because they duplicate playback streams.

## Dependencies

Required:

```sh
sudo dnf install quickshell
```

Optional. Each tool powers one panel, and a missing one degrades only that
panel rather than the shell — `scripts/run.sh` prints a warning for each:

| Tool | Used by |
| --- | --- |
| `nmcli` | Unified network menu: Wi-Fi scanning/connecting and Ethernet controls |
| `bluetoothctl` | Bluetooth pairing agent and device actions; live state and adapter controls use native BlueZ |
| `ddcutil` | Monitor brightness (needs the user in the `video` group) |
| `gsettings` | Light/dark theme detection |
| `gio` | Launching apps not yet known to Quickshell's native desktop-entry index |
| `hyprctl` | Workspace and session actions |
| `playerctl` | Event-driven “Now Playing” toast |
| `wl-copy`, `wl-paste` (`wl-clipboard`) | Event-driven persistent text and media clipboard history |
| `ffmpeg` | Image previews, video thumbnails, and wallpaper video decoding |
| `python3` | App and icon discovery, wallpaper library/previews, Bluetooth action jobs, monitor names and display color control |

Audio and media use Quickshell's PipeWire and MPRIS integrations directly and
need no command-line helpers.

### Application discovery

The launcher watches installed `.desktop` entries and icons with filesystem
events. New installs, updates, and removals appear while the shell is running,
including icons installed after the application entry. It monitors user and
system XDG data directories, `~/.local/share`, `/usr/local/share`, `/usr/share`,
and Flatpak exports, and starts watching new directories when they are created.
The installer must provide a `.desktop` entry for the app to appear.

`python3` runs the discovery monitor and icon resolver. `gio` (from GLib) launches
new entries that Quickshell's native index has not discovered yet.

## Running

```sh
/usr/share/avethyos/quickshell/scripts/run.sh
```

The managed Hyprland session starts this launcher at login. For development,
run `scripts/run.sh` in a checkout. Commands below use the installed shell path;
substitute the absolute checkout path when working on a development instance.

Include `quickshell:controlcenter` in Hyprland's `no_anim` layer rule alongside
the other shell popups. QML draws the opening and closing transitions; an
additional compositor fade can obscure the opening reveal.

The control center uses the notification popup's window ordering and clipped
reveal. Its animation advances with rendered frames, preserving the opening
and closing motion when window setup or rendering stalls. The opening takes
260 ms. Cached brightness appears immediately; the hardware refresh follows
the reveal and targets the detected I²C bus to avoid scanning every monitor.

## IPC and Hyprland keybindings

Select the installed shell explicitly with `-p /usr/share/avethyos/quickshell`
for every IPC command. Replace that path with your checkout for development.
Every popup on the bar exposes an event-driven toggle through Quickshell IPC:

```sh
qs -p /usr/share/avethyos/quickshell ipc call applauncher toggle
qs -p /usr/share/avethyos/quickshell ipc call clock toggle
qs -p /usr/share/avethyos/quickshell ipc call mediaplayer toggle
qs -p /usr/share/avethyos/quickshell ipc call clipboard toggle
qs -p /usr/share/avethyos/quickshell ipc call controlcenter toggle
```

The bar follows connected outputs. IPC toggles open the popup on the output
under the cursor; clicking a bar button opens it on that bar's output.
The same command both opens and closes its popup. Add bindings to your writable
`~/.config/hypr/shortcuts.lua` using the image-managed command definitions:

```lua
local commands = require("/usr/share/avethyos/hypr/commands.lua")
hl.bind("SUPER + R", hl.dsp.exec_cmd(commands.applauncher))
hl.bind("SUPER + N", hl.dsp.exec_cmd(commands.notifications))
hl.bind("SUPER + V", hl.dsp.exec_cmd(commands.clipboard))
hl.bind("SUPER + W", hl.dsp.exec_cmd(commands.control_center))
```

Use `qs -p /usr/share/avethyos/quickshell ipc show` to inspect the registered targets for the running shell.

The workspace bar shows workspaces 1–10 with at least one open app, plus the
focused workspace, sorted numerically. The focused workspace shows its number
when empty; other empty workspaces are hidden. App icons appear by default; hold
either Super key to show the workspace numbers, then release it to restore the
icons. Each app appears once per workspace, and buttons widen to fit multiple
apps when showing icons.
Both directions use a 140 ms crossfade with no delay.

The managed `/usr/share/avethyos/hypr` configuration forwards the press and release of
`mainMod .. "_L"` and `mainMod .. "_R"` through `hl.dsp.event`, using
`quickshell-workspace-apps,left,1` / `left,0` and `right,1` / `right,0`.
These [Hyprland bindings](https://wiki.hypr.land/configuring/core/binds/flags/)
use `non_consuming`, `ignore_mods`, `transparent`, and `submap_universal` so
the preview also works during Super shortcuts. A `config.reloaded` callback
sends `quickshell-workspace-apps,reset` to clear the held state.

## Tests

```sh
tests/run-all.sh
```

Runs the JavaScript and Python unit tests, a structural check over every QML
file (brace balance, dropped bindings, whitespace) and helper syntax checks.
When `qs` is installed, the icon tests also exercise IPC, live pack switching,
config saving, and newly installed themes in an isolated offscreen shell. With
`gio` available, launcher integration also checks app installs, launch actions,
icon installs and replacements, Flatpak exports, and removal without a restart.
Popup motion checks cover delayed rendering, quick reversals, and closing.
Qt's `qmllint` is not part of this because it is not present in every environment;
if you have it, `qmllint -I components bar/*.qml` is worth running too.
