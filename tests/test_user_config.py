"""Account lifecycle checks use isolated home, XDG directories, and image defaults."""

import importlib.machinery
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "system_files/usr/libexec/avethyos-user-config"
LOADER = importlib.machinery.SourceFileLoader("avethyos_user_config", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
initializer = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(initializer)

LEGACY = '''hl.monitor({ output = "DP-1)", mode = "2560x1440@144", scale = 1 })
local terminal = "foot"
local fileManager = "thunar"
local appmenu = "qs ipc call applauncher toggle"
local control_center = "qs ipc call controlcenter toggle"
local notifications = "qs ipc call clock toggle"
local clipboard = "qs ipc call clipboard toggle"
local screenshot = "hyprshot -m region --freeze"
hl.on("hyprland.start", function()
    hl.env("OWNED_NESTED", "old")
    hl.exec_cmd("bash ~/.config/quickshell/scripts/run.sh")
end)
hl.env("XCURSOR_SIZE", "24")
hl.config({ general = { gaps_out = 17 } })
hl.layer_rule({ name = "qs-launcher-blur", blur = true })
require("theme")
hl.curve("custom", { type = "spring", mass = 2 })
hl.config({ dwindle = { preserve_split = true } })
hl.config({ input = { kb_layout = "fr", sensitivity = 0.7 } })
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
local mainMod = "ALT"
for _, key in ipairs({ { mainMod .. "_L", "left" }, { mainMod .. "_R", "right" } }) do
    hl.bind(key[1], hl.dsp.event("quickshell-workspace-apps," .. key[2] .. ",1"))
    hl.bind(key[1], hl.dsp.event("quickshell-workspace-apps," .. key[2] .. ",0"), { release = true })
end
hl.on("config.reloaded", function()
    hl.dispatch(hl.dsp.event("quickshell-workspace-apps,reset"))
end)
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/reload-qs.sh"))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox --new-window"))
for i = 1, 10 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
end
local suppressMaximizeRule = hl.window_rule({ name = "my-maximize-rule", suppress_event = "maximize" })
hl.window_rule({ name = "my-browser", match = { class = "firefox" }, float = true })
'''


def concurrent_initialize(home, config, state, defaults, preferences):
    initializer.initialize(home, config, state, hypr_defaults=defaults, shell_defaults=preferences)


class UserConfigTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.config = self.home / ".config"
        self.state = self.home / ".local/state"
        self.data = self.home / ".local/share"
        self.defaults = self.root / "image/hypr/user"
        self.defaults.mkdir(parents=True)
        for name in ("shortcuts.lua", "monitors.lua", "appearance.lua", "input.lua", "window-rules.lua", "custom.lua",
                     "hypridle.conf", "hyprlock.conf"):
            (self.defaults / name).write_text(f"-- image default: {name}\n")
        self.shell_default = self.root / "image/quickshell/config.ini"
        self.shell_default.parent.mkdir()
        self.shell_default.write_text("[wallpaper]\npath=\n")

    def initialize(self):
        initializer.initialize(self.home, self.config, self.state, self.data, hypr_defaults=self.defaults,
                               shell_defaults=self.shell_default)

    @property
    def preferences(self):
        return self.state / "avethyos/quickshell/config.ini"

    @property
    def backup(self):
        return self.state / "avethyos/legacy-desktop"

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def old_desktop(self, monolith=LEGACY):
        self.write(self.config / "hypr/hyprland.lua", monolith)
        self.write(self.config / "hypr/theme.lua", 'hl.env("OLD_THEME", "yes")\n')
        self.write(self.config / "hypr/scripts/reload-qs.sh", "old reload helper\n")
        self.write(self.config / "quickshell/shell.qml", "old shell\n")
        self.write(self.config / "quickshell/config.ini", "[wallpaper]\npath=/pictures/custom wallpaper.png\nfillMode=fit\n")

    def test_fresh_account_seeds_only_writable_preferences(self):
        self.initialize()
        for path in self.defaults.iterdir():
            self.assertEqual(path.read_bytes(), (self.config / "hypr" / path.name).read_bytes())
        self.assertEqual(self.shell_default.read_bytes(), self.preferences.read_bytes())
        self.assertFalse((self.config / "quickshell").exists())
        self.assertFalse((self.config / "hypr/hyprland.lua").exists())
        self.assertFalse(self.backup.exists())

    def test_image_upgrade_preserves_modified_and_empty_files_and_seeds_new_defaults(self):
        self.initialize()
        self.write(self.config / "hypr/shortcuts.lua", "my edited shortcuts\n")
        self.write(self.config / "hypr/monitors.lua", "")
        self.write(self.preferences, "")
        for path in self.defaults.iterdir():
            path.write_text("changed image default\n")
        self.shell_default.write_text("changed image preferences\n")
        (self.defaults / "new-preference.lua").write_text("new default\n")
        self.initialize()
        self.assertEqual("my edited shortcuts\n", (self.config / "hypr/shortcuts.lua").read_text())
        self.assertEqual("", (self.config / "hypr/monitors.lua").read_text())
        self.assertEqual("", self.preferences.read_text())
        self.assertEqual("new default\n", (self.config / "hypr/new-preference.lua").read_text())

    def test_migration_keeps_shortcuts_launch_preferences_and_wallpaper_and_archives_code(self):
        self.old_desktop()
        self.write(self.config / "hypr/hypridle.conf", "custom idle configuration\n")
        self.initialize()
        self.assertEqual(LEGACY, (self.backup / "hypr/hyprland.lua").read_text())
        self.assertEqual("old shell\n", (self.backup / "quickshell/shell.qml").read_text())
        self.assertIn("custom wallpaper.png", self.preferences.read_text())
        self.assertTrue((self.backup / "hypr/theme.lua").is_file())
        self.assertTrue((self.backup / "hypr/scripts/reload-qs.sh").is_file())
        self.assertEqual("custom idle configuration\n", (self.config / "hypr/hypridle.conf").read_text())
        shortcuts = (self.config / "hypr/shortcuts.lua").read_text()
        for preserved in ('local terminal = "foot"', 'local fileManager = "thunar"', 'local mainMod = "ALT"',
                          "firefox --new-window", "for i = 1, 10 do", "commands.appmenu", "commands.restart_shell"):
            self.assertIn(preserved, shortcuts)
        self.assertIn("hl.dsp.exec_cmd(restart_shell)", shortcuts)
        self.assertNotIn("reload-qs.sh", shortcuts)
        user_content = "\n".join(path.read_text() for path in (self.config / "hypr").glob("*.lua"))
        for removed in ("quickshell-workspace-apps", 'hl.on("hyprland.start"', 'hl.on("config.reloaded"',
                        "hl.env(", "hl.layer_rule(", "qs ipc call", 'require("theme")'):
            self.assertNotIn(removed, user_content)
        self.assertIn('kb_layout = "fr"', (self.config / "hypr/input.lua").read_text())
        self.assertIn("gaps_out = 17", (self.config / "hypr/appearance.lua").read_text())
        self.assertIn("my-browser", (self.config / "hypr/window-rules.lua").read_text())
        self.assertIn('output = "DP-1)"', (self.config / "hypr/monitors.lua").read_text())
        self.assertFalse((self.config / "quickshell").exists())
        self.assertFalse((self.config / "hypr/theme.lua").exists())
        self.assertFalse((self.config / "hypr/scripts").exists())
        self.initialize()
        self.assertEqual({"hypr", "quickshell", "MIGRATION.txt"}, {path.name for path in self.backup.iterdir()})

    def test_histories_and_image_payload_paths_migrate_without_changing_clipboard_text(self):
        old = self.home / ".local/share/quickshell"
        self.write(old / "notifications.json", '[{"summary": "saved notification"}]\n')
        self.write(old / "app-usage.json", '{"firefox.desktop": 7}\n')
        self.write(old / "clipboard-media/nested/image.png", "saved image payload")
        self.write(old / "clipboard-media/preview.png", "saved preview")
        original = [{"kind": "text", "text": str(old / "clipboard-media/keep-this-text")},
                    {"kind": "image", "payload": str(old / "clipboard-media/nested/image.png"),
                     "preview": str(old / "clipboard-media/preview.png"), "mime": "image/png"}]
        self.write(old / "clipboard.json", json.dumps(original))
        self.initialize()
        destination = self.preferences.parent
        self.assertIn("saved notification", (destination / "notifications.json").read_text())
        self.assertEqual({"firefox.desktop": 7}, json.loads((destination / "app-usage.json").read_text()))
        history = json.loads((destination / "clipboard.json").read_text())
        self.assertEqual(original[0], history[0])
        for key, filename in (("payload", "nested/image.png"), ("preview", "preview.png")):
            self.assertEqual(str(destination / "clipboard-media" / filename), history[1][key])
            self.assertTrue(Path(history[1][key]).is_file())
        self.assertEqual(original, json.loads((old / "clipboard.json").read_text()))
        self.assertTrue((old / "clipboard-media/nested/image.png").is_file())

    def test_existing_histories_and_media_keep_precedence(self):
        old = self.home / ".local/share/quickshell"
        destination = self.preferences.parent
        self.write(old / "notifications.json", "old notifications")
        self.write(old / "clipboard.json", "old clipboard")
        self.write(old / "app-usage.json", "old usage")
        self.write(old / "clipboard-media/original.png", "old payload")
        for name in ("notifications.json", "clipboard.json", "app-usage.json"):
            self.write(destination / name, "")
        (destination / "clipboard-media").mkdir()
        self.initialize()
        for name in ("notifications.json", "clipboard.json", "app-usage.json"):
            self.assertEqual("", (destination / name).read_text())
        self.assertFalse((destination / "clipboard-media/original.png").exists())
        self.assertEqual("old payload", (old / "clipboard-media/original.png").read_text())

    def test_home_histories_have_priority_and_custom_xdg_data_fills_missing_files(self):
        old = self.home / ".local/share/quickshell"
        self.data = self.root / "custom-data"
        self.write(old / "notifications.json", "home history wins")
        self.write(self.data / "quickshell/notifications.json", "custom notifications")
        self.write(self.data / "quickshell/app-usage.json", "custom usage")
        self.initialize()
        self.assertEqual("home history wins", (self.preferences.parent / "notifications.json").read_text())
        self.assertEqual("custom usage", (self.preferences.parent / "app-usage.json").read_text())

    def test_malformed_clipboard_history_is_preserved_verbatim(self):
        old = self.home / ".local/share/quickshell"
        self.write(old / "clipboard.json", "not valid JSON\n")
        self.write(old / "clipboard-media/image.png", "old image")
        self.initialize()
        self.assertEqual("not valid JSON\n", (self.preferences.parent / "clipboard.json").read_text())

    def test_fallback_appmenu_and_command_help_are_available_in_migrated_shortcuts(self):
        legacy = LEGACY.replace('local appmenu =', 'local fallback_appmenu = "rofi -show drun"\nlocal appmenu =')
        legacy = legacy.replace('hl.bind(mainMod .. " + B",', 'hl.bind(mainMod .. " + F12", hl.dsp.exec_cmd(fallback_appmenu))\nhl.bind(mainMod .. " + B",')
        self.old_desktop(legacy)
        self.initialize()
        shortcuts = (self.config / "hypr/shortcuts.lua").read_text()
        self.assertIn('local fallback_appmenu = "rofi -show drun"', shortcuts)
        for variable in ("appmenu", "applauncher", "control_center", "notifications", "clipboard", "screenshot", "restart_shell"):
            self.assertIn("-- commands." + variable + ":", shortcuts)
        for variable in ("terminal", "fileManager", "mainMod"):
            self.assertIn("-- " + variable + ":", shortcuts)

    def test_commented_lua_declarations_do_not_replace_real_launch_preferences(self):
        legacy = '--[[\nlocal terminal = "wrong terminal"\nlocal fileManager = "wrong browser"\n]]\n' + LEGACY
        extracted = initializer.migrate_monolith(legacy)
        self.assertIn('local terminal = "foot"', extracted["shortcuts.lua"])
        self.assertNotIn("wrong terminal", extracted["shortcuts.lua"])

    def test_custom_command_preferences_and_complete_launch_expressions_survive(self):
        legacy = LEGACY.replace('local terminal = "foot"', 'local preferred_terminal = "foot"\nlocal terminal = os.getenv("TERMINAL") or preferred_terminal\nlocal editor = "code --new-window"\nlocal launch_shell = appmenu')
        legacy = legacy.replace('hl.bind(mainMod .. " + B",', 'hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(editor))\nhl.bind(mainMod .. " + B",')
        self.old_desktop(legacy)
        self.initialize()
        shortcuts = (self.config / "hypr/shortcuts.lua").read_text()
        self.assertIn('local terminal = os.getenv("TERMINAL") or preferred_terminal', shortcuts)
        self.assertIn('local editor = "code --new-window"', shortcuts)
        self.assertIn('hl.dsp.exec_cmd(editor)', shortcuts)
        self.assertLess(shortcuts.index('local preferred_terminal'), shortcuts.index('local terminal'))
        self.assertLess(shortcuts.index('local appmenu = commands.appmenu'), shortcuts.index('local launch_shell = appmenu'))

    def test_multiline_launch_expression_remains_in_recoverable_backup(self):
        legacy = LEGACY.replace('local terminal = "foot"', 'local terminal = "foot" ..\n " --server"')
        self.old_desktop(legacy)
        self.initialize()
        self.assertEqual(legacy, (self.backup / "hypr/hyprland.lua").read_text())
        self.assertIn("Unrecognized Lua layout", (self.backup / "MIGRATION.txt").read_text())

    def test_user_added_script_remains_runnable_at_its_existing_shortcut_path(self):
        self.old_desktop()
        helper = self.config / "hypr/scripts/custom.sh"
        self.write(helper, "#!/bin/sh\nprintf 'custom user helper\\n'\n")
        helper.chmod(0o755)
        monolith = self.config / "hypr/hyprland.lua"
        monolith.write_text(monolith.read_text().replace('hl.bind(mainMod .. " + B",',
            'hl.bind(mainMod .. " + F11", hl.dsp.exec_cmd("~/.config/hypr/scripts/custom.sh"))\nhl.bind(mainMod .. " + B",'))
        self.initialize()
        self.assertTrue(helper.is_file())
        result = subprocess.run([str(helper)], check=True, capture_output=True, text=True)
        self.assertEqual("custom user helper\n", result.stdout)
        self.assertIn("~/.config/hypr/scripts/custom.sh", (self.config / "hypr/shortcuts.lua").read_text())
        self.assertFalse((self.config / "hypr/scripts/reload-qs.sh").exists())
        self.assertTrue((self.backup / "hypr/scripts/reload-qs.sh").exists())

    def test_unknown_monolith_is_saved_without_being_executed(self):
        marker = self.root / "must-not-be-created"
        unknown = f'os.execute("touch {marker}")\nrequire("my-personal-config")\n'
        self.old_desktop(unknown)
        self.initialize()
        self.assertFalse(marker.exists())
        self.assertEqual(unknown, (self.backup / "hypr/hyprland.lua").read_text())
        self.assertIn("Unrecognized Lua layout", (self.backup / "MIGRATION.txt").read_text())
        self.assertEqual((self.defaults / "shortcuts.lua").read_text(),
                         (self.config / "hypr/shortcuts.lua").read_text())

    def test_existing_new_preferences_take_priority_over_old_defaults(self):
        self.old_desktop()
        self.write(self.preferences, "new settings win\n")
        self.write(self.config / "hypr/shortcuts.lua", "")
        self.initialize()
        self.assertEqual("new settings win\n", self.preferences.read_text())
        self.assertEqual("", (self.config / "hypr/shortcuts.lua").read_text())

    def test_custom_xdg_roots_migrate_old_home_configuration(self):
        self.old_desktop()
        self.config = self.root / "custom-config"
        self.state = self.root / "custom-state"
        self.initialize()
        self.assertIn("custom wallpaper.png", self.preferences.read_text())
        self.assertTrue((self.backup / "home-quickshell/shell.qml").is_file())
        self.assertTrue((self.backup / "home-hypr/hyprland.lua").is_file())
        self.assertTrue((self.config / "hypr/shortcuts.lua").is_file())
        self.assertFalse((self.home / ".config/quickshell").exists())

    def test_interrupted_migration_recovers_archived_monolith(self):
        self.write(self.backup / "hypr/hyprland.lua", LEGACY)
        self.initialize()
        self.assertIn("firefox --new-window", (self.config / "hypr/shortcuts.lua").read_text())

    def test_missing_image_assets_do_not_move_existing_configuration(self):
        self.old_desktop()
        self.shell_default.unlink()
        with self.assertRaises(FileNotFoundError):
            self.initialize()
        self.assertTrue((self.config / "hypr/hyprland.lua").is_file())
        self.assertTrue((self.config / "quickshell/shell.qml").is_file())

    def test_dangling_user_symlink_is_preserved(self):
        (self.config / "hypr").mkdir(parents=True)
        target = self.config / "hypr/custom.lua"
        target.symlink_to("deliberately-missing.lua")
        self.initialize()
        self.assertTrue(target.is_symlink())
        self.assertEqual("deliberately-missing.lua", os.readlink(target))

    def test_simultaneous_service_and_session_initialization_is_serialized(self):
        self.old_desktop()
        context = multiprocessing.get_context("fork")
        processes = [context.Process(target=concurrent_initialize, args=(self.home, self.config, self.state,
                     self.defaults, self.shell_default)) for _ in range(4)]
        for process in processes:
            process.start()
        for process in processes:
            process.join(timeout=10)
            self.assertEqual(0, process.exitcode)
        self.assertEqual(LEGACY, (self.backup / "hypr/hyprland.lua").read_text())
        self.assertIn("firefox --new-window", (self.config / "hypr/shortcuts.lua").read_text())
        self.assertIn("custom wallpaper.png", self.preferences.read_text())
        self.assertEqual(1, len(list(self.backup.glob("quickshell*"))))
        self.assertFalse(list(self.config.rglob(".avethyos-*")))

    def test_nested_owned_calls_are_removed_without_truncating_following_user_code(self):
        text = 'hl.on("hyprland.start", function() hl.env("A", "B") end)\nhl.bind("T", hl.dsp.exec_cmd("foot"))\n'
        self.assertEqual('hl.bind("T", hl.dsp.exec_cmd("foot"))\n', initializer.without_owned_integration(text))

    def test_relative_xdg_environment_values_use_standard_home_locations(self):
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": "relative/path"}):
            self.assertEqual(self.home / ".config", initializer.xdg_directory("XDG_CONFIG_HOME", self.home / ".config"))


if __name__ == "__main__":
    unittest.main()
