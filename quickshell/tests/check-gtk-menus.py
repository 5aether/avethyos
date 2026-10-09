#!/usr/bin/env python3
"""Render GTK 3/4 context menus on private Broadway displays in both modes.

Requires PyGObject, GTK 3/4, libadwaita, broadwayd and gtk4-broadwayd. Checks
actual popup compositing, pointer/keyboard selections and disabled labels.
Avethy theme aliases, including GTK 3's inherited assets, are staged privately.
No desktop windows or theme settings are changed; PyCairo is not required.
"""
import argparse
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import warnings


def rgba(hex_color, alpha=1):
    return [round(int(hex_color[i:i + 2], 16) * alpha) for i in (5, 3, 1)] + [round(255 * alpha)]


def assert_pixel(actual, expected, name):
    assert all(abs(a - b) <= 1 for a, b in zip(actual, expected)), (name, actual, expected)


def assert_foreground(actual, hex_color, name):
    color = [round(255 * actual.blue), round(255 * actual.green),
             round(255 * actual.red), round(255 * actual.alpha)]
    assert_pixel(color, rgba(hex_color), name)


def settle(context):
    until = time.monotonic() + .22
    while time.monotonic() < until:
        while context.pending():
            context.iteration(False)
        time.sleep(.005)


def gtk3_check(Gtk, Gdk, GLib, role, mode):
    menu = Gtk.Menu()
    item = Gtk.MenuItem.new_with_label("Open")
    disabled = Gtk.MenuItem.new_with_label("Unavailable")
    disabled.set_sensitive(False)
    menu.append(item)
    menu.append(disabled)
    menu.show_all()
    cairo = ctypes.CDLL("libcairo.so.2")
    gtk = ctypes.CDLL("libgtk-3.so.0")
    cairo.cairo_image_surface_create.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
    cairo.cairo_image_surface_create.restype = ctypes.c_void_p
    cairo.cairo_create.argtypes = [ctypes.c_void_p]
    cairo.cairo_create.restype = ctypes.c_void_p
    cairo.cairo_destroy.argtypes = [ctypes.c_void_p]
    cairo.cairo_surface_destroy.argtypes = [ctypes.c_void_p]
    cairo.cairo_surface_flush.argtypes = [ctypes.c_void_p]
    cairo.cairo_image_surface_get_data.argtypes = [ctypes.c_void_p]
    cairo.cairo_image_surface_get_data.restype = ctypes.POINTER(ctypes.c_ubyte)
    gtk.gtk_render_background.argtypes = [ctypes.c_void_p, ctypes.c_void_p] + [ctypes.c_double] * 4

    def background(widget, state):
        context = widget.get_style_context()
        context.set_state(state)
        surface = cairo.cairo_image_surface_create(0, 240, 40)
        cr = cairo.cairo_create(surface)
        try:
            gtk.gtk_render_background(hash(context), cr, 0, 0, 240, 40)
            cairo.cairo_surface_flush(surface)
            pixels = cairo.cairo_image_surface_get_data(surface)
            offset = (20 * 240 + 120) * 4
            return list(pixels[offset:offset + 4]), context.get_color(state)
        finally:
            cairo.cairo_destroy(cr)
            cairo.cairo_surface_destroy(surface)

    alpha = .94 if mode == "dark" else .97
    pixel, foreground = background(menu, Gtk.StateFlags.NORMAL)
    assert_pixel(pixel, rgba(role["surface_container_high"], alpha), "menu surface")
    assert_foreground(foreground, role["on_surface"], "menu text")
    assert_pixel(background(menu, Gtk.StateFlags.BACKDROP)[0], pixel, "inactive menu surface")
    for name, state in (("pointer", Gtk.StateFlags.PRELIGHT),
                        ("keyboard", Gtk.StateFlags.FOCUSED)):
        selected, foreground = background(item, state)
        assert_pixel(selected, rgba(role["primary"]), name + " background")
        assert_foreground(foreground, role["on_primary"], name + " text")
        assert_foreground(item.get_child().get_style_context().get_color(state),
                          role["on_primary"], name + " label")
    disabled_pixel, foreground = background(disabled, Gtk.StateFlags.INSENSITIVE)
    assert_pixel(disabled_pixel, [0, 0, 0, 0], "disabled row remains transparent")
    menu.destroy()
    return pixel, foreground


def gtk4_check(Gtk, Gdk, GLib, role, mode):
    from gi.repository import Adw, Gio, Graphene
    window = Adw.Window(default_width=400, default_height=300)
    group = Gio.SimpleActionGroup()
    model = Gio.Menu()
    for name, label, enabled in (("open", "Open", True), ("disabled", "Unavailable", False)):
        action = Gio.SimpleAction.new(name, None)
        action.set_enabled(enabled)
        group.add_action(action)
        model.append(label, "check." + name)
    window.insert_action_group("check", group)
    menu = Gtk.PopoverMenu.new_from_model(model)
    button = Gtk.MenuButton(label="Context menu", popover=menu)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.append(button)
    window.set_content(box)
    paintable = Gtk.WidgetPaintable.new(menu)
    window.present()
    button.popup()
    context = GLib.MainContext.default()
    settle(context)

    def descendants(widget):
        yield widget
        child = widget.get_first_child()
        while child:
            yield from descendants(child)
            child = child.get_next_sibling()

    items = [widget for widget in descendants(menu) if widget.get_css_name() == "modelbutton"]
    assert len(items) == 2, "GTK menu modelbutton structure changed"
    contents = menu.get_first_child()
    gtk = ctypes.CDLL("libgtk-4.so.1")
    gtk.gdk_texture_download.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]

    def sample(widget, inset):
        settle(context)
        width, height = menu.get_width(), menu.get_height()
        snapshot = Gtk.Snapshot.new()
        paintable.snapshot(snapshot, width, height)
        node = snapshot.to_node()
        assert node is not None, "GTK popup did not render"
        bounds = Graphene.Rect()
        bounds.init(0, 0, width, height)
        texture = window.get_renderer().render_texture(node, bounds)
        pixels = (ctypes.c_ubyte * (width * height * 4))()
        gtk.gdk_texture_download(hash(texture), pixels, width * 4)
        ok, rect = widget.compute_bounds(menu)
        assert ok
        x = round(rect.get_x() + inset)
        y = round(rect.get_y() + rect.get_height() / 2)
        offset = (y * width + x) * 4
        return list(pixels[offset:offset + 4])

    alpha = .94 if mode == "dark" else .97
    pixel = sample(contents, 3)
    assert_pixel(pixel, rgba(role["surface_container_high"], alpha), "single popup surface")
    clear = (Gtk.StateFlags.PRELIGHT | Gtk.StateFlags.FOCUSED | Gtk.StateFlags.FOCUS_VISIBLE |
             Gtk.StateFlags.ACTIVE | Gtk.StateFlags.SELECTED)
    window.set_focus(None)
    item, disabled = items
    for name, state in (("pointer", Gtk.StateFlags.PRELIGHT),
                        ("keyboard", Gtk.StateFlags.FOCUSED)):
        item.unset_state_flags(clear)
        item.set_state_flags(state, False)
        ok, rect = item.compute_bounds(menu)
        assert ok
        selected = sample(item, rect.get_width() - 7)
        assert_pixel(selected, rgba(role["primary"]), name + " background")
        assert_foreground(item.get_style_context().get_color(), role["on_primary"], name + " text")
        labels = [widget for widget in descendants(item) if widget.get_css_name() == "label"]
        assert labels
        assert_foreground(labels[0].get_style_context().get_color(), role["on_primary"], name + " label")
    foreground = disabled.get_style_context().get_color()
    ok, rect = disabled.compute_bounds(menu)
    assert ok
    assert_pixel(sample(disabled, rect.get_width() - 7), pixel, "disabled row remains transparent")
    labels = [widget for widget in descendants(disabled) if widget.get_css_name() == "label"]
    assert labels
    assert_foreground(labels[0].get_style_context().get_color(),
                      "#%02x%02x%02x" % (round(255 * foreground.red), round(255 * foreground.green),
                                          round(255 * foreground.blue)), "disabled label inheritance")
    window.destroy()
    return pixel, foreground


def render(version, mode, css_directory, theme_only):
    warnings.filterwarnings("ignore", category=DeprecationWarning)
    import gi
    gi.require_version("Gtk", version + ".0")
    gi.require_version("Gdk", version + ".0")
    if version == "4":
        gi.require_version("Adw", "1")
    from gi.repository import Gdk, GLib, Gtk
    if version == "3":
        Gtk.init([])
    else:
        from gi.repository import Adw
        Adw.init()
        Adw.StyleManager.get_default().set_color_scheme(
            Adw.ColorScheme.FORCE_DARK if mode == "dark" else Adw.ColorScheme.FORCE_LIGHT)
    spec = importlib.util.spec_from_file_location(
        "material_palette", Path(__file__).parents[1] / "scripts/material-palette.py")
    palette = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(palette)
    role = palette.material_roles(palette.tonal_palette((7, 49, 98)))[mode]
    if css_directory:
        role = json.loads((css_directory / mode / "desktop-theme.json").read_text())["roles"]
    provider = Gtk.CssProvider()
    errors = []
    provider.connect("parsing-error", lambda p, section, error: errors.append(str(error)))
    if css_directory:
        provider.load_from_path(str(css_directory / mode / ("gtk-" + version + ".0") / "gtk.css"))
    elif version == "3":
        provider.load_from_data(palette.gtk_css(role).encode())
    else:
        provider.load_from_string(palette.gtk_css(role, gtk4=True))
    if version == "3":
        if not theme_only:
            Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_USER)
        pixel, foreground = gtk3_check(Gtk, Gdk, GLib, role, mode)
    else:
        if not theme_only:
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                                       Gtk.STYLE_PROVIDER_PRIORITY_USER)
        pixel, foreground = gtk4_check(Gtk, Gdk, GLib, role, mode)
    muted = palette.blend_color(role["on_surface"], role["surface_container_high"], .55)
    assert_foreground(foreground, muted, "disabled text")
    assert not errors, errors
    print(json.dumps({"gtk": version, "mode": mode, "surface_bgra": pixel,
                      "states": ["pointer", "keyboard", "disabled"], "css_errors": errors}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gtk", choices=("3", "4"))
    parser.add_argument("--mode", choices=("dark", "light"))
    parser.add_argument("--css-directory", type=Path)
    parser.add_argument("--theme-only", action="store_true", help="Check named themes without user CSS overrides")
    parser.add_argument("--render", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.render:
        render(args.gtk, args.mode, args.css_directory, args.theme_only)
        return
    spec = importlib.util.spec_from_file_location(
        "material_palette", Path(__file__).parents[1] / "scripts/material-palette.py")
    palette = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(palette)
    for version in (args.gtk,) if args.gtk else ("3", "4"):
        with tempfile.TemporaryDirectory(prefix="gtk-menu-check-") as directory:
            env = os.environ.copy()
            data = Path(directory) / "data"
            roles = palette.material_roles(palette.tonal_palette((7, 49, 98)))
            for mode in roles:
                if args.css_directory:
                    roles[mode] = json.loads((args.css_directory / mode / "desktop-theme.json").read_text())["roles"]
                palette.install_gtk_theme(roles[mode], mode, data)
            env.update(XDG_RUNTIME_DIR=directory, XDG_CONFIG_HOME=directory, XDG_DATA_HOME=str(data),
                       GDK_BACKEND="broadway",
                       BROADWAY_DISPLAY=":43", GSK_RENDERER="cairo")
            env["GTK_THEME"] = palette.gtk_theme_name("light")
            daemon = subprocess.Popen(["broadwayd" if version == "3" else "gtk4-broadwayd",
                                       "--unixsocket=" + directory + "/web.sock", ":43"],
                                      env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 3
                # GTK 3 uses an abstract display socket; the HTTP socket is
                # visible on disk for both daemon versions.
                while not (Path(directory) / "web.sock").exists():
                    if daemon.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("Private GTK display failed to start")
                    time.sleep(.01)
                for mode in (args.mode,) if args.mode else ("dark", "light"):
                    env["GTK_THEME"] = palette.gtk_theme_name(mode)
                    command = [sys.executable, str(Path(__file__).resolve()), "--render",
                               "--gtk", version, "--mode", mode]
                    if args.css_directory:
                        command += ["--css-directory", str(args.css_directory.resolve())]
                    if args.theme_only:
                        command += ["--theme-only"]
                    subprocess.run(command, env=env, check=True)
            finally:
                daemon.terminate()
                daemon.wait(timeout=3)


if __name__ == "__main__":
    main()
