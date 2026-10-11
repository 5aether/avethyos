"""Isolated checks for palette restoration and the desktop launch environment."""

from contextlib import ExitStack, redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("avethy_startup_palette", ROOT / "scripts/material-palette.py")
palette = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(palette)


class ThemeStartupTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.home = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.cache = self.home / ".cache/avethy"
        self.file = self.cache / "palette.ini"
        self.source = "/wallpapers/a color palette.png"
        self.roles = palette.material_roles(palette.tonal_palette((186, 45, 99)))
        for name, value in (("HOME", self.home), ("CACHE", self.cache), ("PALETTE_FILE", self.file)):
            self.stack.enter_context(patch.object(palette, name, value))
        self.wallpaper = self.stack.enter_context(patch.object(palette, "wallpaper_from_config", return_value=self.source))
        self.apply = self.stack.enter_context(patch.object(palette, "apply"))
        self.generate = self.stack.enter_context(patch.object(palette, "generate"))

    def write_cache(self, path=None, source=None, roles=None):
        path = path or self.file
        path.parent.mkdir(parents=True, exist_ok=True)
        text = "source=" + (self.source if source is None else source) + "\n"
        for mode, values in (self.roles if roles is None else roles).items():
            text += "".join(f"{mode}.{key}={value}\n" for key, value in values.items())
        path.write_text(text, encoding="utf-8")

    def test_complete_matching_palette_is_applied_in_either_mode(self):
        self.write_cache()
        for mode in ("dark", "light"):
            with self.subTest(mode=mode):
                self.apply.reset_mock()
                palette.startup(mode)
                self.apply.assert_called_once_with(self.roles, mode)
                self.generate.assert_not_called()

    def test_legacy_cache_is_migrated_without_changing_its_primary(self):
        # A previously chosen accent must survive a startup/name migration.
        self.roles["dark"]["primary"] = "#ffa5d3"
        self.write_cache(self.home / ".cache/quickshell/material-palette.ini")
        palette.startup("dark")
        self.assertTrue(self.file.is_file())
        self.assertIn("name=Avethy\n", self.file.read_text())
        self.assertEqual("#ffa5d3", palette.read_roles()["dark"]["primary"])
        self.apply.assert_called_once_with(self.roles, "dark")
        self.generate.assert_not_called()

    def test_current_cache_takes_precedence_over_legacy_cache(self):
        self.write_cache()
        self.write_cache(self.home / ".cache/quickshell/material-palette.ini", source="/old/wallpaper.png")
        palette.startup("light")
        self.apply.assert_called_once_with(self.roles, "light")
        self.generate.assert_not_called()

    def test_missing_palette_is_generated_in_requested_mode(self):
        palette.startup("light")
        self.generate.assert_called_once_with(self.source, "light")
        self.apply.assert_not_called()

    def test_incomplete_palette_in_either_mode_is_regenerated(self):
        for appearance in ("dark", "light"):
            with self.subTest(appearance=appearance):
                incomplete = {mode: values.copy() for mode, values in self.roles.items()}
                del incomplete[appearance]["on_primary"]
                self.write_cache(roles=incomplete)
                self.generate.reset_mock()
                palette.startup("dark")
                self.generate.assert_called_once_with(self.source, "dark")
                self.apply.assert_not_called()

    def test_changed_wallpaper_is_regenerated(self):
        self.write_cache(source="/wallpapers/previous.png")
        palette.startup("light")
        self.generate.assert_called_once_with(self.source, "light")
        self.apply.assert_not_called()

    def test_invalid_cached_color_does_not_get_applied(self):
        self.write_cache()
        self.file.write_text(self.file.read_text().replace(self.roles["dark"]["primary"], "broken"))
        palette.startup("dark")
        self.generate.assert_called_once_with(self.source, "dark")
        self.apply.assert_not_called()

    def test_cli_forwards_mode_and_quotes_export_values(self):
        environment = {"QT_STYLE_OVERRIDE": "Avethy", "QML_IMPORT_PATH": "/a path/it's here:$HOME;$(false)"}
        output = io.StringIO()
        with patch.object(palette.sys, "argv", ["material-palette.py", "--startup", "--mode", "light", "--shell-environment"]), \
                patch.object(palette, "startup") as startup, \
                patch.object(palette, "qt_environment", return_value=environment) as exports, \
                redirect_stdout(output):
            self.assertEqual(0, palette.main())
        startup.assert_called_once_with("light")
        exports.assert_called_once_with("light")
        self.assertEqual("".join(f"export {key}={shlex.quote(value)}\n" for key, value in environment.items()), output.getvalue())


class ThemeLauncherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.bin = self.path / "bin"
        self.bin.mkdir()
        self.environment = os.environ.copy()
        self.environment.update({
            "PATH": str(self.bin) + ":/usr/bin:/bin",
            "AVETHY_TEST_LOG": str(self.path / "events"),
            "AVETHY_TEST_HELPER_ARGS": str(self.path / "helper-args"),
            "AVETHY_TEST_QS_ARGS": str(self.path / "qs-args"),
            "AVETHY_TEST_QS_ENV": str(self.path / "qs-env"),
            "AVETHY_TEST_EXPORTS": str(self.path / "exports"),
            "AVETHY_TEST_APPLY_RESULT": "0",
            "AVETHY_TEST_ICON_PACK": "",
        })
        self.stub("python3", """#!/bin/sh
case "$1" in
    */icon-theme.py) printf '%s\\n' "$AVETHY_TEST_ICON_PACK"; exit 0 ;;
esac
printf '%s\\n' "$@" > "$AVETHY_TEST_HELPER_ARGS"
printf 'apply\\n' >> "$AVETHY_TEST_LOG"
if [ "$AVETHY_TEST_APPLY_RESULT" != 0 ]; then exit "$AVETHY_TEST_APPLY_RESULT"; fi
/usr/bin/cat "$AVETHY_TEST_EXPORTS"
""")
        self.stub("qs", """#!/bin/sh
printf 'launch\\n' >> "$AVETHY_TEST_LOG"
printf '%s\\n' "$@" > "$AVETHY_TEST_QS_ARGS"
/usr/bin/env > "$AVETHY_TEST_QS_ENV"
""")

    def stub(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def run_launcher(self):
        return subprocess.run(["/bin/sh", str(ROOT / "scripts/run.sh"), "--no-duplicate", "--daemonize"],
                              env=self.environment, capture_output=True, text=True, timeout=10)

    def test_theme_applies_before_launch_and_exports_are_preserved_safely(self):
        marker = self.path / "must-not-be-created"
        expected = {
            "QT_STYLE_OVERRIDE": "Avethy",
            "QT_QUICK_CONTROLS_STYLE": "Avethy",
            "GTK_THEME": "Avethy-dark",
            "QT_PLUGIN_PATH": f"/a path/it's plugins;$(touch {marker})",
            "AVETHY_QT_THEME": str(self.path / "palette.json"),
        }
        (self.path / "exports").write_text("".join(f"export {key}={shlex.quote(value)}\n" for key, value in expected.items()))
        result = self.run_launcher()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["apply", "launch"], (self.path / "events").read_text().splitlines())
        self.assertEqual([str(ROOT / "scripts/material-palette.py"), "--startup", "--shell-environment"],
                         (self.path / "helper-args").read_text().splitlines())
        self.assertEqual(["-p", str(ROOT), "--no-duplicate", "--daemonize"],
                         (self.path / "qs-args").read_text().splitlines())
        actual = dict(line.split("=", 1) for line in (self.path / "qs-env").read_text().splitlines() if "=" in line)
        for key, value in expected.items():
            self.assertEqual(value, actual[key])
        self.assertEqual("1", actual["AVETHY_THEME_READY"])
        self.assertFalse(marker.exists())

    def test_apply_failure_stops_launch(self):
        self.environment["AVETHY_TEST_APPLY_RESULT"] = "2"
        result = self.run_launcher()
        self.assertEqual(1, result.returncode)
        self.assertIn("Avethy: could not apply desktop themes; shell startup stopped", result.stderr)
        self.assertEqual(["apply"], (self.path / "events").read_text().splitlines())
        self.assertFalse((self.path / "qs-env").exists())

    def test_icon_pack_reaches_qt_without_evaluating_its_contents(self):
        marker = self.path / "must-not-be-created"
        pack = f"Papirus;$(touch {marker})"
        self.environment["AVETHY_TEST_ICON_PACK"] = pack
        (self.path / "exports").write_text("")
        result = self.run_launcher()
        self.assertEqual(0, result.returncode, result.stderr)
        actual = dict(line.split("=", 1) for line in (self.path / "qs-env").read_text().splitlines() if "=" in line)
        self.assertEqual(pack, actual["QS_ICON_THEME"])
        self.assertFalse(marker.exists())

    def test_empty_icon_pack_follows_the_desktop_theme(self):
        self.environment["QS_ICON_THEME"] = "OldPack"
        (self.path / "exports").write_text("")
        result = self.run_launcher()
        self.assertEqual(0, result.returncode, result.stderr)
        actual = (self.path / "qs-env").read_text()
        self.assertNotIn("QS_ICON_THEME=", actual)


if __name__ == "__main__":
    unittest.main()
