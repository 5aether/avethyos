#!/usr/bin/env python3
"""List a bounded wallpaper folder and cache small, static media previews.

Scanning never decodes media. The separate `thumbnails` command emits one JSON
line per preview, so QML can display the folder immediately and fill its grid
progressively. All subprocess arguments are passed directly, never via a shell.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse

IMAGE_EXTENSIONS = frozenset({
    ".jpg", ".jpeg", ".png", ".apng", ".webp", ".avif", ".gif", ".bmp", ".tif", ".tiff", ".svg", ".heic", ".heif",
})
VIDEO_EXTENSIONS = frozenset({
    ".mp4", ".m4v", ".mkv", ".webm", ".mov", ".avi", ".wmv", ".mpg", ".mpeg", ".ogv", ".flv", ".ts", ".mts",
})
CACHE_VERSION = "320-v1"


def local_path(value: str) -> Path:
    """Decode a local file URL or expand a user path without shell evaluation."""
    if value.startswith("file:"):
        parsed = urlparse(value)
        if parsed.netloc not in ("", "localhost") or parsed.query or parsed.fragment:
            raise ValueError("Choose a local folder or file")
        return Path(unquote(parsed.path)).expanduser().resolve()
    if "://" in value:
        raise ValueError("Choose a local folder or file")
    return Path(value).expanduser().resolve()


def within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def cache_directory() -> Path:
    cache = Path(tempfile.gettempdir()) / f"quickshell-wallpapers-{os.getuid()}"
    cache.mkdir(mode=0o700, exist_ok=True)
    if cache.is_symlink() or cache.stat().st_uid != os.getuid():
        raise ValueError("Wallpaper preview cache is unavailable")
    return cache


def thumbnail_path(source: Path, cache: Path) -> Path:
    stat = source.stat()
    identity = f"{CACHE_VERSION}\0{source}\0{stat.st_size}\0{stat.st_mtime_ns}"
    return cache / (hashlib.sha256(identity.encode()).hexdigest() + ".jpg")


def media_kind(path: Path) -> str:
    suffix = path.suffix.casefold()
    return "image" if suffix in IMAGE_EXTENSIONS else "video" if suffix in VIDEO_EXTENSIONS else ""


def cached_preview(source: Path, kind: str, cache: Path) -> str:
    # SVG is already a small declarative preview and is unsupported by FFmpeg.
    if source.suffix.casefold() == ".svg":
        return source.as_uri()
    thumbnail = thumbnail_path(source, cache)
    return thumbnail.as_uri() if thumbnail.is_file() and thumbnail.stat().st_size > 0 else ""


def scan(folder: str, directory: str = "", cache: Path | None = None) -> dict:
    root = local_path(folder)
    if not root.is_dir():
        raise ValueError("Wallpaper folder does not exist")
    current = local_path(directory) if directory else root
    if not within(current, root):
        raise ValueError("Folder is outside the wallpaper library")
    if not current.is_dir():
        raise ValueError("Wallpaper subfolder does not exist")
    cache = cache or cache_directory()
    entries = []
    for child in current.iterdir():
        if child.name.startswith("."):
            continue
        try:
            resolved = child.resolve(strict=True)
            if not within(resolved, root):
                continue
            if resolved.is_dir():
                entries.append({"name": child.name, "url": resolved.as_uri(), "directory": True,
                                "kind": "folder", "thumbnail": ""})
                continue
            kind = media_kind(child)
            if not kind or not resolved.is_file():
                continue
            entries.append({"name": child.name, "url": resolved.as_uri(), "directory": False,
                            "kind": kind, "thumbnail": cached_preview(resolved, kind, cache)})
        except (OSError, RuntimeError):
            # A deleted file or broken link must not hide the rest of the folder.
            continue
    entries.sort(key=lambda item: (not item["directory"], item["name"].casefold(), item["name"]))
    return {"folder": str(root), "directory": str(current), "relativeDirectory": str(current.relative_to(root)),
            "parent": "" if current == root else str(current.parent), "entries": entries, "error": ""}


def make_thumbnail(source: Path, kind: str, cache: Path | None = None) -> str:
    if not source.is_file() or kind not in ("image", "video"):
        raise ValueError("Choose an image or video wallpaper")
    cache = cache or cache_directory()
    cached = cached_preview(source, kind, cache)
    if cached:
        return cached
    output = thumbnail_path(source, cache)
    fd, temporary_name = tempfile.mkstemp(prefix="preview-", suffix=".jpg", dir=cache)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        # A representative video frame avoids the black lead-in of many clips.
        # Short clips fall back to their first frame. Limit decoder threads so
        # browsing a folder cannot saturate the desktop's CPU.
        for seek in (["1", "0"] if kind == "video" else [None]):
            command = ["ffmpeg", "-nostdin", "-v", "error", "-y", "-threads", "1", "-filter_threads", "1"]
            if seek is not None:
                command += ["-ss", seek]
            command += ["-protocol_whitelist", "file,pipe", "-i", str(source), "-frames:v", "1",
                        "-vf", "scale=320:240:force_original_aspect_ratio=decrease", "-q:v", "3", str(temporary)]
            try:
                subprocess.run(command, check=True, capture_output=True, timeout=12)
            except subprocess.CalledProcessError:
                if kind == "video" and seek == "1":
                    continue
                raise
            if temporary.stat().st_size > 0:
                os.replace(temporary, output)
                return output.as_uri()
        raise ValueError("Preview is unavailable")
    finally:
        temporary.unlink(missing_ok=True)


def preview(source_value: str, cache: Path | None = None) -> dict:
    source = local_path(source_value)
    return {"url": source.as_uri(), "thumbnail": make_thumbnail(source, media_kind(source), cache), "error": ""}


def emit(value: dict) -> None:
    print(json.dumps(value, ensure_ascii=True), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    for name in ("scan", "thumbnails"):
        command = subparsers.add_parser(name)
        command.add_argument("--folder", required=True)
        command.add_argument("--directory", default="")
    subparsers.add_parser("preview").add_argument("--source", required=True)
    args = parser.parse_args()
    # Let subprocess.run's cleanup kill FFmpeg when QML cancels a folder job.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
    try:
        if args.action == "preview":
            emit(preview(args.source))
        else:
            listing = scan(args.folder, args.directory)
            if args.action == "scan":
                emit(listing)
            else:
                for entry in listing["entries"]:
                    if entry["directory"] or entry["thumbnail"]:
                        continue
                    try:
                        emit({"url": entry["url"], "thumbnail": make_thumbnail(local_path(entry["url"]), entry["kind"]),
                              "error": ""})
                    except (ValueError, OSError, subprocess.SubprocessError):
                        emit({"url": entry["url"], "thumbnail": "", "error": "Preview unavailable"})
        return 0
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        emit({"error": str(error), "entries": [], "thumbnail": ""})
        return 1


if __name__ == "__main__":
    sys.exit(main())
