#!/usr/bin/env python3
"""Cache local WebP artwork as PNG for Qt builds without a WebP plugin."""
from pathlib import Path
from urllib.parse import unquote, urlparse
import hashlib
import os
import subprocess
import sys
import tempfile


def convert(url):
    parsed = urlparse(url)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        raise ValueError("Expected local artwork")
    source = Path(unquote(parsed.path))
    stat = source.stat()
    key = hashlib.sha256(f"{source}:{stat.st_mtime_ns}:{stat.st_size}".encode()).hexdigest()
    cache = Path(tempfile.gettempdir()) / f"quickshell-media-art-{os.getuid()}"
    cache.mkdir(mode=0o700, exist_ok=True)
    output = cache / f"{key}.png"
    if not output.exists():
        fd, temporary = tempfile.mkstemp(suffix=".png", dir=cache)
        os.close(fd)
        try:
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source),
                            "-frames:v", "1", "-vf", "scale=512:512:force_original_aspect_ratio=decrease",
                            temporary], check=True, timeout=15, capture_output=True)
            os.replace(temporary, output)
        finally:
            Path(temporary).unlink(missing_ok=True)
    return output.as_uri()


if __name__ == "__main__":
    try:
        print(convert(sys.argv[1]))
    except (IndexError, ValueError, OSError, subprocess.SubprocessError):
        sys.exit(1)
