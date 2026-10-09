#!/usr/bin/env python3

import importlib.util
import pathlib
import unittest


MODULE = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "clipboard.py"
spec = importlib.util.spec_from_file_location("clipboard", MODULE)
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)


class ClipboardTypes(unittest.TestCase):
    def test_prefers_image_payload_over_text_fallback(self):
        offered = ["text/plain;charset=utf-8", "image/webp"]
        self.assertEqual(clipboard.choose_type(offered), "image/webp")

    def test_preserves_file_list_instead_of_substitute_media(self):
        offered = ["text/uri-list", "video/x-matroska"]
        self.assertEqual(clipboard.choose_type(offered), "text/uri-list")

    def test_decodes_local_file_uris(self):
        data = b"# copied files\nfile:///tmp/a%20photo.avif\r\nhttps://example.com/x\n"
        self.assertEqual(clipboard.uri_paths(data),
                         [pathlib.Path("/tmp/a photo.avif")])

    def test_classifies_common_uri_media(self):
        self.assertEqual(clipboard.media_kind(
            "text/uri-list", b"file:///tmp/photo.avif\n"), "image")
        self.assertEqual(clipboard.media_kind(
            "text/uri-list", b"file:///tmp/movie.mkv\n"), "video")


if __name__ == "__main__":
    unittest.main()
