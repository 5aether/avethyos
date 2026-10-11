#!/usr/bin/env python3
"""Resolve freedesktop icons and list installed icon packs by their exact names."""

import argparse
import configparser
import json
import os
from pathlib import Path
import sys


def icon_roots(include_missing=False):
    local_share = Path.home() / ".local/share"
    data_home = Path(os.environ.get("XDG_DATA_HOME") or local_share)
    data_dirs = [Path(item) for item in
                 (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
                 if item]
    roots = [Path.home() / ".icons", data_home / "icons", local_share / "icons"]
    roots.extend(directory / "icons" for directory in data_dirs)
    roots.extend([Path("/usr/local/share/icons"), Path("/usr/share/icons")])

    # Sandboxed Quickshell packages expose the host's icon themes under
    # /run/host. Flatpak applications publish their icons in export trees,
    # which are not guaranteed to be present in XDG_DATA_DIRS.
    roots.extend([
        data_home / "flatpak/exports/share/icons",
        local_share / "flatpak/exports/share/icons",
        Path("/var/lib/flatpak/exports/share/icons"),
        Path("/run/host/user-share/icons"),
        Path("/run/host/share/icons"),
        Path("/run/host/usr/share/icons"),
        Path("/run/host/usr/local/share/icons"),
    ])
    result = []
    for root in roots:
        if root not in result and (include_missing or root.is_dir()):
            result.append(root)
    return result


def installed_themes(roots=None):
    """Group installations by directory name, never by the display Name key."""
    roots = icon_roots() if roots is None else list(roots)
    themes = set()
    for root in roots:
        try:
            directories = sorted(root.iterdir())
        except OSError:
            continue
        for directory in directories:
            if not directory.is_dir():
                continue
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                parser.read(directory / "index.theme", encoding="utf-8")
                if not parser.has_section("Icon Theme"):
                    continue
            except (configparser.Error, OSError, UnicodeError):
                continue
            themes.add(directory.name)
    # A user directory may extend a system theme without its own index.theme.
    return [{"name": name, "paths": [str(path) for path in find_themes(name, roots)]}
            for name in sorted(themes, key=lambda value: (value.casefold(), value))]


def pixmap_roots(include_missing=False):
    roots = [root.with_name("pixmaps") for root in icon_roots(include_missing=True) if root.name == "icons"]
    return [root for root in roots if include_missing or root.is_dir()]


def root_watches():
    """Watch existing ancestors too, so newly created icon roots are discovered."""
    watches = []
    for root in icon_roots(include_missing=True):
        parent = root.parent
        while not parent.is_dir() and parent != parent.parent:
            parent = parent.parent
        watches.append({"path": str(root), "parent": str(parent), "exists": root.is_dir()})
    return watches


def configured_theme(config):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(config, encoding="utf-8")
        return parser.get("appearance", "icon-pack", fallback="").strip()
    except (configparser.Error, OSError, UnicodeError):
        return ""


def format_themes(themes):
    if not themes:
        return "No installed icon packs found."
    lines = ["Exact names for [appearance] icon-pack:"]
    for theme in themes:
        lines.append(theme["name"])
        lines.extend("  " + path for path in theme["paths"])
    return "\n".join(lines)


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
    except (configparser.Error, OSError, UnicodeError):
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
                    if path.suffix.lower() not in {".png", ".svg", ".xpm"} or not path.is_file():
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
    # Applications also install unthemed icons directly in icons/ or pixmaps/.
    # These come after the selected pack, its parents and hicolor.
    for root in [*roots, *pixmap_roots()]:
        try:
            for path in sorted(root.iterdir()):
                if path.suffix.lower() not in {".png", ".svg", ".xpm"} or not path.is_file():
                    continue
                icons.setdefault(path.stem, str(path.resolve()))
                icons.setdefault(path.stem.lower(), icons[path.stem])
        except OSError:
            continue
    return icons


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("theme", nargs="?", default="hicolor")
    parser.add_argument("resolver_version", nargs="?")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--list", action="store_true", help="list exact icon-pack names and paths")
    actions.add_argument("--roots", action="store_true", help="print icon search roots as JSON")
    actions.add_argument("--watch-roots", action="store_true", help="print icon roots and existing ancestors as JSON")
    actions.add_argument("--config", type=Path, help="print the icon-pack override from a config.ini")
    args = parser.parse_args()
    if args.config is not None:
        print(configured_theme(args.config))
    elif args.list:
        print(format_themes(installed_themes()))
    else:
        if args.watch_roots:
            result = root_watches()
        elif args.roots:
            result = [str(path) for path in icon_roots(include_missing=True)]
        else:
            result = build(args.theme)
        json.dump(result, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
