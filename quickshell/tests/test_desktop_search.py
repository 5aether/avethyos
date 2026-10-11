import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "desktop-search.py"
spec = importlib.util.spec_from_file_location("desktop_search", SCRIPT)
desktop_search = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop_search)


class DesktopSearchTests(unittest.TestCase):
    def test_indexes_custom_localized_and_action_values(self):
        values = desktop_search.field_values(
            "# ignored-comment\n[Desktop Entry]\nName=Vesktop\n"
            "Description=Discord client\nName[it]=Messaggistica\n"
            "MimeType=x-scheme-handler/discord;\nKeywords=chat;vencord;\n"
            "X-Custom=custom-value\n[Desktop Action New]\nName=New\\sWindow\n"
            "Exec=vesktop --new-window\n[Unrelated]\nKey=ignored-value\n")
        for value in ["Vesktop", "Discord client", "Messaggistica", "discord",
                      "vencord", "custom-value", "New Window", "--new-window"]:
            self.assertIn(value, values)
        self.assertNotIn("ignored", values)

    def test_user_overrides_do_not_match_system_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            user = Path(tmp) / "user"
            system = Path(tmp) / "system"
            user.mkdir()
            system.mkdir()
            (user / "vesktop.desktop").write_text("[Desktop Entry]\nName=Local client\n")
            (system / "vesktop.desktop").write_text("[Desktop Entry]\nName=System Discord\n")
            self.assertEqual(desktop_search.build_index([user, system]),
                             {"vesktop": "Local client"})

    def test_nested_ids_and_unreadable_encoding(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "vendor").mkdir()
            (directory / "vendor/client.desktop").write_text("[Desktop Entry]\nName=Client\n")
            (directory / "bad.desktop").write_bytes(b"\xff")
            self.assertEqual(desktop_search.build_index([directory]),
                             {"vendor-client": "Client"})

    def test_xdg_directories_and_defaults(self):
        self.assertEqual(desktop_search.application_dirs({
            "XDG_DATA_HOME": "/custom", "XDG_DATA_DIRS": "/one:/two"})[:3],
            [Path("/custom/applications"), Path("/one/applications"), Path("/two/applications")])
        self.assertEqual(desktop_search.application_dirs({})[1:3],
                         [Path("/usr/local/share/applications"), Path("/usr/share/applications")])
        roots = desktop_search.application_dirs({"HOME": "/home/test", "XDG_DATA_DIRS": "/one:/one"})
        self.assertIn(Path("/home/test/.local/share/flatpak/exports/share/applications"), roots)
        self.assertIn(Path("/var/lib/flatpak/exports/share/applications"), roots)
        self.assertEqual(len(roots), len(set(roots)))

    def test_snapshots_honor_hidden_overrides_and_include_localized_actions(self):
        with tempfile.TemporaryDirectory() as tmp:
            user, system = Path(tmp) / "user", Path(tmp) / "system"
            user.mkdir()
            system.mkdir()
            (system / "masked.desktop").write_text("[Desktop Entry]\nType=Application\nName=Masked\nExec=true\n")
            (user / "masked.desktop").write_text("[Desktop Entry]\nHidden=true\n")
            path = user / "test.desktop"
            path.write_text("[Desktop Entry]\nType=Application\nName=Test\nName[it]=Prova\n"
                            "Icon=/opt/test/icon.svg\nExec=test %U\nStartupWMClass=TestClass\n"
                            "Actions=New;\n[Desktop Action New]\nName=New\nName[it]=Nuova\n"
                            "Exec=test --new %c %k %%\n")
            result = desktop_search.snapshot([user, system], {"LANG": "it_IT.UTF-8"})
            self.assertEqual(["test"], [app["id"] for app in result["applications"]])
            app = result["applications"][0]
            self.assertEqual("Prova", app["name"])
            self.assertEqual("TestClass", app["startupClass"])
            self.assertEqual("Nuova", app["actions"][0]["name"])
            self.assertEqual(["test", "--new", "Prova", str(path), "%"], app["actions"][0]["command"])
            self.assertEqual(["/opt/test/icon.svg"], result["iconPaths"])

    def test_new_symlinked_exports_and_deletions_are_discovered(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "applications"
            target = Path(tmp) / "deployment"
            root.mkdir()
            target.mkdir()
            (target / "app.desktop").write_text("[Desktop Entry]\nType=Application\nName=Export\nExec=true\n")
            (root / "vendor").symlink_to(target, target_is_directory=True)
            (target / "cycle").symlink_to(root, target_is_directory=True)
            self.assertEqual(["vendor-app"], [app["id"] for app in desktop_search.snapshot([root])["applications"]])
            (target / "app.desktop").unlink()
            self.assertEqual([], desktop_search.snapshot([root])["applications"])


if __name__ == "__main__":
    unittest.main()
