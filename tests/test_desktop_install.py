"""Check the image desktop installation without writing to the host's /usr."""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class DesktopInstallTests(unittest.TestCase):
    def test_managed_assets_permissions_and_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            image = root / "image"
            fixtures = {
                "quickshell/shell.qml": "import Quickshell\n",
                "quickshell/config.ini": "[appearance]\nicon-pack = Papirus\n",
                "quickshell/scripts/run.sh": "#!/bin/sh\nexit 0\n",
                "quickshell/scripts/helper.py": "print('helper')\n",
                "quickshell/assets/shaders/panel.frag": "shader source\n",
                "quickshell/native/qt-theme/qml/Avethy/qmldir": "module Avethy\n",
                "quickshell/native/qt-theme/build-qt5/stale.so": "old local build\n",
                "quickshell/tests/test.py": "test code\n",
                "quickshell/scripts/__pycache__/helper.pyc": "cache\n",
                "hypr/hyprland.lua": "-- managed\n",
                "hypr/commands.lua": "return {}\n",
                "hypr/user/shortcuts.lua": "-- user template\n",
                "hypr/.git/config": "checkout metadata\n",
            }
            for name, content in fixtures.items():
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
                path.chmod(0o777)
            shaders = image / "usr/share/avethyos/quickshell/shaders"
            shaders.mkdir(parents=True)
            (shaders / "panel.frag.qsb").write_bytes(b"compiled shader")
            for name in ("hypr", "quickshell"):
                old = image / "etc/skel/.config" / name
                old.mkdir(parents=True)
                (old / "stale-config").touch()

            # The host and CI need no RPM installation for this staging check.
            binaries = root / "bin"
            binaries.mkdir()
            rpm = binaries / "rpm"
            rpm.write_text("#!/bin/sh\nprintf '%s\\n' /usr/lib64\n")
            rpm.chmod(0o755)
            env = dict(os.environ, DESTDIR=str(image), DESKTOP_SOURCE_DIR=str(source),
                       PATH=str(binaries) + ":" + os.environ["PATH"])
            subprocess.run(["bash", str(REPO / "build_files/layers/desktop-configs.sh")],
                           env=env, check=True, capture_output=True, text=True)

            desktop = image / "usr/share/avethyos"
            shell = desktop / "quickshell"
            hypr = desktop / "hypr"
            self.assertEqual((shell / "shell.qml").read_text(), fixtures["quickshell/shell.qml"])
            self.assertEqual((hypr / "user/shortcuts.lua").read_text(), "-- user template\n")
            self.assertEqual((shell / "assets/shaders/panel.frag.qsb").read_bytes(), b"compiled shader")
            for major in (5, 6):
                plugin = shell / f"native/qt-theme/build-qt{major}"
                self.assertTrue(plugin.is_symlink())
                self.assertEqual(os.readlink(plugin), f"/usr/lib64/avethyos/qt-theme/qt{major}")
            for path in (shell / "tests", shell / "scripts/__pycache__", hypr / ".git"):
                self.assertFalse(path.exists(), str(path))
            for path in desktop.rglob("*"):
                if path.is_symlink():
                    continue
                mode = stat.S_IMODE(path.stat().st_mode)
                self.assertEqual(mode & 0o022, 0, str(path))
                self.assertTrue(mode & 0o004, str(path))
            self.assertEqual(stat.S_IMODE((shell / "scripts/run.sh").stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((shell / "scripts/helper.py").stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((hypr / "commands.lua").stat().st_mode), 0o644)
            self.assertFalse((image / "etc/skel/.config/quickshell").exists())
            self.assertFalse((image / "etc/skel/.config/hypr").exists())


if __name__ == "__main__":
    unittest.main()
