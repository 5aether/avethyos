#!/bin/bash
set -euo pipefail

# Run in an ephemeral container from the completed image, before publishing it.
# Only temporary HOME/XDG directories are used; no desktop session is started.
/usr/bin/python3 - <<'PY'
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time


DESKTOP = Path("/usr/share/avethyos")
SHELL = DESKTOP / "quickshell"
HYPR = DESKTOP / "hypr"
INITIALIZER = Path("/usr/libexec/avethyos-user-config")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(command, environment=None):
    result = subprocess.run(command, env=environment, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    require(result.returncode == 0, f"Command failed ({result.returncode}): {command}\n{result.stdout}")
    return result.stdout


def inspect_tree(root):
    require(root.is_dir(), f"Missing installed directory: {root}")
    for path in (root, *root.rglob("*")):
        info = path.lstat()
        require(info.st_uid == 0 and info.st_gid == 0, f"Image asset is not root-owned: {path}")
        if stat.S_ISLNK(info.st_mode):
            require(path.exists(), f"Broken installed symlink: {path}")
            continue
        require(not info.st_mode & 0o022, f"Image asset allows group/other writes: {path}")
        require(info.st_mode & 0o004, f"Image asset is not readable by users: {path}")
        if stat.S_ISDIR(info.st_mode):
            require(info.st_mode & 0o001, f"Image directory is not searchable by users: {path}")


def check_installation():
    for root in (SHELL, HYPR):
        inspect_tree(root)
    for path in (SHELL / "shell.qml", SHELL / "config.ini", SHELL / "components/Config.qml",
                 HYPR / "hyprland.lua", HYPR / "commands.lua", INITIALIZER,
                 Path("/usr/libexec/avethyos-start-hyprland"),
                 Path("/usr/libexec/avethyos-hyprland-session")):
        require(path.is_file(), f"Missing installed desktop file: {path}")
        require(path.stat().st_uid == 0 and not path.stat().st_mode & 0o022,
                f"Installed desktop file is user-writable: {path}")
    for name in ("shortcuts.lua", "monitors.lua", "input.lua", "appearance.lua",
                 "window-rules.lua", "custom.lua", "hypridle.conf", "hyprlock.conf"):
        require((HYPR / "user" / name).is_file(), f"Missing user template: {name}")
    for name in ("quickshell", "hypr"):
        require(not (Path("/etc/skel/.config") / name).exists(), f"Stale desktop implementation in skel: {name}")
    require(not (SHELL / "tests").exists(), "Quickshell test sources leaked into installed assets")

    sources = [*SHELL.glob("assets/shaders/*.vert"), *SHELL.glob("assets/shaders/*.frag")]
    require(sources, "No installed shader sources")
    for source in sources:
        compiled = source.with_name(source.name + ".qsb")
        target = SHELL / "shaders" / compiled.name
        require(compiled.is_symlink() and target.is_file() and compiled.samefile(target),
                f"Shader does not use its image-built binary: {compiled}")
        require(target.stat().st_size > 0 and os.access(target, os.R_OK), f"Unreadable compiled shader: {target}")

    libdir = Path(run(["rpm", "--eval", "%{_libdir}"]).strip())
    for major in (5, 6):
        linked = SHELL / f"native/qt-theme/build-qt{major}"
        provider = libdir / f"avethyos/qt-theme/qt{major}"
        require(linked.is_symlink() and linked.resolve() == provider.resolve(), f"Wrong native theme link: {linked}")
        inspect_tree(provider)
        for kind, name in (("styles", "style"), ("generic", "theme")):
            library = linked / f"plugins/{kind}/libavethy-{name}-qt{major}.so"
            require(library.is_file() and os.access(library, os.R_OK), f"Missing native theme library: {library}")
            # dlopen verifies runtime dependencies without creating any Qt GUI.
            # Keep Qt 5 and Qt 6 in separate processes to avoid symbol conflicts.
            run(["/usr/bin/python3", "-c", "import ctypes, sys; ctypes.CDLL(sys.argv[1])", str(library)])
    print("Installed desktop paths, permissions, shaders and native libraries passed.")


def check_user_state(shell_root, hypr_root, initializer):
    with tempfile.TemporaryDirectory(prefix="avethyos-desktop-check-") as temporary:
        base = Path(temporary)
        home, config, state, runtime = (base / name for name in ("home", "custom config", "custom state", "runtime"))
        for directory in (home, config, state, runtime):
            directory.mkdir(mode=0o700)
        environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config),
                           XDG_STATE_HOME=str(state), XDG_DATA_HOME=str(base / "data"),
                           XDG_CACHE_HOME=str(base / "cache"), XDG_RUNTIME_DIR=str(runtime))
        for name in tuple(environment):
            if name.startswith(("QT_", "QML_", "QS_", "AVETHY_")) or name in (
                    "DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
                environment.pop(name, None)

        # Exercise migration with a stale per-user implementation in temporary HOME.
        legacy = config / "quickshell"
        legacy.mkdir()
        (legacy / "shell.qml").write_text("// obsolete per-user shell\n")
        (legacy / "config.ini").write_text("[appearance]\nicon-pack = CI-persistent\n")
        preference = state / "avethyos/quickshell/config.ini"
        initialize = ["/usr/bin/python3", str(initializer)]
        run(initialize, environment)
        require(not legacy.exists() and not (home / ".config/quickshell").exists(), "Old home Quickshell source remains active")
        archive = state / "avethyos/legacy-desktop/quickshell/shell.qml"
        require(archive.is_file(), "Old Quickshell source was not archived")
        require(preference.read_text() == "[appearance]\nicon-pack = CI-persistent\n", "Legacy shell preferences were not preserved")
        require(preference.stat().st_mode & stat.S_IWUSR, "Quickshell user state is not writable")
        shortcuts = config / "hypr/shortcuts.lua"
        custom = shortcuts.read_bytes() + b"\n-- CI user shortcut preference, preserved on upgrade.\n"
        shortcuts.write_bytes(custom)
        run(initialize, environment)
        require(shortcuts.read_bytes() == custom, "Initializer replaced user shortcuts")
        require(not (config / "hypr/hyprland.lua").exists() and not (config / "hypr/theme.lua").exists(),
                "System entry point or generated palette leaked into user config")

        verify = ["Hyprland", "--verify-config", "--config", str(hypr_root / "hyprland.lua")]
        if os.geteuid() == 0:
            verify.append("--i-am-really-stupid")
        output = run(verify, environment)
        require("config ok" in output, f"Hyprland did not confirm the installed configuration:\n{output}")

        # Load only Config.qml; this creates no windows, desktop services or portals.
        fixture = base / "config-check"
        fixture.mkdir()
        components = fixture / "components"
        components.mkdir()
        (components / "Config.qml").symlink_to(shell_root / "components/Config.qml")
        (components / "qmldir").write_text("singleton Config 1.0 Config.qml\n")
        (fixture / "shell.qml").write_text('''import QtQuick
import Quickshell
import "components" as Desktop
ShellRoot {
    readonly property var preferences: Desktop.Config
    property Timer check: Timer {
        interval: 25
        running: true
        repeat: true
        onTriggered: {
            if (Desktop.Config.iconPack === "CI-persistent") {
                Desktop.Config.iconPack = "CI-written";
                Desktop.Config.save();
                stop();
            }
        }
    }
}
''')
        environment.update(QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software")
        installed_default = hashlib.sha256((shell_root / "config.ini").read_bytes()).digest()
        with (base / "quickshell.log").open("w+") as log:
            process = subprocess.Popen(["qs", "--no-color", "-p", str(fixture)], env=environment,
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if "icon-pack = CI-written" in preference.read_text():
                        break
                    if process.poll() is not None:
                        break
                    time.sleep(0.05)
                log.seek(0)
                output = log.read()
                require("icon-pack = CI-written" in preference.read_text(),
                        "Installed Config.qml did not read and write user state:\n" + output)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        updated = preference.read_bytes()
        run(initialize, environment)
        require(preference.read_bytes() == updated and shortcuts.read_bytes() == custom,
                "Repeated initialization changed saved user preferences")
        require(hashlib.sha256((shell_root / "config.ini").read_bytes()).digest() == installed_default,
                "Quickshell wrote into image-managed defaults")
        require(not legacy.exists(), "Config.qml recreated a per-user Quickshell implementation")
        print("Installed Hyprland and Config.qml passed; migration and writable preferences survive repeated initialization.")


check_installation()
check_user_state(SHELL, HYPR, INITIALIZER)
PY
