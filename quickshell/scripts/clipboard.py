#!/usr/bin/env python3
"""Capture and restore typed Wayland clipboard entries for Quickshell."""

import hashlib
import json
import mimetypes
import os
from pathlib import Path
import subprocess
import sys
import urllib.parse


IMAGE_SUFFIXES = {
    ".apng", ".avif", ".bmp", ".exr", ".gif", ".heic", ".heif",
    ".ico", ".j2k", ".jp2", ".jpeg", ".jpg", ".jxl", ".png", ".pnm",
    ".qoi", ".svg", ".tga", ".tif", ".tiff", ".webp",
}
VIDEO_SUFFIXES = {
    ".3gp", ".asf", ".avi", ".flv", ".m2ts", ".m4v", ".mkv", ".mov",
    ".mp4", ".mpeg", ".mpg", ".mts", ".ogv", ".ts", ".vob", ".webm",
    ".wmv",
}


def offered_types():
    result = subprocess.run(
        ["wl-paste", "--list-types"], capture_output=True, text=True, check=False)
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def choose_type(types):
    """Preserve copied files, then accept raw media, then ordinary text."""
    for mime in types:
        if mime.lower() == "text/uri-list":
            return mime
    for prefix in ("image/", "video/"):
        for mime in types:
            if mime.lower().startswith(prefix):
                return mime
    for wanted in ("text/plain;charset=utf-8", "text/plain"):
        for mime in types:
            if mime.lower() == wanted:
                return mime
    return next((mime for mime in types if mime.lower().startswith("text/")), "")


def uri_paths(data):
    paths = []
    for raw_line in data.decode("utf-8", "replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parsed = urllib.parse.urlparse(line)
        if parsed.scheme == "file" and parsed.netloc in ("", "localhost"):
            paths.append(Path(urllib.parse.unquote(parsed.path)))
    return paths


def probed_kind(path):
    """Classify uncommon formats with FFprobe instead of an extension list."""
    if not path.is_file():
        return ""
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "format=duration", "-of", "json", str(path)],
            capture_output=True, text=True, check=False)
        if result.returncode != 0:
            return ""
        info = json.loads(result.stdout or "{}")
        duration = info.get("format", {}).get("duration")
        return "video" if duration and float(duration) > 0 else "image"
    except (FileNotFoundError, ValueError, json.JSONDecodeError):
        return ""


def media_kind(mime, data):
    lower = mime.lower()
    if lower.startswith("image/"):
        return "image"
    if lower.startswith("video/"):
        return "video"
    if lower == "text/uri-list":
        for path in uri_paths(data):
            guessed = mimetypes.guess_type(path.name)[0] or ""
            if guessed.startswith("image/") or path.suffix.lower() in IMAGE_SUFFIXES:
                return "image"
            if guessed.startswith("video/") or path.suffix.lower() in VIDEO_SUFFIXES:
                return "video"
            detected = probed_kind(path)
            if detected:
                return detected
    return "text"


def make_preview(source, target, kind):
    positions = ("00:00:01", "00:00:00") if kind == "video" else (None,)
    for position in positions:
        command = ["ffmpeg", "-loglevel", "error", "-y"]
        if position:
            command += ["-ss", position]
        command += ["-i", str(source), "-frames:v", "1",
                    "-vf", "scale=640:360:force_original_aspect_ratio=decrease",
                    str(target)]
        try:
            result = subprocess.run(command, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, check=False)
            if result.returncode == 0 and target.exists():
                return True
        except FileNotFoundError:
            return False
    return False


def capture(directory):
    # Drain the watched offer. The MIME-specific read below preserves its type.
    sys.stdin.buffer.read()
    if os.environ.get("CLIPBOARD_STATE") == "sensitive":
        return
    mime = choose_type(offered_types())
    if not mime:
        return
    result = subprocess.run(["wl-paste", "--type", mime],
                            capture_output=True, check=False)
    if result.returncode != 0 or not result.stdout:
        return

    data = result.stdout
    kind = media_kind(mime, data)
    if kind == "text":
        text = data.decode("utf-8", "replace")
        if text.strip():
            print(json.dumps({"kind": "text", "text": text}))
        return

    root = Path(directory)
    root.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(mime.encode() + b"\0" + data).hexdigest()
    payload = root / (key + ".data")
    preview = root / (key + ".png")
    payload.write_bytes(data)

    preview_source = payload
    if mime.lower() == "text/uri-list":
        candidates = uri_paths(data)
        preview_source = next((path for path in candidates if path.is_file()), payload)
    if not make_preview(preview_source, preview, kind):
        payload.unlink(missing_ok=True)
        return
    print(json.dumps({"kind": kind, "mime": mime, "payload": str(payload),
                      "preview": str(preview),
                      "label": preview_source.name if preview_source != payload else mime}))


def restore(payload, mime):
    with open(payload, "rb") as source:
        return subprocess.run(["wl-copy", "--type", mime], stdin=source,
                              check=False).returncode


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "capture":
        capture(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "restore":
        raise SystemExit(restore(sys.argv[2], sys.argv[3]))
    else:
        raise SystemExit("usage: clipboard.py capture DIR | restore FILE MIME")


if __name__ == "__main__":
    main()
