#!/usr/bin/env python3
"""Build an icon-name to file-path map for a freedesktop icon theme."""

import configparser
import json
import os
from pathlib import Path
import sys


def icon_roots():
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data_dirs = [Path(item) for item in
                 os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
                 if item]
    roots = [Path.home() / ".icons", data_home / "icons"]
    roots.extend(directory / "icons" for directory in data_dirs)

    # Sandboxed Quickshell packages expose the host's icon themes under
    # /run/host. Flatpak applications publish their icons in export trees,
    # which are not guaranteed to be present in XDG_DATA_DIRS.
    roots.extend([
        data_home / "flatpak/exports/share/icons",
        Path("/var/lib/flatpak/exports/share/icons"),
        Path("/run/host/user-share/icons"),
        Path("/run/host/share/icons"),
        Path("/run/host/usr/share/icons"),
    ])
    result = []
    for root in roots:
        if root not in result and root.is_dir():
            result.append(root)
    return result


def find_themes(name, roots):
    """Return every installation of a theme in lookup-priority order."""
    return [root / name for root in roots if (root / name).is_dir()]


def inherited_names(theme_dir):
    index = theme_dir / "index.theme"
    if not index.is_file():
        return []
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(index, encoding="utf-8")
        value = parser.get("Icon Theme", "Inherits", fallback="")
        return [item.strip() for item in value.split(",") if item.strip()]
    except (configparser.Error, OSError):
        return []


def theme_chain(name, roots):
    result = []
    visiting = set()

    def add(theme_name):
        if not theme_name or theme_name in visiting:
            return
        visiting.add(theme_name)
        directories = find_themes(theme_name, roots)
        for directory in directories:
            result.append(directory)
        for directory in directories:
            for inherited in inherited_names(directory):
                add(inherited)

    add(name)
    add("hicolor")
    return result


def preference(path):
    parts = [part.lower() for part in path.parts]
    suffix = path.suffix.lower()
    scalable = "scalable" in parts or suffix == ".svg"
    symbolic = path.stem.endswith("-symbolic")
    application = "apps" in parts or "applications" in parts
    sizes = []
    for part in parts:
        if "x" in part:
            try:
                sizes.append(int(part.split("x", 1)[0]))
            except ValueError:
                pass
    size = min(sizes, key=lambda value: abs(value - 48)) if sizes else 0
    # This resolver primarily serves application and notification icons. Keep
    # a full-colour icon from an apps directory ahead of a same-named symbolic
    # or category icon; within that choice, scalable images remain preferred.
    return (0 if application else 1, 1 if symbolic else 0,
            0 if scalable else 1, abs(size - 48), -size)


def build(theme_name):
    roots = icon_roots()
    icons = {}
    for theme in theme_chain(theme_name, roots):
        candidates = {}
        try:
            # Papirus-Dark and similar variants expose their icon-size folders
            # as symlinks into the base theme. pathlib.rglob intentionally does
            # not descend through those, so use a loop-safe following walk.
            visited = set()
            for directory, child_dirs, filenames in os.walk(theme, followlinks=True):
                real_directory = os.path.realpath(directory)
                if real_directory in visited:
                    child_dirs[:] = []
                    continue
                visited.add(real_directory)
                child_dirs[:] = [child for child in child_dirs
                                  if os.path.realpath(os.path.join(directory, child)) not in visited]
                for filename in filenames:
                    path = Path(directory) / filename
                    if path.suffix.lower() not in {".png", ".svg", ".xpm"}:
                        continue
                    name = path.stem
                    if name in icons:
                        continue
                    current = candidates.get(name)
                    if current is None or preference(path) < preference(current):
                        candidates[name] = path
        except OSError:
            continue
        for name, path in candidates.items():
            resolved = str(path.resolve())
            icons[name] = resolved
            # Preserve the theme's exact key while also accepting desktop
            # entries whose Icon value differs only in letter casing.
            icons.setdefault(name.lower(), resolved)
    return icons


if __name__ == "__main__":
    theme = sys.argv[1] if len(sys.argv) > 1 else "hicolor"
    json.dump(build(theme), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
