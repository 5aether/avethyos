import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="red"/></svg>'


@unittest.skipUnless(shutil.which("qs") and shutil.which("gio"), "Quickshell and gio are required")
class LauncherDiscoveryTests(unittest.TestCase):
    def test_installs_icons_updates_and_removal_without_restarting(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            shell, home, system = base / "shell", base / "home", base / "system"
            (shell / "components").mkdir(parents=True)
            (shell / "scripts").mkdir()
            (shell / "modules").mkdir()
            names = ["Config", "AppSearchIndex", "IconThemeService", "DesktopFileMonitor"]
            for name in names:
                shutil.copy(ROOT / "components" / (name + ".qml"), shell / "components")
            (shell / "components/qmldir").write_text("".join(
                f"singleton {name} 1.0 {name}.qml\n" for name in names))
            for name in ["desktop-search.py", "desktop-watch.py", "icon-theme.py"]:
                shutil.copy(ROOT / "scripts" / name, shell / "scripts")
            # Desktop icon propagation has its own integration fixture. Keep
            # this launcher test independent of the real desktop settings/bus.
            (shell / "scripts/material-palette.py").write_text("# Isolated desktop theme sync stub.\n")
            shutil.copy(ROOT / "modules/appSearch.js", shell / "modules")
            config = home / ".local/state/avethyos/quickshell/config.ini"
            config.parent.mkdir(parents=True)
            config.write_text("[appearance]\nicon-pack = TestPack\n")
            theme = home / ".local/share/icons/TestPack"
            (theme / "scalable/apps").mkdir(parents=True)
            (theme / "index.theme").write_text("[Icon Theme]\nName=TestPack\nDirectories=scalable/apps\n")
            (theme / "scalable/apps/application-x-executable.svg").write_text(SVG)
            (system / "applications").mkdir(parents=True)
            (system / "applications/seed.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=Seed\nExec=true\n")
            (shell / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "components"
import "modules/appSearch.js" as AppSearch
ShellRoot {
    id: root
    property string inspectedId: "test-new-install"
    property string query: ""
    readonly property var inspected: AppSearchIndex.applications.find(app => app.id === inspectedId)
    readonly property string iconSource: inspected ? IconThemeService.resolve(inspected.icon) : ""
    property Image image: Image { source: root.iconSource; asynchronous: true }
    ScriptModel {
        id: launcher
        values: AppSearch.rankApps(AppSearchIndex.applications, root.query, {}, AppSearchIndex.entries)
    }
    IpcHandler {
        target: "discovery"
        function snapshot(): string {
            return JSON.stringify({ pid: Quickshell.processId,
                apps: launcher.values.map(app => ({ id: app.id, name: app.name })),
                icon: root.iconSource, ready: root.image.status === Image.Ready,
                native: !!DesktopEntries.byId(root.inspectedId) });
        }
        function inspect(id: string): void { root.inspectedId = id; }
        function search(query: string): void { root.query = query; }
        function launch(id: string): void { AppSearchIndex.applications.find(app => app.id === id).execute(); }
        function action(id: string, name: string): void {
            AppSearchIndex.applications.find(app => app.id === id).actions.find(action => action.id === name).execute();
        }
    }
}
''')
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.update({"HOME": str(home), "XDG_DATA_HOME": str(home / ".local/share"),
                        "XDG_DATA_DIRS": str(system), "XDG_RUNTIME_DIR": str(runtime),
                        "XDG_CACHE_HOME": str(base / "cache"), "XDG_CONFIG_HOME": str(home / ".config"),
                        "XDG_STATE_HOME": str(home / ".local/state"),
                        "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "", "XDG_CURRENT_DESKTOP": "",
                        "DESKTOP_SESSION": "", "QS_ICON_THEME": "TestPack"})
            for key in ["QT_QPA_GENERIC_PLUGINS", "QT_PLUGIN_PATH", "QS_CONFIG_PATH", "DISPLAY", "WAYLAND_DISPLAY"]:
                env.pop(key, None)
            with (base / "log").open("w+") as log:
                process = subprocess.Popen(["qs", "--no-color", "-p", str(shell)], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
                try:
                    def call(method, *args):
                        result = subprocess.run(["qs", "ipc", "-p", str(shell), "call", "discovery", method, *args],
                                                env=env, capture_output=True, text=True, timeout=5)
                        return result.stdout.strip() if result.returncode == 0 else ""

                    def state():
                        try:
                            return json.loads(call("snapshot"))
                        except ValueError:
                            return {}

                    def wait_for(predicate, message):
                        deadline = time.monotonic() + 15
                        while time.monotonic() < deadline:
                            current = state()
                            if predicate(current):
                                return current
                            if process.poll() is not None:
                                break
                            time.sleep(.05)
                        log.seek(0)
                        self.fail(message + ": " + json.dumps(state()) + "\n" + log.read())

                    def contains(current, app_id):
                        return any(app["id"] == app_id for app in current.get("apps", []))

                    initial = wait_for(lambda value: contains(value, "seed"), "initial apps did not load")
                    user = home / ".local/share/applications"
                    self.assertFalse(user.exists())
                    user.mkdir()
                    marker = user / "launched-marker"
                    action_marker = user / "action-marker"
                    app = user / "test-new-install.desktop"
                    app.write_text("[Desktop Entry]\nType=Application\nName=New Install\nIcon=late-icon\n"
                                   f'Exec="{sys.executable}" -c "from pathlib import Path; Path(\'{marker}\').write_text(\'ok\')"\n'
                                   "X-Discovery-Test=fresh-install-alias\nActions=New;\n[Desktop Action New]\nName=New\n"
                                   f'Exec="{sys.executable}" -c "from pathlib import Path; Path(\'{action_marker}\').write_text(\'ok\')"\n')
                    discovered = wait_for(lambda value: contains(value, "test-new-install"), "new application root was missed")
                    self.assertEqual(initial["pid"], discovered["pid"])
                    self.assertFalse(discovered["native"], "test must exercise a directory missed by the native index")
                    call("search", "fresh-install-alias")
                    wait_for(lambda value: contains(value, "test-new-install") and len(value["apps"]) == 1,
                             "new search metadata was missed")
                    call("search", "")
                    call("launch", "test-new-install")
                    wait_for(lambda value: marker.exists(), "discovered application did not launch")
                    call("action", "test-new-install", "New")
                    wait_for(lambda value: action_marker.exists(), "discovered application action did not launch")
                    icon = theme / "scalable/apps/late-icon.svg"
                    icon.write_text(SVG)
                    wait_for(lambda value: str(icon) in value.get("icon", "") and value.get("ready"),
                             "icon installed after the desktop entry was missed")
                    previous = state()["icon"]
                    icon.write_text(SVG.replace("red", "blue"))
                    wait_for(lambda value: value.get("icon", "") != previous and value.get("ready"),
                             "updated icon stayed cached")
                    icon.unlink()
                    wait_for(lambda value: "application-x-executable.svg" in value.get("icon", ""),
                             "removed icon stayed cached")
                    absolute = home / "bundle/icon.svg"
                    app.write_text(app.read_text().replace("Icon=late-icon", "Icon=" + str(absolute)))
                    wait_for(lambda value: str(absolute) in value.get("icon", ""), "absolute icon metadata was missed")
                    absolute.parent.mkdir()
                    absolute.write_text(SVG)
                    wait_for(lambda value: value.get("ready"), "late absolute icon did not load")
                    pixmap = home / ".local/share/pixmaps/late-pixmap.svg"
                    app.write_text(app.read_text().replace("Icon=" + str(absolute), "Icon=late-pixmap"))
                    pixmap.parent.mkdir()
                    pixmap.write_text(SVG)
                    wait_for(lambda value: str(pixmap) in value.get("icon", "") and value.get("ready"),
                             "new pixmap icon was missed")
                    app.write_text(app.read_text().replace("Name=New Install", "Name=Updated Install"))
                    wait_for(lambda value: any(entry["id"] == "test-new-install" and entry["name"] == "Updated Install"
                                              for entry in value.get("apps", [])), "updated application metadata was missed")
                    exports = home / ".local/share/flatpak/exports/share/applications"
                    exports.mkdir(parents=True)
                    first, second = home / "flatpak-first", home / "flatpak-second"
                    first.mkdir()
                    second.mkdir()
                    active = home / "flatpak-active"
                    active.symlink_to(first, target_is_directory=True)
                    target = first / "app.desktop"
                    target.write_text("[Desktop Entry]\nType=Application\nName=Exported app\nExec=true\n")
                    (second / "app.desktop").write_text(
                        "[Desktop Entry]\nType=Application\nName=Updated export\nExec=true\n")
                    (exports / "test-exported.desktop").symlink_to(active / "app.desktop")
                    wait_for(lambda value: contains(value, "test-exported"), "new Flatpak exports were missed")
                    replacement = home / "flatpak-next"
                    replacement.symlink_to(second, target_is_directory=True)
                    replacement.replace(active)
                    wait_for(lambda value: any(entry["id"] == "test-exported" and entry["name"] == "Updated export"
                                              for entry in value.get("apps", [])), "updated Flatpak deployment was missed")
                    (exports / "test-exported.desktop").unlink()
                    app.unlink()
                    final = wait_for(lambda value: not contains(value, "test-new-install")
                                     and not contains(value, "test-exported"), "removed applications remained visible")
                    self.assertEqual(initial["pid"], final["pid"])
                finally:
                    process.terminate()
                    process.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
