#!/usr/bin/env python3
"""Folder bounds, URL handling and thumbnail cache behavior."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parent.parent / "scripts" / "wallpaper-library.py"
SPEC = importlib.util.spec_from_file_location("wallpaper_library", MODULE)
library = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(library)


class WallpaperLibrary(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wallpaper-library-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "Wallpapers #1"
        self.root.mkdir()
        self.cache = self.base / "cache"
        self.cache.mkdir()

    def media(self, name, content=b"wallpaper"):
        path = self.root / name
        path.write_bytes(content)
        return path

    def scan(self, directory=""):
        return library.scan(str(self.root), directory, self.cache)

    def test_scan_lists_media_and_folders_without_decoding(self):
        self.media("z.JPG")
        self.media("a.webm")
        self.media("notes.txt")
        self.media(".hidden.mp4")
        (self.root / "Scenes").mkdir()
        with patch.object(library.subprocess, "run") as run:
            result = self.scan()
        self.assertEqual([entry["name"] for entry in result["entries"]], ["Scenes", "a.webm", "z.JPG"])
        self.assertEqual([entry["kind"] for entry in result["entries"]], ["folder", "video", "image"])
        self.assertEqual(result["relativeDirectory"], ".")
        self.assertEqual(result["parent"], "")
        run.assert_not_called()

    def test_file_urls_and_hostile_filenames_round_trip(self):
        name = 'cat #1 % " $(touch never) `echo nope`\n雪.mp4'
        path = self.media(name)
        result = library.scan(self.root.as_uri(), cache=self.cache)
        entry = result["entries"][0]
        self.assertEqual(entry["name"], name)
        self.assertEqual(library.local_path(entry["url"]), path)
        self.assertIn("%23", entry["url"])
        self.assertIn("%0A", entry["url"])
        self.assertEqual(library.local_path(path.as_uri().replace("file://", "file://localhost")), path)

    def test_tilde_expansion_and_remote_url_rejection(self):
        with patch.dict(os.environ, {"HOME": str(self.base)}):
            self.assertEqual(library.local_path("~/Wallpapers #1"), self.root)
        for value in ("https://example.org/wallpaper.jpg", "file://remote/tmp/folder", "file:///tmp/folder?query"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                library.local_path(value)

    def test_subfolder_navigation_stays_within_root(self):
        child = self.root / "Scenes"
        child.mkdir()
        result = self.scan(child.as_uri())
        self.assertEqual(result["directory"], str(child))
        self.assertEqual(result["parent"], str(self.root))
        self.assertEqual(result["relativeDirectory"], "Scenes")
        for outside in (self.base, self.root / "..", self.base / "Wallpapers #10"):
            with self.subTest(outside=outside), self.assertRaises(ValueError):
                self.scan(str(outside))

    def test_symlinks_cannot_escape_library_or_loop(self):
        outside = self.base / "outside.mp4"
        outside.write_bytes(b"video")
        (self.root / "escape.mp4").symlink_to(outside)
        (self.root / "escape-folder").symlink_to(self.base, target_is_directory=True)
        (self.root / "loop.mp4").symlink_to(self.root / "loop.mp4")
        inside = self.media("inside.png")
        (self.root / "alias.png").symlink_to(inside)
        result = self.scan()
        self.assertEqual([item["name"] for item in result["entries"]], ["alias.png", "inside.png"])
        self.assertTrue(all(library.within(library.local_path(item["url"]), self.root) for item in result["entries"]))
        with self.assertRaises(ValueError):
            self.scan(str(self.root / "escape-folder"))

    def test_missing_root_has_clear_error(self):
        with self.assertRaisesRegex(ValueError, "does not exist"):
            library.scan(str(self.base / "missing"), cache=self.cache)

    def test_cache_key_changes_when_file_changes(self):
        path = self.media("scene.mp4")
        first = library.thumbnail_path(path, self.cache)
        path.write_bytes(b"new wallpaper content")
        second = library.thumbnail_path(path, self.cache)
        self.assertNotEqual(first, second)
        self.assertEqual(second.parent, self.cache)

    def test_generation_passes_filename_as_one_argument_and_reuses_cache(self):
        path = self.media('space $() `cmd` " #.mp4')

        def decode(command, **kwargs):
            self.assertEqual(command[command.index("-i") + 1], str(path))
            self.assertNotIn("shell", kwargs)
            Path(command[-1]).write_bytes(b"small JPEG preview")
            return subprocess.CompletedProcess(command, 0)

        with patch.object(library.subprocess, "run", side_effect=decode) as run:
            first = library.make_thumbnail(path, "video", self.cache)
            second = library.make_thumbnail(path, "video", self.cache)
        self.assertEqual(first, second)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(library.local_path(first).parent, self.cache)
        self.assertFalse(list(self.cache.glob("preview-*")))
        self.assertEqual(self.scan()["entries"][0]["thumbnail"], first)

    def test_failed_decoder_cleans_temporary_file(self):
        path = self.media("broken.png")
        with patch.object(library.subprocess, "run", side_effect=subprocess.TimeoutExpired("ffmpeg", 12)):
            with self.assertRaises(subprocess.TimeoutExpired):
                library.make_thumbnail(path, "image", self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_short_video_falls_back_to_first_frame(self):
        path = self.media("short.mp4")
        seeks = []

        def decode(command, **kwargs):
            seek = command[command.index("-ss") + 1]
            seeks.append(seek)
            if seek == "1":
                raise subprocess.CalledProcessError(234, command)
            if seek == "0":
                Path(command[-1]).write_bytes(b"frame")
            return subprocess.CompletedProcess(command, 0)

        with patch.object(library.subprocess, "run", side_effect=decode):
            result = library.make_thumbnail(path, "video", self.cache)
        self.assertEqual(seeks, ["1", "0"])
        self.assertTrue(library.local_path(result).is_file())


if __name__ == "__main__":
    unittest.main()
