import importlib.util
from pathlib import Path
import select
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/desktop-watch.py"
SPEC = importlib.util.spec_from_file_location("desktop_watch", SCRIPT)
watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watch)


class DesktopWatchTests(unittest.TestCase):
    def changed(self, watcher):
        self.assertTrue(select.select([watcher.fd], [], [], 2)[0], "filesystem event was missed")
        return watcher.read()

    def test_new_roots_and_nested_directories_remain_watched(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "new/applications"
            roots = [("applications", root)]
            watcher = watch.Watcher()
            try:
                watcher.sync(roots)
                root.mkdir(parents=True)
                changed, topology = self.changed(watcher)
                self.assertIn("applications", changed)
                self.assertTrue(topology)
                watcher.sync(roots)
                nested = root / "vendor/new"
                nested.mkdir(parents=True)
                self.assertTrue(self.changed(watcher)[1])
                watcher.sync(roots)
                (nested / "app.desktop").write_text("[Desktop Entry]\nName=Test\n")
                self.assertIn("applications", self.changed(watcher)[0])
            finally:
                watcher.close()

    def test_install_during_initial_scan_remains_watched(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            apps, icons = base / "applications", base / "icons"
            icons.mkdir()
            roots = [("applications", apps), ("icons", icons)]
            original = watch.watch_plan

            def install_during_icon_scan(roots, *args, **kwargs):
                if roots and roots[0][0] == "icons":
                    apps.mkdir()
                    (apps / "new.desktop").write_text("[Desktop Entry]\nName=New\n")
                return original(roots, *args, **kwargs)

            watcher = watch.Watcher()
            try:
                with patch.object(watch, "watch_plan", side_effect=install_during_icon_scan):
                    watcher.sync(roots)
                changed, topology = self.changed(watcher)
                self.assertIn("applications", changed)
                self.assertTrue(topology)
                watcher.sync(roots, refresh_roots=set(watcher.dirty_roots))
                watcher.read()
                (apps / "new.desktop").write_text("[Desktop Entry]\nName=Updated\n")
                self.assertIn("applications", self.changed(watcher)[0])
            finally:
                watcher.close()

    def test_atomic_root_replacements_and_symlinked_icon_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "icons"
            target = base / "deployment"
            root.mkdir()
            target.mkdir()
            (root / "scalable").symlink_to(target, target_is_directory=True)
            roots = [("icons", root)]
            watcher = watch.Watcher()
            try:
                watcher.sync(roots)
                (target / "first.svg").write_text("svg")
                self.assertIn("icons", self.changed(watcher)[0])
                root.rename(base / "old-icons")
                root.mkdir()
                self.assertTrue(self.changed(watcher)[1])
                watcher.sync(roots)
                watcher.read()
                (root / "replacement.svg").write_text("svg")
                self.assertIn("icons", self.changed(watcher)[0])
            finally:
                watcher.close()

    def test_absolute_icon_targets_and_unrelated_parent_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            icon = base / "bundle/icon.svg"
            watcher = watch.Watcher()
            try:
                watcher.sync([], [str(icon)])
                (base / "unrelated.txt").write_text("ignored")
                self.assertEqual(set(), self.changed(watcher)[0])
                icon.parent.mkdir()
                self.assertIn("icons", self.changed(watcher)[0])
                watcher.sync([], [str(icon)])
                icon.write_text("svg")
                self.assertIn("icons", self.changed(watcher)[0])
            finally:
                watcher.close()

    def test_new_icon_symlinks_watch_late_external_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root, target = base / "icons", base / "bundle/icon.svg"
            root.mkdir()
            roots = [("icons", root)]
            watcher = watch.Watcher()
            try:
                watcher.sync(roots)
                (root / "late.svg").symlink_to(target)
                changed, topology = self.changed(watcher)
                self.assertIn("icons", changed)
                self.assertTrue(topology)
                watcher.sync(roots, refresh_roots=set(watcher.dirty_roots))
                target.parent.mkdir()
                self.assertTrue(self.changed(watcher)[1])
                watcher.sync(roots, refresh_roots=set(watcher.dirty_roots))
                target.write_text("svg")
                self.assertIn("icons", self.changed(watcher)[0])
            finally:
                watcher.close()

    def test_exported_files_follow_deployment_symlink_replacements(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "applications"
            root.mkdir()
            first, second = base / "first", base / "second"
            first.mkdir()
            second.mkdir()
            for directory in [first, second]:
                (directory / "app.desktop").write_text("[Desktop Entry]\nName=Test\n")
            active = base / "active"
            active.symlink_to(first, target_is_directory=True)
            (root / "export.desktop").symlink_to(active / "app.desktop")
            roots = [("applications", root)]
            watcher = watch.Watcher()
            try:
                watcher.sync(roots)
                (first / "app.desktop").write_text("[Desktop Entry]\nName=Edited\n")
                self.assertIn("applications", self.changed(watcher)[0])
                replacement = base / "next"
                replacement.symlink_to(second, target_is_directory=True)
                replacement.replace(active)
                changed, topology = self.changed(watcher)
                self.assertIn("applications", changed)
                self.assertTrue(topology)
                watcher.sync(roots)
                watcher.read()
                (second / "app.desktop").write_text("[Desktop Entry]\nName=Updated\n")
                self.assertIn("applications", self.changed(watcher)[0])
            finally:
                watcher.close()
