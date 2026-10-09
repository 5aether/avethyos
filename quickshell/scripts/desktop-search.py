#!/usr/bin/env python3
"""Index every desktop-entry field value using XDG desktop-file precedence."""
import json
import os
from pathlib import Path
import re


def application_dirs(environ):
    home = environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    dirs = environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [Path(directory) / "applications"
            for directory in [home, *dirs.split(":")] if directory.startswith("/")]


def field_values(contents):
    values = []
    in_entry = False
    escapes = {"s": " ", "n": "\n", "t": "\t", "r": "\r",
               "\\": "\\", ";": ";"}
    for line in contents.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_entry = line == "[Desktop Entry]" or line.startswith("[Desktop Action ")
        elif in_entry and "=" in line:
            value = line.split("=", 1)[1].strip()
            values.append(re.sub(r"\\([sntr\\;])",
                                 lambda match: escapes[match[1]], value))
    return "\n".join(values)


def build_index(directories):
    index = {}
    seen = set()
    for directory in directories:
        for path in sorted(directory.rglob("*.desktop")):
            desktop_id = str(path.relative_to(directory)).replace("/", "-")[:-8]
            if desktop_id in seen:
                continue
            # Even a hidden or unreadable user override masks the system entry.
            seen.add(desktop_id)
            try:
                index[desktop_id] = field_values(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError):
                continue
    return index


if __name__ == "__main__":
    print(json.dumps(build_index(application_dirs(os.environ)), ensure_ascii=False))
