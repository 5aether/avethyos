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
            "HOME": str(self.path / "home"),
            "XDG_STATE_HOME": str(self.path / "state"),
            "XDG_CONFIG_HOME": str(self.path / "home/.config"),
            "PATH": str(self.bin) + ":/usr/bin:/bin",
            "AVETHY_TEST_LOG": str(self.path / "events"),
            "AVETHY_TEST_HELPER_ARGS": str(self.path / "helper-args"),
            "AVETHY_TEST_ICON_ARGS": str(self.path / "icon-args"),
            "AVETHY_TEST_QS_ARGS": str(self.path / "qs-args"),
            "AVETHY_TEST_QS_ENV": str(self.path / "qs-env"),
            "AVETHY_TEST_EXPORTS": str(self.path / "exports"),
            "AVETHY_TEST_APPLY_RESULT": "0",
            "AVETHY_TEST_ICON_PACK": "",
        })
        self.stub("python3", """#!/bin/sh
case "$1" in
    */icon-theme.py) printf '%s\\n' "$@" > "$AVETHY_TEST_ICON_ARGS"; printf '%s\\n' "$AVETHY_TEST_ICON_PACK"; exit 0 ;;
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

    def test_launcher_reads_persistent_state_and_preserves_existing_settings(self):
        config = self.path / "state/avethyos/quickshell/config.ini"
        config.parent.mkdir(parents=True)
        config.write_text("[wallpaper]\npath=/user/wallpaper.mp4\n")
        (self.path / "exports").write_text("")
        result = self.run_launcher()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("[wallpaper]\npath=/user/wallpaper.mp4\n", config.read_text())
        self.assertEqual([str(ROOT / "scripts/icon-theme.py"), "--config", str(config)],
                         (self.path / "icon-args").read_text().splitlines())

    def test_launcher_migrates_legacy_settings_to_default_state_home(self):
        self.environment["XDG_STATE_HOME"] = "relative-state"
        self.environment["XDG_CONFIG_HOME"] = "relative-config"
        legacy = self.path / "home/.config/quickshell/config.ini"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("[appearance]\nicon-pack=Custom-Pack\n")
        (self.path / "exports").write_text("")
        result = self.run_launcher()
        self.assertEqual(0, result.returncode, result.stderr)
        config = self.path / "home/.local/state/avethyos/quickshell/config.ini"
        self.assertEqual(legacy.read_text(), config.read_text())

    def test_atomic_seed_preserves_preferences_created_by_a_concurrent_initializer(self):
        self.stub("ln", """#!/bin/sh
printf '[appearance]\\nicon-pack=Concurrent-User-Pack\\n' > "$2"
exec /usr/bin/ln "$@"
""")
        (self.path / "exports").write_text("")
        result = self.run_launcher()
        self.assertEqual(0, result.returncode, result.stderr)
        config = self.path / "state/avethyos/quickshell/config.ini"
        self.assertEqual("[appearance]\nicon-pack=Concurrent-User-Pack\n", config.read_text())
        self.assertEqual([], list(config.parent.glob(".config.*")))

    def test_brightness_helper_addresses_this_shell_with_native_ipc(self):
        self.stub("ddcutil", """#!/bin/sh
case "$1" in
    getvcp) printf 'VCP 10 C 55 100\\n' ;;
esac
""")
        result = subprocess.run(["bash", str(ROOT / "scripts/brightness.sh"), "1", "+", "5"],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["-p", str(ROOT), "ipc", "call", "osd", "brightness", "55"],
                         (self.path / "qs-args").read_text().splitlines())


class ImmutableRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.home = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.package = self.home / "usr/share/avethyos/quickshell"
        self.package.mkdir(parents=True)
        self.config = self.home / "state/avethyos/quickshell/config.ini"
        self.config.parent.mkdir(parents=True)
        self.qt6 = self.package / "native/qt-theme/build-qt6/plugins"
        self.qt5 = self.package / "native/qt-theme/build-qt5/plugins"
        self.qml = self.package / "native/qt-theme/qml"
        self.theme = self.home / "state/avethyos/hypr/theme.lua"
        for key, value in (("HOME", self.home), ("ROOT", self.package),
                           ("CONFIG_HOME", self.home / ".config"),
                           ("QT_THEME_DIR", self.home / ".config/avethy"),
                           ("SHELL_CONFIG", self.config), ("HYPR_THEME", self.theme),
                           ("QT_PLUGIN_DIR", self.qt6), ("QT5_PLUGIN_DIR", self.qt5),
                           ("QT_QML_DIR", self.qml)):
            self.stack.enter_context(patch.object(palette, key, value))

    def write_plugins(self):
        for directory, major in ((self.qt5, 5), (self.qt6, 6)):
            for kind, stem in (("styles", "style"), ("generic", "theme")):
                target = directory / kind / f"libavethy-{stem}-qt{major}.so"
                target.parent.mkdir(parents=True)
                target.write_bytes(f"version one qt{major}".encode())
        (self.qml / "Avethy").mkdir(parents=True)
        (self.qml / "Avethy/Theme.qml").write_text("version one")

    def test_wallpaper_and_icon_selection_come_from_state_instead_of_image_defaults(self):
        (self.package / "config.ini").write_text("[appearance]\nicon-pack=Image-Pack\n"
                                                 "[wallpaper]\npath=/image/default.png\n")
        self.config.write_text("[appearance]\nicon-pack=User-Pack\n"
                               "[wallpaper]\npath=/user/custom.mp4\n")
        self.assertEqual("/user/custom.mp4", palette.wallpaper_from_config())
        self.assertEqual("User-Pack", palette.desktop_icon_theme("dark"))

    def test_host_plugins_and_qml_load_directly_from_current_image(self):
        self.write_plugins()
        obsolete = self.home / ".local/lib/avethy/qt-plugins"
        legacy = self.home / ".local/lib/quickshell/qt-plugins"
        with patch.dict(os.environ, {"QT_PLUGIN_PATH": f"{obsolete}:{legacy}:/third-party",
                                     "QML_IMPORT_PATH": f"{obsolete}/qml:{legacy}/qml:/extra-qml"}, clear=True):
            environment = palette.qt_environment("dark")
        self.assertEqual(f"{self.qt6}:{self.qt5}:/third-party", environment["QT_PLUGIN_PATH"])
        self.assertEqual(f"{self.qml}:/extra-qml", environment["QML_IMPORT_PATH"])
        self.assertEqual(str(self.qml), environment["QT_QUICK_CONTROLS_STYLE_PATH"])
        self.assertFalse(obsolete.exists(), "Host startup must not install stale user copies")

    def test_flatpak_copies_refresh_updated_and_removed_image_assets(self):
        self.write_plugins()
        destination = self.home / ".var/app/example/config/avethy/qt-plugins"
        palette.copy_native_qt_plugins(destination)
        copied = destination / "styles/libavethy-style-qt6.so"
        self.assertEqual(b"version one qt6", copied.read_bytes())
        (self.qt6 / "styles/libavethy-style-qt6.so").write_bytes(b"version two")
        (self.qt5 / "styles/libavethy-style-qt5.so").unlink()
        (self.qml / "Avethy/Theme.qml").unlink()
        (self.qml / "Avethy/New.qml").write_text("new style component")
        palette.copy_native_qt_plugins(destination)
        self.assertEqual(b"version two", copied.read_bytes())
        self.assertFalse((destination / "styles/libavethy-style-qt5.so").exists())
        self.assertFalse((destination / "qml/Avethy/Theme.qml").exists())
        self.assertEqual("new style component", (destination / "qml/Avethy/New.qml").read_text())

    def test_generated_hypr_theme_is_written_in_state_without_rewriting_preferences(self):
        preferences = self.home / ".config/hypr/shortcuts.lua"
        preferences.parent.mkdir(parents=True)
        preferences.write_text("-- My shortcuts stay mine.\n")
        roles = palette.material_roles(palette.tonal_palette((30, 80, 140)))["dark"]
        with patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette.subprocess, "run") as run, \
                patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "test"}, clear=True):
            palette.sync_qt_gtk_environment(roles, "dark")
        self.assertIn(f'active_border = "rgba({roles["primary"][1:]}ff)"', self.theme.read_text())
        self.assertEqual("-- My shortcuts stay mine.\n", preferences.read_text())
        self.assertFalse((preferences.parent / "theme.lua").exists())
        self.assertTrue(any(call.args[0] == ["hyprctl", "reload"] for call in run.call_args_list))

    def test_custom_xdg_state_home_is_used_when_module_is_loaded(self):
        state = self.home / "custom-state"
        spec = importlib.util.spec_from_file_location("palette_state_fixture", ROOT / "scripts/material-palette.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(os.environ, {"XDG_STATE_HOME": str(state)}):
            spec.loader.exec_module(module)
        self.assertEqual(state / "avethyos/quickshell/config.ini", module.SHELL_CONFIG)
        self.assertEqual(state / "avethyos/hypr/theme.lua", module.HYPR_THEME)

    def test_custom_xdg_config_home_is_used_for_generated_toolkit_files(self):
        config = self.home / "custom-config"
        self.config.write_text("[appearance]\nicon-pack=Test-Pack\n")
        roles = palette.material_roles(palette.tonal_palette((30, 80, 140)))["dark"]
        with patch.object(palette, "CONFIG_HOME", config), \
                patch.object(palette, "QT_THEME_DIR", config / "avethy"), \
                patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette.subprocess, "run"), \
                patch.dict(os.environ, {}, clear=True):
            palette.install_qt(roles, "dark")
            palette.sync_qt_gtk_environment(roles, "dark")
            environment = palette.qt_environment("dark")
        self.assertTrue((config / "avethy/palette.json").is_file())
        self.assertTrue((config / "qt6ct/gtk3-palette.json").is_file())
        self.assertTrue((config / "environment.d/90-avethy-theme.conf").is_file())
        self.assertEqual(str(config / "qt6ct/gtk3-palette.json"), environment["QT_GUI_GTK_JSON"])
        self.assertIn(str(config / "qt6ct/gtk3-palette.json"), self.theme.read_text())
        self.assertFalse((self.home / ".config").exists())

    def test_custom_xdg_config_home_is_used_when_module_is_loaded(self):
        config = self.home / "custom-config"
        spec = importlib.util.spec_from_file_location("palette_config_fixture", ROOT / "scripts/material-palette.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config)}):
            spec.loader.exec_module(module)
        self.assertEqual(config, module.CONFIG_HOME)
        self.assertEqual(config / "avethy", module.QT_THEME_DIR)

    def test_relative_xdg_homes_are_ignored_in_favor_of_home_defaults(self):
        spec = importlib.util.spec_from_file_location("palette_relative_fixture", ROOT / "scripts/material-palette.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(os.environ, {"HOME": str(self.home), "XDG_CONFIG_HOME": "relative-config",
                                     "XDG_STATE_HOME": "relative-state"}):
            spec.loader.exec_module(module)
        self.assertEqual(self.home / ".config", module.CONFIG_HOME)
        self.assertEqual(self.home / ".local/state", module.STATE_HOME)


if __name__ == "__main__":
    unittest.main()
