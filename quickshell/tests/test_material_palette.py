from contextlib import ExitStack
import importlib.util
import json
import math
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "material-palette.py"
SPEC = importlib.util.spec_from_file_location("material_palette", SCRIPT)
palette = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(palette)


class AvethyPaletteTests(unittest.TestCase):
    def test_native_theme_and_qt_quick_share_the_gtk_palette(self):
        for mode, roles in palette.material_roles(palette.tonal_palette((20, 80, 140))).items():
            scheme = Path("/tmp/Avethy.colors")
            theme = json.loads(palette.qt_native_theme(roles, mode, scheme))
            self.assertEqual(roles, theme["roles"])
            self.assertEqual(str(scheme), theme["kde_scheme"])
            self.assertEqual(mode, theme["mode"])
            for group in ("Active", "Inactive"):
                colors = theme["palette"][group]
                self.assertEqual("#ff" + roles["primary"][1:], colors[12])
                self.assertEqual(colors[12], colors[21])
                self.assertEqual("#ff" + roles["on_primary"][1:], colors[13])
                self.assertEqual("#ff" + roles["surface_container_highest"][1:], colors[2])
            self.assertIn("Style=Avethy", palette.qt_quick_config())

    def test_saved_kde_gui_scheme_overrides_change_without_touching_document_colors(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            app = config / "katerc"
            app.write_text("[UiSettings]\nColorScheme=BreezeDark\n[General]\nFont=My Font\n"
                           "[KateDocumentDefaults]\nColorScheme=CodeTheme\n")
            profile = config / "Terminal.profile"
            profile.write_text("[Appearance]\nColorScheme=TerminalTheme\n")
            role = palette.material_roles(palette.tonal_palette((20, 80, 140)))["dark"]
            palette.sync_kde_app_schemes(config, role)
            result = palette.parse_ini_text(app.read_text())
            self.assertEqual(palette.SCHEME_NAME, result["UiSettings"]["ColorScheme"])
            self.assertEqual("My Font", result["General"]["Font"])
            self.assertEqual("CodeTheme", result["KateDocumentDefaults"]["ColorScheme"])
            self.assertEqual("[Appearance]\nColorScheme=TerminalTheme\n", profile.read_text())
            self.assertTrue((config / "katerc.before-material").exists())
            dolphin = palette.parse_ini_text((config / "dolphinrc").read_text())
            self.assertEqual(palette.SCHEME_NAME, dolphin["UiSettings"]["ColorScheme"])

    def test_theme_environment_reaches_widget_quick_and_activation_launches(self):
        with tempfile.TemporaryDirectory() as directory:
            plugins = Path(directory)
            (plugins / "styles").mkdir()
            (plugins / "styles/libavethy-style-qt6.so").touch()
            with patch.object(palette, "QT_PLUGIN_DIR", plugins), \
                    patch.object(palette, "QT5_PLUGIN_DIR", plugins / "missing-qt5"), \
                    patch.dict(palette.os.environ, {"QT_PLUGIN_PATH": "/existing/plugins",
                                                   "QT_QPA_GENERIC_PLUGINS": "existing-driver"}):
                environment = palette.qt_environment()
            self.assertEqual(environment["QT_QUICK_CONTROLS_STYLE"], environment["QT_STYLE_OVERRIDE"])
            self.assertEqual("Avethy", environment["QT_QUICK_CONTROLS_STYLE"])
            self.assertEqual(str(plugins) + ":/existing/plugins", environment["QT_PLUGIN_PATH"])
            self.assertEqual("avethy-theme,existing-driver", environment["QT_QPA_GENERIC_PLUGINS"])
            self.assertIn("/qml", environment["QML_IMPORT_PATH"])
            self.assertEqual(str(palette.QT_THEME_DIR / "palette.json"), environment["AVETHY_QT_THEME"])
            self.assertNotIn("QUICKSHELL_QT_THEME", environment)

    def test_nautilus_relaunch_waits_for_exit_and_is_detached_after_portals(self):
        events = []
        with patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette, "nautilus_running", side_effect=[True, True, False]), \
                patch.object(palette, "nautilus_locations", return_value=["file:///tmp/a folder"]), \
                patch.object(palette.time, "sleep"), \
                patch.object(palette.subprocess, "run", side_effect=lambda *a, **kw: events.append("quit")) as run, \
                patch.object(palette, "restart_settings_portal", side_effect=lambda: events.append("portals")), \
                patch.object(palette.subprocess, "Popen", side_effect=lambda *a, **kw: events.append("launch")) as launch:
            palette.restart_gtk_desktop()
        self.assertEqual(["quit", "portals", "launch"], events)
        self.assertEqual(["nautilus", "-q"], run.call_args.args[0])
        self.assertEqual(["nautilus", "--new-window", "--", "file:///tmp/a folder"], launch.call_args.args[0])
        options = launch.call_args.kwargs
        self.assertTrue(options["start_new_session"])
        self.assertTrue(options["close_fds"])
        for stream in ("stdin", "stdout", "stderr"):
            self.assertEqual(palette.subprocess.DEVNULL, options[stream])

    def test_closed_nautilus_stays_closed_but_portals_refresh(self):
        with patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette, "nautilus_running", return_value=False), \
                patch.object(palette, "nautilus_locations") as locations, \
                patch.object(palette.subprocess, "run") as run, \
                patch.object(palette.subprocess, "Popen") as launch, \
                patch.object(palette, "restart_settings_portal") as portals:
            palette.restart_gtk_desktop()
        locations.assert_not_called()
        run.assert_not_called()
        launch.assert_not_called()
        portals.assert_called_once()

    def test_nautilus_quit_timeout_does_not_relaunch_old_process(self):
        with patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette, "nautilus_running", return_value=True), \
                patch.object(palette, "nautilus_locations", return_value=[]), \
                patch.object(palette.time, "monotonic", side_effect=[0, 6]), \
                patch.object(palette.subprocess, "run"), \
                patch.object(palette.subprocess, "Popen") as launch, \
                patch.object(palette, "restart_settings_portal") as portals:
            palette.restart_gtk_desktop()
        launch.assert_not_called()
        portals.assert_called_once()

    def test_nautilus_folder_snapshot_handles_spaces_quotes_and_failed_dbus(self):
        locations = ["file:///tmp/a folder", "file:///tmp/it's-a-folder"]
        with patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette.subprocess, "run", return_value=Mock(
                    returncode=0, stdout=f"(<{locations!r}>,)")) as run:
            self.assertEqual(locations, palette.nautilus_locations({}))
            run.return_value = Mock(returncode=1, stdout="")
            self.assertEqual([], palette.nautilus_locations({}))

    def test_portal_broker_stops_before_backend_and_starts_after_it(self):
        with patch.dict(palette.os.environ, {}, clear=True), \
                patch.object(palette.shutil, "which", return_value="installed"), \
                patch.object(palette.subprocess, "run") as run:
            palette.restart_settings_portal()
        self.assertEqual([
            ["systemctl", "--user", "start", "hyprland-session.target"],
            ["systemctl", "--user", "stop", "xdg-desktop-portal.service"],
            ["systemctl", "--user", "stop", "xdg-desktop-portal-gtk.service"],
            ["systemctl", "--user", "start", "xdg-desktop-portal-gtk.service"],
            ["systemctl", "--user", "start", "xdg-desktop-portal.service"],
        ], [call.args[0] for call in run.call_args_list])

    @staticmethod
    def contrast(first, second):
        def luminance(value):
            rgb = [int(value[i:i+2], 16) / 255 for i in (1, 3, 5)]
            linear = [x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4
                      for x in rgb]
            return .2126*linear[0] + .7152*linear[1] + .0722*linear[2]
        a, b = sorted((luminance(first), luminance(second)), reverse=True)
        return (a + .05) / (b + .05)

    def test_roles_are_complete_and_valid(self):
        roles = palette.material_roles(palette.tonal_palette((80, 130, 220)))
        required = {
            "primary", "on_primary", "primary_container", "on_primary_container",
            "secondary", "tertiary", "error", "background", "on_background",
            "surface", "on_surface", "surface_variant", "on_surface_variant",
            "outline", "outline_variant", "inverse_surface", "inverse_primary",
            "surface_dim", "surface_bright", "surface_container_lowest",
            "surface_container_low", "surface_container", "surface_container_high",
            "surface_container_highest", "surface_tint", "primary_fixed",
            "primary_fixed_dim", "on_primary_fixed", "on_primary_fixed_variant",
            "secondary_fixed", "secondary_fixed_dim", "on_secondary_fixed",
            "on_secondary_fixed_variant", "tertiary_fixed", "tertiary_fixed_dim",
            "on_tertiary_fixed", "on_tertiary_fixed_variant", "success", "warning",
        }
        for mode in ("light", "dark"):
            self.assertTrue(required.issubset(roles[mode]))
            self.assertTrue(all(len(value) == 7 and value.startswith("#")
                                for value in roles[mode].values()))

    def test_seed_prefers_a_colorful_dominant_cluster(self):
        pixels = [(35, 35, 35)] * 200 + [(30, 90, 220)] * 150 + [(245, 245, 245)] * 20
        seed = palette.dominant_seed(pixels)
        self.assertGreater(seed[2], seed[0] + 60)

    def test_qt6ct_has_all_qpalette_roles(self):
        roles = palette.material_roles(palette.tonal_palette((180, 70, 100)))["dark"]
        output = palette.qt6ct_colors(roles)
        for key in ("active_colors", "inactive_colors", "disabled_colors"):
            line = next(line for line in output.splitlines() if line.startswith(key + "="))
            self.assertEqual(22, len(line.split("=", 1)[1].split(",")))

    def test_qt_selection_accent_and_tooltips_match_gtk_roles(self):
        for mode, roles in palette.material_roles(palette.tonal_palette((180, 70, 100))).items():
            output = palette.parse_ini_text(palette.qt6ct_colors(roles))["ColorScheme"]
            for group in ("active_colors", "inactive_colors"):
                colors = [value.strip() for value in output[group].split(",")]
                self.assertEqual("#ff" + roles["primary"][1:], colors[12], (mode, group))
                self.assertEqual(colors[12], colors[21])
                self.assertEqual("#ff" + roles["on_primary"][1:], colors[13])
                self.assertEqual("#ff" + roles["surface_container_low"][1:], colors[9])
                self.assertEqual("#ff" + roles["surface_container_high"][1:], colors[18])
                self.assertEqual("#ff" + roles["on_surface"][1:], colors[19])
            self.assertTrue(all(color.strip().startswith("#ff")
                                for line in output.values() for color in line.split(",")))
            qt5 = palette.parse_ini_text(palette.qt5ct_colors(roles))["ColorScheme"]
            self.assertTrue(all(len(line.split(",")) == 21 for line in qt5.values()))

    def test_qt_gtk_bridge_has_an_explicit_accent_and_surface_palette(self):
        for roles in palette.material_roles(palette.tonal_palette((180, 70, 100))).values():
            system = json.loads(palette.qt_gtk_bridge(roles))["QtGtk3Palettes"]["SystemPalette"]
            self.assertTrue(set(palette.QT_COLOR_ROLES) - {"NoRole"} <= system.keys())
            for group in ("Active", "Inactive"):
                color = lambda name: next(item["SourceData"]["FixedBrush"]["Color"]
                                           for item in system[name] if item["ColorGroup"] == group)
                self.assertEqual("#ff" + roles["primary"][1:], color("Accent"))
                self.assertEqual(color("Accent"), color("Highlight"))
                self.assertEqual("#ff" + roles["on_primary"][1:], color("HighlightedText"))
                self.assertEqual("#ff" + roles["background"][1:], color("Window"))
                self.assertEqual("#ff" + roles["surface_container_low"][1:], color("Base"))

    def test_persistent_compositor_theme_uses_the_generated_palette(self):
        roles = palette.material_roles(palette.tonal_palette((180, 70, 100)))["dark"]
        text = palette.hyprland_theme(roles, Path('/home/test/.config/qt6ct/gtk3-palette.json'))
        self.assertIn('hl.env("QT_GUI_GTK_JSON", "/home/test/.config/qt6ct/gtk3-palette.json")', text)
        self.assertIn(f'active_border = "rgba({roles["primary"][1:]}ff)"', text)

    def test_material_foreground_pairs_meet_text_contrast(self):
        pairs = (("primary", "on_primary"), ("primary_container", "on_primary_container"),
                 ("secondary", "on_secondary"), ("tertiary", "on_tertiary"),
                 ("error", "on_error"), ("background", "on_background"),
                 ("surface", "on_surface"), ("inverse_surface", "inverse_on_surface"),
                 ("success", "on_success"), ("warning", "on_warning"))
        for seed in ((20, 110, 220), (220, 50, 70), (40, 180, 80), (150, 70, 190),
                     (255, 255, 0), (0, 255, 255), (0, 0, 255), (128, 128, 128)):
            roles = palette.material_roles(palette.tonal_palette(seed))
            for mode in ("light", "dark"):
                for background, foreground in pairs:
                    self.assertGreaterEqual(
                        self.contrast(roles[mode][background], roles[mode][foreground]), 4.5,
                        (seed, mode, background, roles[mode][background], roles[mode][foreground]))

    def test_gamut_mapping_preserves_hue_instead_of_clipping_channels(self):
        for degrees in range(0, 360, 30):
            hue = math.radians(degrees)
            self.assertIsNone(palette.oklab_to_rgb((.60, .40*math.cos(hue), .40*math.sin(hue))))
            rgb = palette.from_oklch(.60, .40, hue)
            lightness, chroma, mapped_hue = palette.oklch(rgb)
            difference = math.atan2(math.sin(hue-mapped_hue), math.cos(hue-mapped_hue))
            self.assertLess(abs(math.degrees(difference)), 2.0, degrees)
            self.assertAlmostEqual(.60, lightness, delta=.003)
            self.assertGreater(chroma, .05)
        self.assertEqual((0, 0, 0), palette.from_oklch(0, .4, 0))
        self.assertEqual((255, 255, 255), palette.from_oklch(1, .4, 0))

    def test_requested_tones_match_actual_perceived_luminance(self):
        for seed in ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)):
            tones = palette.tonal_palette(seed)
            previous = -1
            for tone in (0, 4, 6, 10, 20, 30, 40, 50, 80, 90, 99, 100):
                color = tones[f"primary_{tone}"]
                r, g, b = (palette.srgb_to_linear(int(color[i:i+2], 16)/255) for i in (1, 3, 5))
                luminance = .2126*r + .7152*g + .0722*b
                actual = 116*luminance**(1/3)-16 if luminance > .008856 else 903.3*luminance
                self.assertAlmostEqual(tone, actual, delta=.3, msg=(seed, color, tone))
                self.assertGreater(actual, previous)
                previous = actual

    def test_achromatic_wallpapers_do_not_invent_a_saturated_accent(self):
        roles = palette.material_roles(palette.tonal_palette((128, 128, 128)))
        for mode in roles.values():
            for name in ("primary", "secondary", "tertiary", "background"):
                rgb = [int(mode[name][i:i+2], 16) for i in (1, 3, 5)]
                self.assertLessEqual(max(rgb)-min(rgb), 1, (name, mode[name]))

    def test_tiny_saturated_outlier_does_not_take_over_the_palette(self):
        pixels = [(45, 85, 145)]*700 + [(25, 28, 32)]*300 + [(255, 0, 0)]*2
        seed = palette.dominant_seed(pixels)
        self.assertGreater(seed[2], seed[0]+60)

    def test_gnome_accent_tracks_seed_hue(self):
        self.assertEqual("red", palette.nearest_gnome_accent("#d62030"))
        self.assertEqual("blue", palette.nearest_gnome_accent("#287fd8"))
        self.assertEqual("green", palette.nearest_gnome_accent("#22b967"))

    def test_gtk4_popover_keeps_shadow_layer_transparent(self):
        roles = palette.material_roles(palette.tonal_palette((40, 110, 190)))["dark"]
        css = palette.gtk_css(roles, gtk4=True)
        self.assertIn(
            "popover, popover.background { background-color: transparent; background-image: none",
            css,
        )
        self.assertIn("popover > contents { background-color:", css)
        self.assertNotIn("popover.background { background-color: " + roles["surface_container_high"], css)
        self.assertNotIn("window.background, .background", css)

    def test_gtk3_controls_do_not_keep_theme_background_images(self):
        roles = palette.material_roles(palette.tonal_palette((40, 110, 190)))["dark"]
        css = palette.gtk_css(roles, gtk4=False)
        self.assertIn("button, combobox button, spinbutton button { background-image: none; }", css)
        self.assertNotIn("combobox button, spinbutton button { background-image: none; }",
                         palette.gtk_css(roles, gtk4=True))

    def test_public_theme_names_match_across_toolkits(self):
        self.assertEqual("Avethy", palette.SCHEME_NAME)
        self.assertEqual("Avethy", palette.QT_STYLE_NAME)
        self.assertEqual("Avethy", palette.QT_QUICK_STYLE_NAME)
        self.assertEqual("Avethy", palette.gtk_theme_name("light"))
        self.assertEqual("Avethy-dark", palette.gtk_theme_name("dark"))
        self.assertEqual(palette.HOME / ".cache/avethy/palette.ini", palette.PALETTE_FILE)
        self.assertEqual(palette.CONFIG_HOME / "avethy", palette.QT_THEME_DIR)
        self.assertEqual(palette.ROOT / "native/qt-theme/build-qt6/plugins", palette.QT_PLUGIN_DIR)
        self.assertEqual(palette.ROOT / "native/qt-theme/qml", palette.QT_QML_DIR)

    def test_gtk2_context_menu_states_match_the_bar_and_modern_popups(self):
        for seed in ((20, 80, 140), (220, 50, 70), (40, 180, 80)):
            for mode, roles in palette.material_roles(palette.tonal_palette(seed)).items():
                with self.subTest(seed=seed, mode=mode):
                    rc = palette.gtk2_rc(roles)
                    self.assertIn(f'gtk-theme-name = "{palette.gtk_theme_name(mode)}"', rc)
                    styles = re.findall(r'style "([^"]+)"(?: = "([^"]+)")? \{([^}]*)\}', rc, re.S)
                    binding = re.search(r'widget_class "\*Menu\*" style "([^"]+)"', rc)
                    self.assertIsNotNone(binding, "Menu palette must be scoped to menu class paths")
                    menus = [style for style in styles if style[0] == binding[1]]
                    self.assertEqual(1, len(menus), "Scoped menu style must be declared once")
                    name, parent, declarations = menus[0]
                    self.assertTrue(parent, "Menu style must inherit the global palette")
                    self.assertTrue(any(style[0] == parent for style in styles))
                    self.assertIn(f'widget_class "*Menu*" style "{name}"', rc)
                    values = {(kind, state): color for kind, state, color in re.findall(
                        r'(bg|fg|base|text)\[([A-Z]+)\] = "(#[0-9a-fA-F]{6})"', declarations)}
                    self.assertEqual(20, len(values), "All four legacy color roles need all five states")
                    muted = palette.blend_color(roles["on_surface"], roles["surface_container_high"], .55)
                    for state in ("NORMAL", "PRELIGHT", "ACTIVE", "SELECTED", "INSENSITIVE"):
                        selected = state in ("PRELIGHT", "ACTIVE", "SELECTED")
                        background = roles["primary" if selected else "surface_container_high"]
                        foreground = muted if state == "INSENSITIVE" else roles[
                            "on_primary" if selected else "on_surface"]
                        for kind in ("bg", "base"):
                            self.assertEqual(background, values[kind, state], (state, kind))
                        for kind in ("fg", "text"):
                            self.assertEqual(foreground, values[kind, state], (state, kind))
                    self.assertIn(f'menu_bg_color:{roles["surface_container_high"]}', rc)
                    self.assertIn(f'menu_fg_color:{roles["on_surface"]}', rc)
                    self.assertIn(f'selected_bg_color:{roles["primary"]}', rc)
                    self.assertIn(f'selected_fg_color:{roles["on_primary"]}', rc)

    def test_flatpak_gtk2_uses_its_generated_rc_instead_of_the_host_rc(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            app = home / ".var/app/org.example.Legacy"
            bridge = app / "config/qt6ct/gtk3-palette.json"
            bridge.parent.mkdir(parents=True)
            bridge.write_text("{}")
            plugins = home / ".local/lib/avethy/qt-plugins"
            (plugins / "styles").mkdir(parents=True)
            (plugins / "styles/libavethy-style-qt6.so").touch()
            (app / "config/avethy/qt-plugins").mkdir(parents=True)
            for mode in ("dark", "light"):
                with self.subTest(mode=mode), \
                        patch.object(palette, "HOME", home), patch.object(palette, "CONFIG_HOME", home / ".config"), \
                        patch.object(palette, "QT_PLUGIN_DIR", plugins), \
                        patch.dict(palette.os.environ, {}, clear=True), \
                        patch.object(palette, "current_mode", side_effect=lambda requested: requested or (
                            "light" if mode == "dark" else "dark")), \
                        patch.object(palette.shutil, "which", return_value="installed"), \
                        patch.object(palette.subprocess, "run") as run:
                    palette.sync_flatpak_theme(mode)
                assignments = run.call_args_list[-1].args[0]
                self.assertIn(f"--env=GTK2_RC_FILES={app}/config/gtk-2.0/gtkrc", assignments)
                self.assertIn(f"--env=GTK_THEME={palette.gtk_theme_name(mode)}", assignments)

    def test_gtk_sidebar_and_unfocused_selection_use_the_bar_accent(self):
        for roles in palette.material_roles(palette.tonal_palette((220, 50, 70))).values():
            for gtk4 in (False, True):
                css = palette.gtk_css(roles, gtk4)
                self.assertIn(f"@define-color theme_unfocused_selected_bg_color {roles['primary']};", css)
                self.assertIn(f"@define-color theme_unfocused_selected_fg_color {roles['on_primary']};", css)
                start = css.index("\nselection,\n")
                selected = css[start:]
                for selector in ("placessidebar row:selected", ".navigation-sidebar row:selected",
                                 "stacksidebar row:selected", "row:selected:backdrop"):
                    self.assertIn(selector, selected)
                self.assertIn(f"background-color: {roles['primary']}; background-image: none;", selected)
                self.assertIn(f"color: {roles['on_primary']};", selected)
                self.assertNotIn(roles["primary_container"], selected)
            rc = palette.gtk2_rc(roles)
            self.assertIn(f'base[SELECTED] = "{roles["primary"]}"', rc)
            self.assertIn(f'text[SELECTED] = "{roles["on_primary"]}"', rc)

    def test_gtk4_sets_modern_colors_and_background_transparency(self):
        for mode, roles in palette.material_roles(palette.tonal_palette((220, 50, 70))).items():
            css = palette.gtk_css(roles, gtk4=True)
            self.assertIn(f"--accent-bg-color: {roles['primary']};", css)
            self.assertIn(f"--accent-fg-color: {roles['on_primary']};", css)
            self.assertIn("window, window.background { background-color: rgba(", css)
            self.assertIn("popover > contents { background-color: rgba(", css)
            self.assertIn(".nautilus-properties headerbar { background-color: transparent;", css)
            self.assertNotIn("opacity: 0.62", css)
            # Text remains readable even over the worst black/white backdrop.
            for underneath in ("#000000", "#ffffff"):
                composite = palette.blend_color(roles["background"], underneath, .88 if mode == "dark" else .94)
                self.assertGreaterEqual(self.contrast(composite, roles["on_surface"]), 4.5)

    def test_preview_does_not_apply_or_write_the_live_palette(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            with patch.object(palette, "apply") as apply, patch.object(palette, "write_palette") as write:
                roles = palette.generate("", "dark", preview_dir=target)
            apply.assert_not_called()
            write.assert_not_called()
            self.assertTrue((target / "palette.ini").exists())
            for mode in roles:
                self.assertTrue((target / mode / "gtk-3.0/gtk.css").exists())
                self.assertTrue((target / mode / "gtk-4.0/gtk.css").exists())
                self.assertTrue((target / mode / "qt5ct.conf").exists())
                self.assertTrue((target / mode / "qt6ct.conf").exists())
                self.assertTrue((target / mode / "gtk3-palette.json").exists())
                self.assertTrue((target / mode / "Avethy.colors").exists())
                theme = json.loads((target / mode / "desktop-theme.json").read_text())
                self.assertEqual(str(target / mode / "Avethy.colors"), theme["kde_scheme"])

    def test_kcolorscheme_contains_every_standard_color_set(self):
        roles = palette.material_roles(palette.tonal_palette((190, 55, 115)))["dark"]
        sections = palette.parse_ini_text(palette.kde_colors(roles))
        self.assertEqual("Avethy", sections["General"]["Name"])
        self.assertEqual("Avethy", sections["General"]["ColorScheme"])
        required = {
            "ColorEffects:Disabled", "ColorEffects:Inactive", "Colors:Button",
            "Colors:Complementary", "Colors:Header", "Colors:Header][Inactive",
            "Colors:Selection", "Colors:Tooltip", "Colors:View", "Colors:Window",
            "General", "KDE", "WM",
        }
        self.assertTrue(required.issubset(sections))
        color_keys = {
            "BackgroundAlternate", "BackgroundNormal", "DecorationFocus", "DecorationHover",
            "ForegroundActive", "ForegroundInactive", "ForegroundLink", "ForegroundNegative",
            "ForegroundNeutral", "ForegroundNormal", "ForegroundPositive", "ForegroundVisited",
        }
        for section in required:
            if section.startswith("Colors:"):
                self.assertTrue(color_keys.issubset(sections[section]), section)


class DesktopIconThemeTests(unittest.TestCase):
    def setUp(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        self.home = Path(stack.enter_context(tempfile.TemporaryDirectory()))
        self.root = self.home / "shell"
        self.root.mkdir()
        self.config = self.home / ".local/state/avethyos/quickshell/config.ini"
        self.config.parent.mkdir(parents=True)
        self.config.write_text("[appearance]\nicon-pack = Papirus\n")
        self.roles = palette.material_roles(palette.tonal_palette((20, 80, 140)))
        for key, value in (("HOME", self.home), ("ROOT", self.root),
                           ("CONFIG_HOME", self.home / ".config"),
                           ("SHELL_CONFIG", self.config),
                           ("QT_THEME_DIR", self.home / ".config/avethy"),
                           ("QT_PLUGIN_DIR", self.root / "native/qt-theme/build-qt6/plugins"),
                           ("QT5_PLUGIN_DIR", self.root / "native/qt-theme/build-qt5/plugins"),
                           ("QT_QML_DIR", self.root / "native/qt-theme/qml")):
            stack.enter_context(patch.object(palette, key, value))
        self.run = stack.enter_context(patch.object(palette.subprocess, "run", return_value=Mock(returncode=0)))
        self.query = stack.enter_context(patch.object(palette.subprocess, "check_output", return_value="'Desktop-Pack'\n"))
        stack.enter_context(patch.object(palette.shutil, "which", side_effect=lambda name: "/bin/" + name))
        stack.enter_context(patch.object(palette.time, "sleep"))
        stack.enter_context(patch.object(palette, "install_gtk_theme"))

    def test_homebrew_tool_uses_native_gtk_backend_and_other_path_overrides_survive(self):
        with patch.object(palette.shutil, "which", return_value="/home/linuxbrew/.linuxbrew/bin/gsettings"), \
                patch.object(Path, "is_file", return_value=True):
            self.assertEqual("/usr/bin/gsettings", palette.gsettings_command())
        with patch.object(palette.shutil, "which", return_value="/test-bin/gsettings"):
            self.assertEqual("gsettings", palette.gsettings_command())

    def test_full_palette_preserves_exact_pack_in_both_modes_and_flatpaks(self):
        app = self.home / ".var/app/org.example.App/config"
        app.mkdir(parents=True)
        for mode in ("dark", "light"):
            with self.subTest(mode=mode):
                role = self.roles[mode]
                palette.install_gtk(role, mode)
                palette.install_qt(role, mode)
                palette.install_flatpak_configs(role, mode)
                palette.set_gsettings(mode, role)
                palette.sync_flatpak_theme(mode)
                for directory in (self.home / ".config", app):
                    for version in ("gtk-3.0", "gtk-4.0"):
                        settings = palette.parse_ini_text((directory / version / "settings.ini").read_text())
                        self.assertEqual("Papirus", settings["Settings"]["gtk-icon-theme-name"])
                    kde = palette.parse_ini_text((directory / "kdeglobals").read_text())
                    self.assertEqual("Papirus", kde["Icons"]["Theme"])
                    for toolkit in ("qt5ct", "qt6ct"):
                        compat = palette.parse_ini_text((directory / toolkit / f"{toolkit}.conf").read_text())
                        self.assertEqual("Papirus", compat["Appearance"]["icon_theme"])
                self.assertIn('gtk-icon-theme-name = "Papirus"', (self.home / ".gtkrc-2.0").read_text())
                commands = [call.args[0] for call in self.run.call_args_list]
                self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "Papirus"], commands)
                self.assertTrue(any("--env=ICON_THEME=Papirus" in command for command in commands))
                self.run.reset_mock()

    def test_empty_pack_follows_existing_desktop_instead_of_switching_with_mode(self):
        self.config.write_text("[appearance]\nicon-pack =\n")
        gtk = self.home / ".config/gtk-3.0/settings.ini"
        gtk.parent.mkdir(parents=True)
        gtk.write_text("[Settings]\ngtk-icon-theme-name = My-Existing-Pack\n")
        for mode in ("dark", "light"):
            self.assertEqual("My-Existing-Pack", palette.desktop_icon_theme(mode))
        gtk.unlink()
        self.assertEqual("Desktop-Pack", palette.desktop_icon_theme("dark"))

    def test_icons_only_preserves_palette_and_unrelated_toolkit_settings(self):
        directory = self.home / ".config"
        gtk = directory / "gtk-3.0"
        gtk.mkdir(parents=True)
        (gtk / "settings.ini").write_text("[Settings]\ngtk-theme-name=My-Theme\ngtk-font-name=My Font 11\n"
                                          "gtk-icon-theme-name=Old-Pack\n[Other]\nkey=value\n")
        (gtk / "gtk.css").write_text("/* unchanged CSS */")
        theme = directory / "avethy/palette.json"
        theme.parent.mkdir()
        theme.write_text('{"keep": "this palette"}\n')
        rc = self.home / ".gtkrc-2.0"
        rc.write_text('gtk-font-name = "My Font 11"\ngtk-icon-theme-name = "Old-Pack"\n')
        (directory / "kdeglobals").write_text("[General]\nColorScheme=My-Colors\n[Icons]\nTheme=Old-Pack\n")
        palette.apply_icon_theme("dark")
        settings = palette.parse_ini_text((gtk / "settings.ini").read_text())
        self.assertEqual("Papirus", settings["Settings"]["gtk-icon-theme-name"])
        self.assertEqual("My-Theme", settings["Settings"]["gtk-theme-name"])
        self.assertEqual("My Font 11", settings["Settings"]["gtk-font-name"])
        self.assertEqual("value", settings["Other"]["key"])
        self.assertEqual("/* unchanged CSS */", (gtk / "gtk.css").read_text())
        self.assertEqual('{"keep": "this palette"}\n', theme.read_text())
        self.assertIn('gtk-font-name = "My Font 11"', rc.read_text())
        self.assertIn('gtk-icon-theme-name = "Papirus"', rc.read_text())
        kde = palette.parse_ini_text((directory / "kdeglobals").read_text())
        self.assertEqual("My-Colors", kde["General"]["ColorScheme"])
        self.assertEqual("Papirus", kde["Icons"]["Theme"])
        self.assertFalse((directory / "qt6ct").exists(), "Icon sync must work without qt6ct")
        commands = [call.args[0] for call in self.run.call_args_list]
        self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "Papirus"], commands)
        self.assertFalse(any("reload" in command or "restart" in command for command in commands))
        notifications = [command for command in commands if command[0] == "dbus-send"]
        self.assertEqual(1, len(notifications))
        self.assertIn("int32:4", notifications[0])

    def test_alternate_config_and_pack_names_are_passed_as_literal_arguments(self):
        alternate = self.root / "alternate.ini"
        selected = "Custom-Pack;$(touch should-not-exist)%"
        alternate.write_text("[appearance]\nicon-pack = " + selected + "\n")
        palette.apply_icon_theme("dark", alternate)
        self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", selected],
                      [call.args[0] for call in self.run.call_args_list])
        self.assertFalse((self.home / "should-not-exist").exists())


if __name__ == "__main__":
    unittest.main()
