#!/usr/bin/env python3
"""Discover launcher applications and searchable metadata from desktop files."""
import argparse
import configparser
import json
import os
from pathlib import Path
import re
import shlex
from urllib.parse import unquote, urlparse


def application_dirs(environ):
    local_share = Path(environ.get("HOME") or Path.home()) / ".local/share"
    home = environ.get("XDG_DATA_HOME") or str(local_share)
    dirs = environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    roots = [home, *dirs.split(":"), str(local_share), "/usr/local/share", "/usr/share",
             str(Path(home) / "flatpak/exports/share"), str(local_share / "flatpak/exports/share"),
             "/var/lib/flatpak/exports/share", "/run/host/user-share", "/run/host/share",
             "/run/host/usr/local/share", "/run/host/usr/share"]
    return list(dict.fromkeys(Path(directory) / "applications"
                             for directory in roots if directory.startswith("/")))


def desktop_files(directory):
    visited = set()
    for parent, children, filenames in os.walk(directory, followlinks=True):
        real = os.path.realpath(parent)
        if real in visited:
            children[:] = []
            continue
        visited.add(real)
        children.sort()
        for filename in sorted(filenames):
            if filename.endswith(".desktop"):
                yield Path(parent) / filename


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
        for path in desktop_files(directory):
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


def unescape(value):
    escapes = {"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\", ";": ";"}
    return re.sub(r"\\([sntr\\;])", lambda match: escapes[match[1]], value)


def localized(section, key, environ):
    locale = environ.get("LC_ALL") or environ.get("LC_MESSAGES") or environ.get("LANG") or ""
    base, _, modifier = locale.partition("@")
    base = base.split(".", 1)[0]
    locale = base + ("@" + modifier if modifier else "")
    language = base.split("_", 1)[0]
    variants = [locale, base, language + "@" + modifier if modifier else language, language]
    for variant in dict.fromkeys(variants):
        if variant and key + "[" + variant + "]" in section:
            return unescape(section[key + "[" + variant + "]"])
    return unescape(section.get(key, ""))


def exec_command(value, name, icon, desktop_file):
    try:
        words = shlex.split(value)
    except ValueError:
        return []
    result = []
    for word in words:
        if word == "%i":
            if icon:
                result.extend(["--icon", icon])
            continue
        expanded = re.sub(r"%([%a-zA-Z])", lambda match: {
            "%": "%", "c": name, "k": str(desktop_file)
        }.get(match[1], ""), word)
        if expanded:
            result.append(expanded)
    return result


def application(contents, desktop_id, path, environ):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read_string(contents)
    except configparser.Error:
        return None
    if not parser.has_section("Desktop Entry"):
        return None
    entry = parser["Desktop Entry"]
    name = localized(entry, "Name", environ)
    if entry.get("Type") != "Application" or not name:
        return None
    if any(entry.get(key, "").lower() == "true" for key in ["Hidden", "NoDisplay"]):
        return None
    icon = unescape(entry.get("Icon", ""))
    command = entry.get("Exec", "")
    result = {"id": desktop_id, "desktopFile": str(path), "name": name,
              "genericName": localized(entry, "GenericName", environ),
              "comment": localized(entry, "Comment", environ), "icon": icon,
              "execString": command, "command": exec_command(command, name, icon, path),
              "workingDirectory": unescape(entry.get("Path", "")),
              "runInTerminal": entry.get("Terminal", "").lower() == "true",
              "startupClass": entry.get("StartupWMClass", ""),
              "categories": entry.get("Categories", "").split(";"),
              "keywords": localized(entry, "Keywords", environ).split(";"), "actions": []}
    for action_id in entry.get("Actions", "").split(";"):
        section = "Desktop Action " + action_id
        if not action_id or not parser.has_section(section):
            continue
        action = parser[section]
        action_exec = action.get("Exec", "")
        result["actions"].append({"id": action_id, "name": localized(action, "Name", environ),
                                  "icon": unescape(action.get("Icon", "")), "execString": action_exec,
                                  "command": exec_command(action_exec, name, icon, path)})
    return result


def snapshot(directories, environ=None):
    environ = os.environ if environ is None else environ
    index, applications, icon_paths, seen = {}, [], set(), set()
    for directory in directories:
        for path in desktop_files(directory):
            desktop_id = str(path.relative_to(directory)).replace("/", "-")[:-8]
            if desktop_id in seen:
                continue
            seen.add(desktop_id)
            try:
                contents = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            index[desktop_id] = field_values(contents)
            app = application(contents, desktop_id, path, environ)
            if app is None:
                continue
            applications.append(app)
            for value in [app["icon"], *(action["icon"] for action in app["actions"])]:
                if value.startswith("/"):
                    icon_paths.add(value)
                elif value.startswith("file:"):
                    url = urlparse(value)
                    if url.netloc in {"", "localhost"}:
                        icon_paths.add(unquote(url.path))
    return {"entries": index, "applications": applications, "iconPaths": sorted(icon_paths)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", action="store_true", help="include launcher applications and icon paths")
    args = parser.parse_args()
    directories = application_dirs(os.environ)
    result = snapshot(directories) if args.snapshot else build_index(directories)
    print(json.dumps(result, ensure_ascii=False))
