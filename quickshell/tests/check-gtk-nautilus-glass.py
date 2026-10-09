#!/usr/bin/env python3
"""Render Nautilus's Adwaita view/status-page structure on a private display.

Requires PyGObject, GTK 4, libadwaita and gtk4-broadwayd. No desktop windows or
theme settings are changed. Both light and dark CSS are checked by default.
"""
import argparse
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def check(mode, css_directory):
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gdk, GLib, Graphene, Gsk, Gtk

    Adw.init()
    Adw.StyleManager.get_default().set_color_scheme(
        Adw.ColorScheme.FORCE_DARK if mode == "dark" else Adw.ColorScheme.FORCE_LIGHT)
    spec = importlib.util.spec_from_file_location(
        "material_palette", Path(__file__).parents[1] / "scripts/material-palette.py")
    palette = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(palette)
    provider = Gtk.CssProvider()
    errors = []
    provider.connect("parsing-error", lambda p, section, error: errors.append(str(error)))
    if css_directory:
        provider.load_from_path(str(css_directory / mode / "gtk-4.0/gtk.css"))
    else:
        role = palette.material_roles(palette.tonal_palette((7, 49, 98)))[mode]
        provider.load_from_string(palette.gtk_css(role, gtk4=True))
    assert not errors, errors
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                              Gtk.STYLE_PROVIDER_PRIORITY_USER)
    window = Adw.Window(title="Nautilus background check", default_width=1000, default_height=680)
    # This class is on NautilusWindow itself, not just on the populated view.
    window.add_css_class("view")
    split = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
    sidebar_toolbar = Adw.ToolbarView()
    sidebar_toolbar.add_top_bar(Adw.HeaderBar())
    sidebar = Gtk.ListBox()
    sidebar.add_css_class("navigation-sidebar")
    sidebar.append(Gtk.Label(label="Home"))
    sidebar_toolbar.set_content(sidebar)
    sidebar_toolbar.set_size_request(220, -1)
    split.append(sidebar_toolbar)
    toolbar = Adw.ToolbarView(hexpand=True)
    toolbar.add_top_bar(Adw.HeaderBar())
    stack = Gtk.Stack()
    stack.add_css_class("view")
    for name, title, icon in (
        ("empty", "Folder is Empty", "folder-symbolic"),
        ("search", "No Results Found", "edit-find-symbolic"),
        ("error", "Unable to Access Location", "dialog-error-symbolic"),
    ):
        status = Adw.StatusPage(title=title, icon_name=icon)
        stack.add_named(status, name)
    factory = Gtk.SignalListItemFactory()
    factory.connect("setup", lambda factory, item: item.set_child(Gtk.Label(label="Example.txt")))
    for name, css_class in (("list", "nautilus-list-view"),
                            ("grid", "nautilus-grid-view"),
                            ("network", "nautilus-network-view")):
        model = Gtk.NoSelection.new(Gtk.StringList.new(["Example.txt"]))
        view = Gtk.GridView.new(model, factory) if name == "grid" else Gtk.ListView.new(model, factory)
        container = Gtk.ScrolledWindow(child=view)
        container.add_css_class(css_class)
        stack.add_named(container, name)
    toolbar.set_content(stack)
    split.append(toolbar)
    window.set_content(split)
    paintable = Gtk.WidgetPaintable.new(window)
    window.present()
    context = GLib.MainContext.default()
    library = ctypes.CDLL("libgtk-4.so.1")
    library.gdk_texture_download.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
    measurements = {}
    expected_alpha = round(255 * (.88 if mode == "dark" else .94))
    for name in ("empty", "search", "error", "list", "grid", "network"):
        stack.set_visible_child_name(name)
        until = time.monotonic() + .4
        while time.monotonic() < until:
            while context.pending():
                context.iteration(False)
            time.sleep(.005)
        width, height = window.get_width(), window.get_height()
        snapshot = Gtk.Snapshot.new()
        paintable.snapshot(snapshot, width, height)
        bounds = Graphene.Rect()
        bounds.init(0, 0, width, height)
        node = snapshot.to_node()
        assert node is not None, ("Window did not render", width, height, window.get_mapped())
        texture = window.get_renderer().render_texture(node, bounds)
        pixels = (ctypes.c_ubyte * (width * height * 4))()
        library.gdk_texture_download(hash(texture), pixels, width * 4)
        alpha = pixels[((height - 40) * width + width - 40) * 4 + 3]
        assert abs(alpha - expected_alpha) <= 1, (mode, name, alpha, expected_alpha)
        measurements[name] = alpha
    window.destroy()
    print(json.dumps({"mode": mode, "background_alpha": measurements, "css_errors": errors}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("dark", "light"))
    parser.add_argument("--css-directory", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="nautilus-glass-check-") as directory:
        os.environ.update(XDG_RUNTIME_DIR=directory, XDG_CONFIG_HOME=directory,
                          GDK_BACKEND="broadway", BROADWAY_DISPLAY=":37", GSK_RENDERER="cairo")
        os.environ.pop("GTK_THEME", None)
        daemon = subprocess.Popen(["gtk4-broadwayd", "--unixsocket=" + directory + "/web.sock", ":37"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not (Path(directory) / "broadway38.socket").exists():
                if daemon.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("Private GTK display failed to start")
                time.sleep(.01)
            for mode in (args.mode,) if args.mode else ("dark", "light"):
                check(mode, args.css_directory)
        finally:
            daemon.terminate()
            daemon.wait(timeout=3)


if __name__ == "__main__":
    main()
