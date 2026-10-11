#!/usr/bin/env python3
"""Emit app/icon filesystem changes, including new roots and symlinked exports."""

import ctypes
import errno
import importlib.util
import json
import os
from pathlib import Path
import select
import struct
import time


def helper(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


desktop_search = helper("desktop-search")
icon_theme = helper("icon-theme")

IN_CLOSE_WRITE = 0x00000008
IN_ATTRIB = 0x00000004
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
IN_ISDIR = 0x40000000
MASK = (IN_CLOSE_WRITE | IN_ATTRIB | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE
        | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF)
EVENT = struct.Struct("=iIII")


def is_directory(path):
    try:
        return path.is_dir()
    except OSError:
        return False


def watch_plan(roots, icon_paths=(), subscribe=None):
    plan = {}
    followed = set()
    real_paths = {}
    directories = {}
    linked_paths = []

    def real_path(path):
        path = str(path)
        if path not in real_paths:
            real_paths[path] = os.path.realpath(path)
        return real_paths[path]

    def directory_exists(path):
        path = str(path)
        if path not in directories:
            directories[path] = is_directory(Path(path))
        return directories[path]

    def add(directory, kind, mode, target):
        real = real_path(directory)
        context = (kind, mode, str(directory), str(target))
        plan.setdefault(real, set()).add(context)
        if subscribe:
            subscribe(real, context)

    def parent(target, kind):
        directory = target.parent
        while not directory_exists(directory) and directory != directory.parent:
            directory = directory.parent
        # A tree watch already covers ordinary files in that directory. Keep
        # explicit watches for symlink directories and missing ancestors.
        suffixes = {".desktop"} if kind == "applications" else {".svg", ".png", ".xpm", ".theme"}
        if (target.suffix.lower() in suffixes
                and any(context[0] == kind and context[1] == "tree"
                        for context in plan.get(real_path(directory), ()))):
            return
        add(directory, kind, "ancestor", target)

    def links(path, kind):
        pending = [path]
        while pending:
            candidate = pending.pop()
            while True:
                key = (kind, str(candidate))
                if key in followed:
                    break
                followed.add(key)
                try:
                    destination = Path(os.readlink(candidate)) if candidate.is_symlink() else None
                except OSError:
                    destination = None
                if destination is not None:
                    # Flatpak may replace an intermediate "active" symlink
                    # while leaving the exported desktop file untouched.
                    parent(candidate, kind)
                    if not destination.is_absolute():
                        destination = candidate.parent / destination
                    destination = Path(os.path.abspath(destination))
                    parent(destination, kind)
                    pending.append(destination)
                ancestor = candidate.parent
                if ancestor == candidate:
                    break
                candidate = ancestor

    for kind, root in roots:
        parent(root, kind)
        linked_paths.append((root, kind))
        if directory_exists(root):
            add(root, kind, "tree", root)
        visited = set()
        for directory, children, filenames in os.walk(root, followlinks=True):
            linked_paths.append((Path(directory), kind))
            real = real_path(directory)
            if real in visited:
                children[:] = []
                continue
            visited.add(real)
            add(directory, kind, "tree", root)
            for name in filenames:
                path = Path(directory) / name
                if (kind == "applications" and path.suffix == ".desktop"
                        or kind == "icons" and path.suffix.lower() in {".svg", ".png", ".xpm", ".theme"}):
                    if path.is_symlink():
                        linked_paths.append((path, kind))
    for path, kind in linked_paths:
        links(path, kind)
    for path in icon_paths:
        parent(Path(path), "icons")
        links(Path(path), "icons")
    return plan


class Watcher:
    def __init__(self):
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.libc.inotify_init1.argtypes = [ctypes.c_int]
        self.libc.inotify_init1.restype = ctypes.c_int
        self.libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self.libc.inotify_add_watch.restype = ctypes.c_int
        self.libc.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]
        self.libc.inotify_rm_watch.restype = ctypes.c_int
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "could not start desktop file monitoring")
        self.watches = {}
        self.root_plans = {}
        self.context_roots = {}
        self.dirty_roots = set()

    def close(self):
        os.close(self.fd)

    def add_watch(self, path):
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), MASK)
        if wd < 0:
            code = ctypes.get_errno()
            if code in {errno.ENOENT, errno.ENOTDIR, errno.EACCES}:
                return None
            raise OSError(code, "could not watch desktop files", path)
        return wd

    def sync(self, roots, icon_paths=(), refresh_roots=None):
        def subscribe(path, context):
            wd = self.add_watch(path)
            if wd is not None:
                self.watches.setdefault(wd, set()).add(context)

        keys = {(kind, str(path)) for kind, path in roots}
        for key in sorted(keys):
            if key not in self.root_plans or refresh_roots is None or key in refresh_roots:
                # Arm each directory before scanning its children, so installs
                # during the first scan remain queued as filesystem events.
                self.root_plans[key] = watch_plan([(key[0], Path(key[1]))], subscribe=subscribe)
        self.root_plans = {key: plan for key, plan in self.root_plans.items() if key in keys}
        plan = watch_plan([], icon_paths, subscribe=subscribe)
        context_roots = {}
        for key, root_plan in self.root_plans.items():
            for path, contexts in root_plan.items():
                plan.setdefault(path, set()).update(contexts)
                for context in contexts:
                    context_roots.setdefault(context, set()).add(key)
        watches = {}
        for path, contexts in plan.items():
            # The same path can now name a different inode after an atomic
            # replacement. Re-adding also reuses unchanged watches safely.
            wd = self.add_watch(path)
            if wd is None:
                continue
            watches.setdefault(wd, set()).update(contexts)
        for wd in self.watches.keys() - watches.keys():
            self.libc.inotify_rm_watch(self.fd, wd)
        self.watches = watches
        self.context_roots = context_roots
        self.dirty_roots.clear()

    def read(self):
        changed = set()
        topology = set()
        while True:
            try:
                data = os.read(self.fd, 262144)
            except BlockingIOError:
                break
            offset = 0
            while offset < len(data):
                wd, mask, _, length = EVENT.unpack_from(data, offset)
                offset += EVENT.size
                name = os.fsdecode(data[offset:offset + length].split(b"\0", 1)[0])
                offset += length
                if mask & IN_Q_OVERFLOW:
                    changed.update(["applications", "icons"])
                    topology.update(["applications", "icons"])
                    self.dirty_roots.update(self.root_plans)
                    continue
                contexts = self.watches.get(wd, ())
                for context in contexts:
                    kind, mode, directory, target = context
                    event_path = Path(directory) / name
                    if mode == "ancestor":
                        if event_path != Path(target) and event_path not in Path(target).parents:
                            continue
                        changed.add(kind)
                        topology.add(kind)
                        self.dirty_roots.update(self.context_roots.get(context, ()))
                    elif (mask & (IN_ISDIR | IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED)
                          or is_directory(event_path)
                          or mask & (IN_CREATE | IN_MOVED_TO) and event_path.is_symlink()):
                        changed.add(kind)
                        topology.add(kind)
                        self.dirty_roots.update(self.context_roots.get(context, ()))
                    elif kind == "applications" and name.endswith(".desktop"):
                        changed.add(kind)
                    elif kind == "icons" and (Path(name).suffix.lower() in {".svg", ".png", ".xpm", ".theme"}
                                              or name == "icon-theme.cache"):
                        changed.add(kind)
                if mask & IN_IGNORED:
                    self.watches.pop(wd, None)
        return changed, topology


def notify(changed, ready=False):
    print(json.dumps({"applications": "applications" in changed,
                      "icons": "icons" in changed, "ready": ready}), flush=True)


def run():
    directories = desktop_search.application_dirs(os.environ)
    roots = [("applications", path) for path in directories]
    roots.extend(("icons", path) for path in icon_theme.icon_roots(include_missing=True))
    roots.extend(("icons", path) for path in icon_theme.pixmap_roots(include_missing=True))
    watcher = Watcher()
    try:
        watcher.sync(roots)
        icon_paths = desktop_search.snapshot(directories)["iconPaths"]
        watcher.sync(roots, icon_paths, refresh_roots=set())
        notify({"applications", "icons"}, ready=True)
        pending, topology = set(), set()
        first = last = 0
        while True:
            timeout = max(0, min(first + .35, last + .08) - time.monotonic()) if pending else None
            readable, _, _ = select.select([watcher.fd], [], [], timeout)
            if readable:
                changed, tree_changed = watcher.read()
                if changed:
                    if not pending:
                        first = time.monotonic()
                    last = time.monotonic()
                    pending.update(changed)
                    topology.update(tree_changed)
            if pending and time.monotonic() >= min(first + .35, last + .08):
                applications_changed = "applications" in pending
                if applications_changed:
                    icon_paths = desktop_search.snapshot(directories)["iconPaths"]
                    pending.add("icons")
                if topology or applications_changed:
                    watcher.sync(roots, icon_paths, refresh_roots=set(watcher.dirty_roots))
                notify(pending)
                pending, topology = set(), set()
    finally:
        watcher.close()


if __name__ == "__main__":
    run()
