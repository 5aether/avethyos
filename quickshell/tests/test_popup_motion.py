import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class PopupMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        base = Path(cls.temp.name)
        cls.shell = base / "shell"
        (cls.shell / "widgets").mkdir(parents=True)
        shutil.copy(ROOT / "widgets/PopupMotion.qml", cls.shell / "widgets")
        (cls.shell / "widgets/qmldir").write_text("PopupMotion 1.0 PopupMotion.qml\n")
        (cls.shell / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "widgets"
ShellRoot {
    id: root
    property bool sourceAttached: false
    property int closedEvents: 0
    property int settledEvents: 0
    QtObject {
        id: frameClock
        signal frameSwapped()
        property int updates: 0
        function update(): void { ++updates; }
    }
    PopupMotion {
        id: motion
        frameDriven: true
        frameSource: root.sourceAttached ? frameClock : null
        onClosed: ++root.closedEvents
        onSettled: ++root.settledEvents
    }
    PopupMotion { id: legacy }
    IpcHandler {
        target: "motion"
        function reset(): void {
            motion.animationsEnabled = false;
            motion.opened = false;
            root.sourceAttached = false;
            motion.animationsEnabled = true;
            legacy.animationsEnabled = false;
            legacy.opened = false;
            legacy.animationsEnabled = true;
            root.closedEvents = 0;
            root.settledEvents = 0;
            frameClock.updates = 0;
        }
        function request(opened: bool): void { motion.opened = opened; }
        function attach(attached: bool): void { root.sourceAttached = attached; }
        function animate(enabled: bool): void { motion.animationsEnabled = enabled; }
        function frame(timestamp: int): void { motion.advanceFrame(timestamp); }
        function frames(timestamp: int, count: int): void {
            for (let i = 0; i < count; ++i)
                motion.advanceFrame(timestamp + i * 16);
        }
        function legacyRequest(opened: bool): void { legacy.opened = opened; }
        function snapshot(): string {
            return JSON.stringify({ progress: motion.progress, active: motion.active,
                opacity: motion.contentOpacity, join: motion.joinProgress,
                expansion: motion.expansionProgress, closed: root.closedEvents,
                settled: root.settledEvents, updates: frameClock.updates,
                legacyProgress: legacy.progress, legacyActive: legacy.active });
        }
    }
}
''')
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        cls.env = os.environ.copy()
        cls.env.update({"HOME": str(base / "home"), "XDG_RUNTIME_DIR": str(runtime),
                        "XDG_CACHE_HOME": str(base / "cache"),
                        "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": ""})
        for key in ["QT_QPA_GENERIC_PLUGINS", "QT_PLUGIN_PATH", "QS_CONFIG_PATH", "DISPLAY", "WAYLAND_DISPLAY"]:
            cls.env.pop(key, None)
        cls.log = (base / "log").open("w+")
        cls.process = subprocess.Popen(["qs", "--no-color", "-p", str(cls.shell)], env=cls.env,
                                       stdout=cls.log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and cls.process.poll() is None:
            result = cls.call("snapshot")
            if result.returncode == 0 and result.stdout.strip().startswith("{"):
                return
            time.sleep(.05)
        cls.log.seek(0)
        error = cls.log.read()
        cls.tearDownClass()
        raise RuntimeError("Popup motion test shell did not start:\n" + error)

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait(timeout=5)
        cls.log.close()
        cls.temp.cleanup()

    @classmethod
    def call(cls, method, *args):
        return subprocess.run(["qs", "ipc", "-p", str(cls.shell), "call", "motion", method,
                               *(str(arg).lower() if isinstance(arg, bool) else str(arg) for arg in args)],
                              env=cls.env, capture_output=True, text=True, timeout=5)

    def command(self, method, *args):
        result = self.call(method, *args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("ERROR", result.stdout + result.stderr)

    def state(self):
        result = self.call("snapshot")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def setUp(self):
        self.command("reset")

    def test_delayed_surface_and_stalled_frames_preserve_the_reveal(self):
        self.command("request", True)
        time.sleep(.45)  # Longer than the entire normal opening animation.
        self.assertEqual(self.state()["progress"], 0)
        self.assertTrue(self.state()["active"])
        self.command("attach", True)
        self.command("frame", 0)
        self.assertEqual(self.state()["progress"], 0)
        self.command("frame", 1000)  # A blocked render must not jump to fully open.
        state = self.state()
        self.assertGreater(state["progress"], 0)
        self.assertLess(state["progress"], .1)
        self.assertEqual(state["opacity"], 0)
        self.command("frames", 1016, 12)
        state = self.state()
        self.assertGreater(state["expansion"], 0)
        self.assertLess(state["expansion"], 1)
        self.assertGreater(state["opacity"], 0)
        self.command("frames", 1208, 30)
        state = self.state()
        self.assertEqual((state["progress"], state["opacity"], state["settled"]), (1, 1, 1))
        self.assertTrue(state["active"])
        updates = state["updates"]
        self.command("frame", 5000)
        self.assertEqual(self.state()["updates"], updates)

    def test_quick_reopening_preserves_progress_and_closing_finishes(self):
        self.command("attach", True)
        initially_closed = self.state()["closed"]
        self.command("request", True)
        self.command("frames", 1000, 12)
        opening = self.state()["progress"]
        self.command("request", False)
        self.command("frame", 2000)
        self.assertEqual(self.state()["progress"], opening)
        self.command("frame", 3000)
        closing = self.state()["progress"]
        self.assertGreater(closing, 0)
        self.assertLess(closing, opening)
        self.command("request", True)
        self.command("frame", 4000)
        self.assertEqual(self.state()["progress"], closing)
        self.command("frames", 4016, 30)
        self.assertEqual(self.state()["progress"], 1)
        self.command("request", False)
        self.command("frame", 5000)
        self.command("frame", 6000)
        self.assertGreater(self.state()["progress"], .8)
        self.assertTrue(self.state()["active"])
        self.command("frames", 6016, 30)
        state = self.state()
        self.assertEqual((state["progress"], state["closed"]), (0, initially_closed + 1))
        self.assertFalse(state["active"])
        self.command("frame", 7000)
        self.assertEqual(self.state()["closed"], initially_closed + 1)

    def test_cancel_before_first_frame_and_disabled_animations(self):
        self.command("request", True)
        self.command("request", False)
        self.command("attach", True)
        self.command("frame", 1000)
        self.assertEqual(self.state()["progress"], 0)
        self.assertFalse(self.state()["active"])
        self.command("animate", False)
        self.command("request", True)
        self.assertEqual(self.state()["progress"], 1)
        self.command("request", False)
        self.assertEqual(self.state()["progress"], 0)
        self.assertFalse(self.state()["active"])

    def test_existing_popups_still_animate_without_a_frame_source(self):
        for opened, target in [(True, 1), (False, 0)]:
            self.command("legacyRequest", opened)
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                state = self.state()
                if state["legacyProgress"] == target:
                    break
                time.sleep(.02)
            self.assertEqual(state["legacyProgress"], target)
            self.assertEqual(state["legacyActive"], opened)


if __name__ == "__main__":
    unittest.main()
