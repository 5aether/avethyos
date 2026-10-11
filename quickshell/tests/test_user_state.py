"""Exercise desktop history persistence outside the image-owned QML tree."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class UserStateTests(unittest.TestCase):
    def test_all_history_services_write_to_custom_xdg_state_home(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            shell, home = directory / "shell", directory / "home"
            state = directory / "custom state/avethyos/quickshell"
            state.mkdir(parents=True)
            (state / "config.ini").write_text("[notifications]\ndoNotDisturb=true\n")
            (state / "notifications.json").write_text("[]\n")
            (state / "clipboard.json").write_text("[]\n")
            (state / "app-usage.json").write_text("{}\n")
            (shell / "components").mkdir(parents=True)
            components = ["Config", "NotificationStore", "ClipboardService", "AppUsage"]
            for name in components:
                shutil.copy(ROOT / "components" / f"{name}.qml", shell / "components")
            (shell / "components/qmldir").write_text("".join(
                f"singleton {name} 1.0 {name}.qml\n" for name in components))
            (shell / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "components"
ShellRoot {
    readonly property var clipboard: ClipboardService
    readonly property var usage: AppUsage
    readonly property var notifications: NotificationStore
    IpcHandler {
        target: "state"
        function ready(): bool {
            return ClipboardService.loaded && ClipboardService.directoryReady
                && NotificationStore.loaded && AppUsage.revision > 0;
        }
        function write(): void {
            NotificationStore.add("test", "Saved", "History", "App", "", "", 1);
            ClipboardService.receive(JSON.stringify({kind: "text", text: "Saved clipboard"}));
            AppUsage.record("test.desktop");
        }
    }
}
''')
            runtime = directory / "runtime"
            runtime.mkdir(mode=0o700)
            environment = os.environ.copy()
            environment.update({"HOME": str(home), "XDG_STATE_HOME": str(state.parents[1]),
                                "XDG_RUNTIME_DIR": str(runtime), "QT_QPA_PLATFORM": "offscreen",
                                "QT_QPA_PLATFORMTHEME": ""})
            for key in ("QT_PLUGIN_PATH", "QT_QPA_GENERIC_PLUGINS", "QS_CONFIG_PATH",
                        "DISPLAY", "WAYLAND_DISPLAY"):
                environment.pop(key, None)
            with (directory / "log").open("w+") as log:
                process = subprocess.Popen(["qs", "--no-color", "-p", str(shell)], env=environment,
                                           stdout=log, stderr=subprocess.STDOUT)
                try:
                    def call(method):
                        return subprocess.run(["qs", "ipc", "-p", str(shell), "call", "state", method],
                                              env=environment, capture_output=True, text=True, timeout=5)

                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline:
                        result = call("ready")
                        if result.returncode == 0 and result.stdout.strip() == "true":
                            break
                        time.sleep(.05)
                    else:
                        log.seek(0)
                        self.fail("History services did not load: " + log.read())
                    result = call("write")
                    self.assertEqual(0, result.returncode, result.stderr)
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        notification = json.loads((state / "notifications.json").read_text())
                        clipboard = json.loads((state / "clipboard.json").read_text())
                        usage = json.loads((state / "app-usage.json").read_text())
                        if notification and clipboard and usage:
                            break
                        time.sleep(.05)
                    self.assertEqual("Saved", notification[0]["summary"])
                    self.assertEqual("Saved clipboard", clipboard[0]["text"])
                    self.assertEqual({"test.desktop": 1}, usage)
                    self.assertFalse((home / ".local/share/quickshell").exists())
                    self.assertFalse((home / ".config/quickshell").exists())
                finally:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
