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
            "XDG_DATA_HOME": "/custom", "XDG_DATA_DIRS": "/one:/two"}),
            [Path("/custom/applications"), Path("/one/applications"), Path("/two/applications")])
        self.assertEqual(desktop_search.application_dirs({})[-2:],
                         [Path("/usr/local/share/applications"), Path("/usr/share/applications")])


if __name__ == "__main__":
    unittest.main()
