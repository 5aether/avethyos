import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/icon-theme.py"
SPEC = importlib.util.spec_from_file_location("icon_theme", SCRIPT)
icons = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(icons)


def make_theme(root, name, display_name=None, inherits="", icon="test-app"):
    directory = root / name
    (directory / "scalable/apps").mkdir(parents=True)
    (directory / "index.theme").write_text(
        f"[Icon Theme]\nName={display_name or name}\nInherits={inherits}\n"
        "Directories=scalable/apps\n[scalable/apps]\nSize=48\nType=Scalable\n")
    path = directory / "scalable/apps" / (icon + ".svg")
    path.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"/>')
    return path


class IconThemeTests(unittest.TestCase):
    def test_custom_xdg_paths_keep_local_and_system_roots_without_duplicates(self):
        with patch.object(Path, "home", return_value=Path("/test-home")), patch.dict(
                os.environ, {"XDG_DATA_HOME": "/custom", "XDG_DATA_DIRS": "/one:/two:/one"}):
            roots = icons.icon_roots(include_missing=True)
        self.assertEqual([Path("/test-home/.icons"), Path("/custom/icons"),
                          Path("/test-home/.local/share/icons"), Path("/one/icons"),
                          Path("/two/icons")], roots[:5])
        for path in ["/usr/share/icons", "/usr/local/share/icons",
                     "/custom/flatpak/exports/share/icons", "/var/lib/flatpak/exports/share/icons",
                     "/run/host/usr/share/icons"]:
            self.assertIn(Path(path), roots)
        self.assertEqual(len(set(roots)), len(roots))

    def test_empty_xdg_variables_use_defaults(self):
        with patch.object(Path, "home", return_value=Path("/test-home")), patch.dict(
                os.environ, {"XDG_DATA_HOME": "", "XDG_DATA_DIRS": ""}):
            roots = icons.icon_roots(include_missing=True)
        self.assertEqual([Path("/test-home/.icons"), Path("/test-home/.local/share/icons"),
                          Path("/usr/local/share/icons"), Path("/usr/share/icons")], roots[:4])

    def test_missing_roots_watch_the_nearest_existing_parent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "new/data/icons"
            with patch.object(icons, "icon_roots", return_value=[root]):
                self.assertEqual([{"path": str(root), "parent": tmp, "exists": False}], icons.root_watches())
                root.parent.mkdir(parents=True)
                self.assertEqual([{"path": str(root), "parent": str(root.parent), "exists": False}], icons.root_watches())
                root.mkdir()
                self.assertTrue(icons.root_watches()[0]["exists"])

    def test_exact_names_and_all_installations_in_lookup_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            local, system = Path(tmp) / "local", Path(tmp) / "system"
            make_theme(system, "Papirus-Dark", display_name="Friendly display name")
            (local / "Papirus-Dark/48x48/apps").mkdir(parents=True)
            make_theme(local, "Adwaita")
            (system / "cursors-only").mkdir()
            (system / "cursors-only/index.theme").write_text("[Cursor Theme]\nName=Cursor theme\n")
            (system / "loose-icons").mkdir()
            themes = icons.installed_themes([local, system, Path(tmp) / "missing"])
            self.assertEqual(["Adwaita", "Papirus-Dark"], [theme["name"] for theme in themes])
            self.assertEqual([str(local / "Papirus-Dark"), str(system / "Papirus-Dark")], themes[1]["paths"])
            self.assertNotIn("Friendly display name", icons.format_themes(themes))

    def test_symlinked_variant_and_inheritance_keep_selected_icons_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            selected = make_theme(root, "Papirus", inherits="Parent", icon="MixedCase")
            parent = make_theme(root, "Parent", inherits="Papirus", icon="inherited-app")
            fallback = make_theme(root, "hicolor", icon="fallback-app")
            variant = root / "Papirus-Dark"
            variant.mkdir()
            (variant / "index.theme").write_text("[Icon Theme]\nName=Dark\nInherits=Papirus\n")
            (variant / "scalable").symlink_to(root / "Papirus/scalable", target_is_directory=True)
            with patch.object(icons, "icon_roots", return_value=[root]):
                result = icons.build("Papirus-Dark")
            self.assertEqual(str(selected), result["mixedcase"])
            self.assertEqual(str(parent), result["inherited-app"])
            self.assertEqual(str(fallback), result["fallback-app"])
            self.assertIn("Papirus-Dark", [theme["name"] for theme in icons.installed_themes([root])])

    def test_configured_pack_uses_the_appearance_section_and_preserves_case(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.ini"
            self.assertEqual("", icons.configured_theme(config))
            config.write_text("[wallpaper]\nicon-pack=Ignored\n[appearance]\nicon-pack = Papirus-Dark\n")
            self.assertEqual("Papirus-Dark", icons.configured_theme(config))
            result = subprocess.run([sys.executable, str(SCRIPT), "--config", str(config)],
                                    capture_output=True, text=True, check=True)
            self.assertEqual("Papirus-Dark\n", result.stdout)


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class IconThemeQmlTests(unittest.TestCase):
    def test_live_selection_listing_and_config_save(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            shell = directory / "shell"
            home = directory / "home"
            data = home / "custom-share"
            system = directory / "system-share"
            (shell / "components").mkdir(parents=True)
            (shell / "scripts").mkdir()
            names = ["Config", "IconThemeService", "IconThemeCatalog", "DesktopFileMonitor"]
            for name in names:
                shutil.copy(ROOT / "components" / (name + ".qml"), shell / "components")
            (shell / "components/qmldir").write_text("".join(
                f"singleton {name} 1.0 {name}.qml\n" for name in names))
            shutil.copy(SCRIPT, shell / "scripts/icon-theme.py")
            for helper in ["desktop-search.py", "desktop-watch.py", "material-palette.py"]:
                shutil.copy(ROOT / "scripts" / helper, shell / "scripts" / helper)
            initial = make_theme(data / "icons", "Test-Local-Pack", display_name="Pretty icons")
            replacement = make_theme(system / "icons", "Test-System-Pack")
            make_theme(data / "icons", "Test-Desktop-Pack")
            config = home / ".local/state/avethyos/quickshell/config.ini"
            config.parent.mkdir(parents=True)
            config.write_text("[appearance]\nicon-pack = Test-Local-Pack\n")
            gtk = home / ".config/gtk-3.0/settings.ini"
            gtk.parent.mkdir(parents=True)
            gtk.write_text("[Settings]\ngtk-icon-theme-name=Test-Desktop-Pack\n")
            (home / ".local/share").mkdir(parents=True)
            (shell / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "components"
ShellRoot {
    readonly property var catalog: IconThemeCatalog
    IpcHandler {
        target: "icons"
        function list(): string { return IconThemeCatalog.list(); }
        function current(): string { return IconThemeService.themeName; }
        function desktop(): string {
            return IconThemeService.desktopTheme.running || IconThemeService.desktopSync.running
                ? "" : IconThemeService.gtk3Theme;
        }
        function source(): string { return IconThemeService.resolve("test-app"); }
        function saveSettings(): void { Config.setDoNotDisturb(true); }
    }
}
''')
            runtime = directory / "runtime"
            runtime.mkdir(mode=0o700)
            # Keep desktop synchronization inside this fixture, including
            # GSettings and the helper's explicit KDE session-bus notification.
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            settings_log = directory / "gsettings-icon"
            commands = {
                "gsettings": """#!/bin/sh
case "$1" in
    get) printf "'Test-Desktop-Pack'\\n" ;;
    set) printf '%s\\n' "$4" > "$ICON_TEST_GSETTINGS" ;;
esac
""",
                "flatpak": "#!/bin/sh\nexit 0\n",
                "dbus-send": "#!/bin/sh\nexit 0\n",
            }
            for name, text in commands.items():
                command = bin_dir / name
                command.write_text(text)
                command.chmod(0o755)
            env = os.environ.copy()
            env.update({"HOME": str(home), "XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(system),
                        "XDG_RUNTIME_DIR": str(runtime), "XDG_CACHE_HOME": str(directory / "cache"),
                        "XDG_CONFIG_HOME": str(home / ".config"), "XDG_STATE_HOME": str(home / ".local/state"),
                        "QT_QPA_PLATFORM": "offscreen",
                        "QT_QPA_PLATFORMTHEME": "", "XDG_CURRENT_DESKTOP": "", "DESKTOP_SESSION": "",
                        "PATH": str(bin_dir) + ":" + env.get("PATH", "/usr/bin:/bin"),
                        "ICON_TEST_GSETTINGS": str(settings_log)})
            for key in ["QT_QPA_GENERIC_PLUGINS", "QT_PLUGIN_PATH", "QS_CONFIG_PATH", "QS_ICON_THEME",
                        "DISPLAY", "WAYLAND_DISPLAY"]:
                env.pop(key, None)
            with (directory / "log").open("w+") as log:
                process = subprocess.Popen(["qs", "--no-color", "-p", str(shell)], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
                try:
                    def call(method):
                        result = subprocess.run(["qs", "ipc", "-p", str(shell), "call", "icons", method],
                                                env=env, capture_output=True, text=True, timeout=5)
                        return result.stdout.strip() if result.returncode == 0 else ""

                    def wait_for(method, expected):
                        deadline = time.monotonic() + 15
                        while time.monotonic() < deadline:
                            value = call(method)
                            if expected in value:
                                return value
                            if process.poll() is not None:
                                break
                            time.sleep(.05)
                        log.seek(0)
                        self.fail(f"{method} never returned {expected!r}: {log.read()}")

                    wait_for("source", str(initial))
                    wait_for("desktop", "Test-Local-Pack")
                    self.assertEqual("Test-Local-Pack", settings_log.read_text().strip())
                    listing = wait_for("list", "Test-System-Pack")
                    self.assertIn("Test-Local-Pack", listing)
                    self.assertIn(str(initial.parent.parent.parent), listing)
                    self.assertIn(str(replacement.parent.parent.parent), listing)
                    self.assertNotIn("Pretty icons", listing)
                    call("saveSettings")
                    deadline = time.monotonic() + 5
                    while "doNotDisturb = true" not in config.read_text() and time.monotonic() < deadline:
                        time.sleep(.05)
                    self.assertIn("icon-pack = Test-Local-Pack", config.read_text())
                    self.assertIn("doNotDisturb = true", config.read_text())
                    config.write_text("[appearance]\nicon-pack = Test-System-Pack\n")
                    wait_for("source", str(replacement))
                    wait_for("desktop", "Test-System-Pack")
                    self.assertEqual("Test-System-Pack", settings_log.read_text().strip())
                    added = make_theme(home / ".local/share/icons", "Test-New-Pack")
                    listing = wait_for("list", "Test-New-Pack")
                    self.assertIn(str(added.parent.parent.parent), listing)
                    # Clearing the override follows the current desktop pack.
                    gtk.write_text("[Settings]\ngtk-icon-theme-name=Test-Desktop-Pack\n")
                    wait_for("desktop", "Test-Desktop-Pack")
                    config.write_text("[appearance]\nicon-pack =\n")
                    wait_for("current", "Test-Desktop-Pack")
                finally:
                    process.terminate()
                    process.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
