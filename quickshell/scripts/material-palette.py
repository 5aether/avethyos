#!/usr/bin/env python3
"""Generate and install a Material-style desktop palette from a wallpaper.

Only Python's standard library is required.  ffmpeg/ffprobe do the decoding,
which gives identical handling for still images, animated images, and videos.
"""

from __future__ import annotations

import argparse
import ast
import configparser
import fcntl
import json
import math
import os
from pathlib import Path
import random
import re
import shlex
import shutil
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse


def xdg_directory(variable: str, fallback: Path) -> Path:
    value = os.environ.get(variable, "")
    return Path(value) if value and Path(value).is_absolute() else fallback


HOME = Path.home()
ROOT = Path(__file__).resolve().parent.parent
CONFIG_HOME = xdg_directory("XDG_CONFIG_HOME", HOME / ".config")
STATE_HOME = xdg_directory("XDG_STATE_HOME", HOME / ".local/state")
SHELL_CONFIG = STATE_HOME / "avethyos/quickshell/config.ini"
HYPR_THEME = STATE_HOME / "avethyos/hypr/theme.lua"
# Quickshell reads this from the host session even when a launcher itself was
# started by a sandboxed editor with an app-specific XDG_CACHE_HOME.
CACHE = HOME / ".cache/avethy"
PALETTE_FILE = CACHE / "palette.ini"
SCHEME_NAME = "Avethy"
QT_STYLE_NAME = "Avethy"
QT_QUICK_STYLE_NAME = "Avethy"
QT_PLUGIN_DIR = ROOT / "native/qt-theme/build-qt6/plugins"
QT5_PLUGIN_DIR = ROOT / "native/qt-theme/build-qt5/plugins"
QT_QML_DIR = ROOT / "native/qt-theme/qml"
QT_THEME_DIR = CONFIG_HOME / "avethy"
FALLBACK_SEED = (103, 80, 164)
QT_COLOR_ROLES = (
    "WindowText", "Button", "Light", "Midlight", "Dark", "Mid", "Text",
    "BrightText", "ButtonText", "Base", "Window", "Shadow", "Highlight",
    "HighlightedText", "Link", "LinkVisited", "AlternateBase", "NoRole",
    "ToolTipBase", "ToolTipText", "PlaceholderText", "Accent",
)


def gtk_theme_name(mode: str) -> str:
    return "Avethy-dark" if mode == "dark" else "Avethy"


def gsettings_command() -> str:
    # Homebrew's GLib can use a separate settings backend from native GTK.
    # Preserve ordinary PATH overrides, but use the desktop's tool in that case.
    command = shutil.which("gsettings")
    if command and ({".linuxbrew", "Cellar"} & set(Path(command).parts)) and Path("/usr/bin/gsettings").is_file():
        return "/usr/bin/gsettings"
    return "gsettings"


def desktop_icon_theme(mode: str, config: Path | None = None) -> str:
    """Use the exact configured pack; an empty value follows GTK's selection."""
    def value(path: Path, section: str, key: str) -> str:
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            parser.read(path, encoding="utf-8")
            return parser.get(section, key, fallback="").strip()
        except (configparser.Error, OSError, UnicodeError):
            return ""

    selected = value(config or SHELL_CONFIG, "appearance", "icon-pack")
    if selected:
        return selected
    for version in ("gtk-3.0", "gtk-4.0"):
        selected = value(CONFIG_HOME / version / "settings.ini", "Settings", "gtk-icon-theme-name")
        if selected:
            return selected.strip("\"'")
    try:
        selected = subprocess.check_output(
            [gsettings_command(), "get", "org.gnome.desktop.interface", "icon-theme"],
            text=True, stderr=subprocess.DEVNULL).strip()
        # GSettings prints a GVariant string, including its quoting/escapes.
        selected = ast.literal_eval(selected)
        if isinstance(selected, str) and selected:
            return selected
    except (OSError, subprocess.SubprocessError, SyntaxError, ValueError):
        pass
    return "Papirus-Dark" if mode == "dark" else "Papirus"


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def srgb_to_linear(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def linear_to_srgb(value: float) -> float:
    value = max(0.0, value)
    return 12.92 * value if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055


def rgb_to_oklab(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    r, g, b = (srgb_to_linear(x / 255) for x in rgb)
    l = 0.4122214708*r + 0.5363325363*g + 0.0514459929*b
    m = 0.2119034982*r + 0.6806995451*g + 0.1073969566*b
    s = 0.0883024619*r + 0.2817188376*g + 0.6299787005*b
    l_, m_, s_ = (max(0.0, x) ** (1/3) for x in (l, m, s))
    return (
        0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
        1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
        0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_,
    )


def oklab_to_linear(lab: tuple[float, float, float]) -> tuple[float, float, float]:
    L, a, b = lab
    l_ = L + 0.3963377774*a + 0.2158037573*b
    m_ = L - 0.1055613458*a - 0.0638541728*b
    s_ = L - 0.0894841775*a - 1.2914855480*b
    l, m, s = l_**3, m_**3, s_**3
    return (
        4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
        -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
        -0.0041960863*l - 0.7034186147*m + 1.7076147010*s,
    )


def oklab_to_rgb(lab: tuple[float, float, float]) -> tuple[int, int, int] | None:
    linear = oklab_to_linear(lab)
    # Check *before* encoding: linear_to_srgb clamps negative channels, which
    # otherwise hides out-of-gamut colors and changes their hue.
    if any(x < -1e-7 or x > 1.0000001 for x in linear):
        return None
    return tuple(round(clamp(linear_to_srgb(x)) * 255) for x in linear)


def oklch(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    L, a, b = rgb_to_oklab(rgb)
    return L, math.hypot(a, b), math.atan2(b, a)


def gamut_mapped_lab(lightness: float, chroma: float, hue: float) -> tuple[float, float, float]:
    lightness = clamp(lightness)
    chroma = max(0.0, chroma)
    a, b = math.cos(hue), math.sin(hue)
    lab = (lightness, chroma*a, chroma*b)
    if oklab_to_rgb(lab) is not None:
        return lab
    # Find the gamut boundary rather than reducing saturation in coarse steps.
    # Hue and lightness stay fixed, including near black and white.
    low, high = 0.0, chroma
    for _ in range(20):
        middle = (low + high) / 2
        candidate = (lightness, middle*a, middle*b)
        if oklab_to_rgb(candidate) is None:
            high = middle
        else:
            low = middle
    return lightness, low*a, low*b


def from_oklch(lightness: float, chroma: float, hue: float) -> tuple[int, int, int]:
    return oklab_to_rgb(gamut_mapped_lab(lightness, chroma, hue))


def tone_color(tone: float, chroma: float, hue: float) -> tuple[int, int, int]:
    """Match actual CIE L* luminance, not just the neutral Oklab axis."""
    if tone <= 0:
        return 0, 0, 0
    if tone >= 100:
        return 255, 255, 255
    target = ((tone + 16) / 116) ** 3 if tone > 8 else tone / 903.3
    low, high = 0.0, 1.0
    lab = (0.0, 0.0, 0.0)
    for _ in range(22):
        middle = (low + high) / 2
        lab = gamut_mapped_lab(middle, chroma, hue)
        r, g, b = oklab_to_linear(lab)
        luminance = 0.2126*r + 0.7152*g + 0.0722*b
        if luminance < target:
            low = middle
        else:
            high = middle
    return oklab_to_rgb(lab)


def blend_color(foreground: str, background: str, amount: float) -> str:
    """Opaque equivalent of an sRGB alpha overlay, for toolkit palettes."""
    return hex_color(tuple(round(int(foreground[i:i+2], 16)*amount
                                 + int(background[i:i+2], 16)*(1-amount))
                           for i in (1, 3, 5)))


def rgba_color(color: str, opacity: float) -> str:
    return f"rgba({csv_color(color)}, {opacity:.2f})"


def hex_color(rgb: tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % rgb


def csv_color(value: str) -> str:
    return ",".join(str(int(value[i:i+2], 16)) for i in (1, 3, 5))


def wallpaper_from_config() -> str:
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(SHELL_CONFIG)
    return parser.get("wallpaper", "path", fallback="").strip()


def local_source(source: str) -> str:
    if source.startswith("file:"):
        parsed = urlparse(source)
        return unquote(parsed.path)
    return source


def probe_duration(source: str) -> float:
    command = ["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=noprint_wrappers=1:nokey=1", source]
    try:
        return max(0.0, float(subprocess.check_output(command, stderr=subprocess.DEVNULL, timeout=8)))
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0.0


def decode_frame(source: str, seek: float | None = None) -> bytes:
    command = ["ffmpeg", "-v", "error"]
    if seek is not None and seek > 0:
        command += ["-ss", f"{seek:.3f}"]
    command += ["-i", source, "-frames:v", "1", "-vf",
                "scale=96:96:force_original_aspect_ratio=decrease",
                "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    try:
        return subprocess.check_output(command, stderr=subprocess.DEVNULL, timeout=18)
    except (OSError, subprocess.SubprocessError):
        return b""


def wallpaper_pixels(source: str) -> list[tuple[int, int, int]]:
    source = local_source(source)
    duration = probe_duration(source)
    seeks: list[float | None] = [None]
    if duration > 1.5:
        # Avoid credits/black intros and use content spread over the whole video.
        seeks = [duration*x for x in (0.08, 0.25, 0.43, 0.61, 0.78, 0.92)]
    pixels: list[tuple[int, int, int]] = []
    for seek in seeks:
        raw = decode_frame(source, seek)
        # A light spatial stride keeps clustering fast without biasing one edge.
        pixels.extend(tuple(raw[i:i+3]) for i in range(0, len(raw)-2, 12))
    return pixels


def dominant_seed(pixels: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    if not pixels:
        return FALLBACK_SEED
    labs = [rgb_to_oklab(p) for p in pixels]
    rng = random.Random(0x4D415433)
    centers = [labs[rng.randrange(len(labs))]]
    for _ in range(11):
        distances = [min(sum((x-y)**2 for x, y in zip(point, c)) for c in centers)
                     for point in labs]
        total = sum(distances)
        if total <= 1e-12:
            break
        needle = rng.random() * total
        acc = 0.0
        for point, distance in zip(labs, distances):
            acc += distance
            if acc >= needle:
                centers.append(point)
                break
    counts = [0] * len(centers)
    for _ in range(9):
        groups: list[list[tuple[float, float, float]]] = [[] for _ in centers]
        for point in labs:
            index = min(range(len(centers)), key=lambda i: sum((point[j]-centers[i][j])**2 for j in range(3)))
            groups[index].append(point)
        for i, group in enumerate(groups):
            counts[i] = len(group)
            if group:
                centers[i] = tuple(sum(x[j] for x in group)/len(group) for j in range(3))
    total = max(1, len(labs))
    def score(item: tuple[int, tuple[float, float, float]]) -> float:
        i, (L, a, b) = item
        chroma = math.hypot(a, b)
        population = math.sqrt(counts[i] / total)
        tone_fit = 1.0 - min(1.0, abs(L - 0.58) / 0.58)
        # Population weights chroma too: a tiny vivid detail should not beat
        # the colors present throughout the wallpaper.
        return population*(chroma*3.8 + 0.25)*(0.8 + tone_fit*0.2)
    chosen = max((item for item in enumerate(centers) if counts[item[0]]), key=score)[1]
    rgb = oklab_to_rgb(chosen)
    return rgb or from_oklch(chosen[0], math.hypot(chosen[1], chosen[2]), math.atan2(chosen[2], chosen[1]))


def tonal_palette(seed: tuple[int, int, int]) -> dict[str, str]:
    _, seed_c, hue = oklch(seed)
    # Achromatic wallpapers stay achromatic. Low-chroma wallpapers keep their
    # character rather than being forced into a saturated, arbitrary hue.
    chromatic = seed_c >= 0.015
    families = {
        "primary": (hue, max(0.075, min(seed_c, 0.24)) if chromatic else 0.0),
        "secondary": (hue, min(seed_c*0.5, 0.075) if chromatic else 0.0),
        "tertiary": (hue + math.radians(60), min(seed_c*0.7, 0.115) if chromatic else 0.0),
        "neutral": (hue, min(seed_c*0.10, 0.018) if chromatic else 0.0),
        "neutral_variant": (hue, min(seed_c*0.25, 0.045) if chromatic else 0.0),
        "error": (math.radians(27), 0.18),
        "success": (math.radians(145), 0.14),
        "warning": (math.radians(85), 0.15),
    }
    tones = [0, 4, 6, 10, 12, 17, 20, 22, 24, 30, 35, 40, 50, 60, 70, 80, 87, 90, 92, 94, 95, 96, 98, 99, 100]
    out: dict[str, str] = {"seed": hex_color(seed)}
    for family, (family_hue, chroma) in families.items():
        for tone in tones:
            out[f"{family}_{tone}"] = hex_color(tone_color(tone, chroma, family_hue))
    return out


def material_roles(tones: dict[str, str]) -> dict[str, dict[str, str]]:
    def f(name: str, tone: int) -> str:
        return tones[f"{name}_{tone}"]
    light = {
        "primary": f("primary", 40), "on_primary": f("primary", 100),
        "primary_container": f("primary", 90), "on_primary_container": f("primary", 10),
        "secondary": f("secondary", 40), "on_secondary": f("secondary", 100),
        "secondary_container": f("secondary", 90), "on_secondary_container": f("secondary", 10),
        "tertiary": f("tertiary", 40), "on_tertiary": f("tertiary", 100),
        "tertiary_container": f("tertiary", 90), "on_tertiary_container": f("tertiary", 10),
        "error": f("error", 40), "on_error": f("error", 100),
        "error_container": f("error", 90), "on_error_container": f("error", 10),
        "background": f("neutral", 99), "on_background": f("neutral", 10),
        "surface": f("neutral", 99), "on_surface": f("neutral", 10),
        "surface_variant": f("neutral_variant", 90), "on_surface_variant": f("neutral_variant", 30),
        "outline": f("neutral_variant", 50), "outline_variant": f("neutral_variant", 80),
        "shadow": f("neutral", 0), "scrim": f("neutral", 0),
        "surface_tint": f("primary", 40),
        "inverse_surface": f("neutral", 20), "inverse_on_surface": f("neutral", 95),
        "inverse_primary": f("primary", 80), "surface_dim": f("neutral", 87),
        "surface_bright": f("neutral", 98), "surface_container_lowest": f("neutral", 100),
        "surface_container_low": f("neutral", 96), "surface_container": f("neutral", 94),
        "surface_container_high": f("neutral", 92), "surface_container_highest": f("neutral", 90),
        "primary_fixed": f("primary", 90), "primary_fixed_dim": f("primary", 80),
        "on_primary_fixed": f("primary", 10), "on_primary_fixed_variant": f("primary", 30),
        "secondary_fixed": f("secondary", 90), "secondary_fixed_dim": f("secondary", 80),
        "on_secondary_fixed": f("secondary", 10), "on_secondary_fixed_variant": f("secondary", 30),
        "tertiary_fixed": f("tertiary", 90), "tertiary_fixed_dim": f("tertiary", 80),
        "on_tertiary_fixed": f("tertiary", 10), "on_tertiary_fixed_variant": f("tertiary", 30),
        "success": f("success", 40), "on_success": f("success", 100),
        "warning": f("warning", 40), "on_warning": f("warning", 100),
    }
    dark = {
        "primary": f("primary", 80), "on_primary": f("primary", 20),
        "primary_container": f("primary", 30), "on_primary_container": f("primary", 90),
        "secondary": f("secondary", 80), "on_secondary": f("secondary", 20),
        "secondary_container": f("secondary", 30), "on_secondary_container": f("secondary", 90),
        "tertiary": f("tertiary", 80), "on_tertiary": f("tertiary", 20),
        "tertiary_container": f("tertiary", 30), "on_tertiary_container": f("tertiary", 90),
        "error": f("error", 80), "on_error": f("error", 20),
        "error_container": f("error", 30), "on_error_container": f("error", 90),
        "background": f("neutral", 6), "on_background": f("neutral", 90),
        "surface": f("neutral", 6), "on_surface": f("neutral", 90),
        "surface_variant": f("neutral_variant", 30), "on_surface_variant": f("neutral_variant", 80),
        "outline": f("neutral_variant", 60), "outline_variant": f("neutral_variant", 30),
        "shadow": f("neutral", 0), "scrim": f("neutral", 0),
        "surface_tint": f("primary", 80),
        "inverse_surface": f("neutral", 90), "inverse_on_surface": f("neutral", 20),
        "inverse_primary": f("primary", 40), "surface_dim": f("neutral", 6),
        "surface_bright": f("neutral", 24), "surface_container_lowest": f("neutral", 4),
        "surface_container_low": f("neutral", 10), "surface_container": f("neutral", 12),
        "surface_container_high": f("neutral", 17), "surface_container_highest": f("neutral", 22),
        "primary_fixed": f("primary", 90), "primary_fixed_dim": f("primary", 80),
        "on_primary_fixed": f("primary", 10), "on_primary_fixed_variant": f("primary", 30),
        "secondary_fixed": f("secondary", 90), "secondary_fixed_dim": f("secondary", 80),
        "on_secondary_fixed": f("secondary", 10), "on_secondary_fixed_variant": f("secondary", 30),
        "tertiary_fixed": f("tertiary", 90), "tertiary_fixed_dim": f("tertiary", 80),
        "on_tertiary_fixed": f("tertiary", 10), "on_tertiary_fixed_variant": f("tertiary", 30),
        "success": f("success", 80), "on_success": f("success", 20),
        "warning": f("warning", 80), "on_warning": f("warning", 20),
    }
    return {"light": light, "dark": dark}


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def preserve_once(path: Path) -> None:
    backup = path.with_name(path.name + ".before-material")
    if ((not path.exists() and not path.is_symlink())
            or backup.exists() or backup.is_symlink()):
        return
    if path.is_symlink():
        backup.symlink_to(os.readlink(path))
    else:
        shutil.copy2(path, backup)


def palette_text(source: str, tones: dict[str, str], roles: dict[str, dict[str, str]]) -> str:
    lines = ["# Generated Avethy palette; do not edit.", "name=Avethy", f"source={source}", f"seed={tones['seed']}"]
    for mode in ("light", "dark"):
        lines.extend(f"{mode}.{key}={value}" for key, value in roles[mode].items())
    return "\n".join(lines) + "\n"


def write_palette(source: str, tones: dict[str, str], roles: dict[str, dict[str, str]]) -> None:
    atomic_write(PALETTE_FILE, palette_text(source, tones, roles))


def write_preview(directory: Path, source: str, tones: dict[str, str], roles: dict[str, dict[str, str]]) -> None:
    """Write both themes for inspection without touching desktop settings."""
    atomic_write(directory / "palette.ini", palette_text(source, tones, roles))
    for mode, role in roles.items():
        target = directory / mode
        for version in ("gtk-3.0", "gtk-4.0"):
            atomic_write(target / version / "gtk.css", gtk_css(role, gtk4=(version == "gtk-4.0")))
        atomic_write(target / "gtkrc-2.0", gtk2_rc(role))
        atomic_write(target / "Avethy.colors", kde_colors(role))
        atomic_write(target / "qt5ct.conf", qt5ct_colors(role))
        atomic_write(target / "qt6ct.conf", qt6ct_colors(role))
        atomic_write(target / "gtk3-palette.json", qt_gtk_bridge(role))
        atomic_write(target / "desktop-theme.json", qt_native_theme(role, mode, target / "Avethy.colors"))
        atomic_write(target / "qtquickcontrols2.conf", qt_quick_config())


def gtk_css(role: dict[str, str], gtk4: bool = False) -> str:
    dark = sum(int(role["background"][i:i+2], 16) for i in (1, 3, 5)) < 384
    glass = rgba_color(role["background"], 0.88 if dark else 0.94)
    floating = rgba_color(role["surface_container_high"], 0.94 if dark else 0.97)
    header = rgba_color(role["surface_container"], 0.45 if dark else 0.60)
    border = rgba_color(role["outline"], 0.24)
    muted = blend_color(role["on_surface"], role["surface_container"], 0.50)
    menu_muted = blend_color(role["on_surface"], role["surface_container_high"], 0.55)
    definitions = {
        "accent_color": role["primary"], "accent_bg_color": role["primary"],
        "accent_fg_color": role["on_primary"], "window_bg_color": glass,
        "window_fg_color": role["on_background"], "view_bg_color": role["surface_container_low"],
        "view_fg_color": role["on_surface"], "headerbar_bg_color": header,
        "headerbar_fg_color": role["on_surface"], "headerbar_border_color": border,
        "headerbar_backdrop_color": header,
        "headerbar_shade_color": rgba_color(role["shadow"], 0.12),
        "headerbar_darker_shade_color": rgba_color(role["shadow"], 0.18),
        "card_bg_color": rgba_color(role["surface_container_high"], 0.65),
        "card_fg_color": role["on_surface"], "card_shade_color": rgba_color(role["shadow"], 0.12),
        "popover_bg_color": floating, "popover_fg_color": role["on_surface"],
        "popover_shade_color": rgba_color(role["shadow"], 0.16),
        "menu_bg_color": floating, "menu_fg_color": role["on_surface"],
        "menu_selected_bg_color": role["primary"], "menu_selected_fg_color": role["on_primary"],
        "menu_border_color": border,
        "dialog_bg_color": glass, "dialog_fg_color": role["on_surface"],
        "sidebar_bg_color": role["surface_container_low"], "sidebar_fg_color": role["on_surface"],
        "sidebar_backdrop_color": role["surface_container_low"], "sidebar_border_color": border,
        "sidebar_shade_color": rgba_color(role["shadow"], 0.12),
        "secondary_sidebar_bg_color": role["surface_container"],
        "secondary_sidebar_fg_color": role["on_surface"],
        "secondary_sidebar_backdrop_color": role["surface_container_low"],
        "secondary_sidebar_border_color": border,
        "secondary_sidebar_shade_color": rgba_color(role["shadow"], 0.12),
        "destructive_color": role["error"], "destructive_bg_color": role["error"],
        "destructive_fg_color": role["on_error"], "error_color": role["error"],
        "error_bg_color": role["error_container"], "error_fg_color": role["on_error_container"],
        "success_color": role["success"], "success_bg_color": role["success"],
        "success_fg_color": role.get("on_success", role["on_primary"]),
        "warning_color": role["warning"], "warning_bg_color": role["warning"],
        "warning_fg_color": role.get("on_warning", role["on_primary"]),
        "borders": border, "unfocused_borders": border,
        "theme_bg_color": role["background"], "theme_fg_color": role["on_background"],
        "theme_base_color": role["surface_container_low"], "theme_text_color": role["on_surface"],
        "theme_selected_bg_color": role["primary"], "theme_selected_fg_color": role["on_primary"],
        "theme_unfocused_bg_color": role["surface_container_low"],
        "theme_unfocused_fg_color": role["on_surface"],
        "theme_unfocused_base_color": role["surface_container_low"],
        "theme_unfocused_text_color": role["on_surface"],
        "theme_unfocused_selected_bg_color": role["primary"],
        "theme_unfocused_selected_fg_color": role["on_primary"],
        "insensitive_bg_color": role["surface_container"],
        "insensitive_fg_color": muted,
        "insensitive_base_color": role["surface_container_low"],
        "theme_tooltip_bg_color": role["surface_container_high"],
        "theme_tooltip_fg_color": role["on_surface"],
        "content_view_bg": role["surface_container_low"], "text_view_bg": role["surface_container_low"],
        "theme_button_background_normal": role["surface_container_high"],
        "wm_title": role["on_surface"], "wm_unfocused_title": role["on_surface_variant"],
        "wm_highlight": role["outline_variant"], "wm_borders_edge": role["outline_variant"],
        "shade_color": rgba_color(role["shadow"], 0.16), "scrollbar_outline_color": border,
        "thumbnail_bg_color": role["surface_container_highest"],
        "thumbnail_fg_color": role["on_surface"],
    }
    head = "/* Generated Avethy wallpaper colors. */\n" + "\n".join(
        f"@define-color {name} {value};" for name, value in definitions.items())
    variables = ""
    if gtk4:
        # libadwaita 1.6+ uses CSS variables. Set the actual colors as well as
        # legacy names so standalone accents do not get lightness-shifted.
        names = ("accent", "destructive", "success", "warning", "error",
                 "window", "view", "headerbar", "card", "popover", "dialog",
                 "sidebar", "secondary_sidebar", "thumbnail")
        modern = {name.replace("_", "-"): value for name, value in definitions.items()
                  if name.startswith(tuple(prefix + "_" for prefix in names))}
        modern.update({"shade-color": definitions["shade_color"],
                       "scrollbar-outline-color": border,
                       "active-toggle-bg-color": role["primary"],
                       "active-toggle-fg-color": role["on_primary"],
                       "overview-bg-color": role["surface_container_low"],
                       "overview-fg-color": role["on_surface"]})
        variables = "\n:root {\n" + "\n".join(
            f"  --{name}: {value};" for name, value in modern.items()) + "\n}\n"
        # Nautilus and GTK's file chooser set a local grey accent on their
        # views. Override that scope too, so rubber bands/focus stay in sync.
        variables += f"""
.nautilus-list-view listview, .nautilus-grid-view gridview, .nautilus-network-view listview,
filechooser columnview > listview, filechooser gridview, filechooser placesview list {{
  --accent-bg-color: {role['primary']};
  --accent-fg-color: {role['on_primary']};
  --accent-color: {role['primary']};
}}
/* Nautilus marks its top-level window as .view. An opaque view background
   there covers the glass even when the content is just an empty status page.
   Paint the tint once at the window, with transparent content layers in both
   populated views and empty/search/error pages. Scope this to Files windows. */
window.view {{
  --view-bg-color: transparent;
  --sidebar-bg-color: transparent;
  --sidebar-backdrop-color: transparent;
  background-color: {glass}; background-image: none;
}}
window.view:backdrop {{ background-color: {glass}; }}
window.view .view, window.view statuspage, window.view .navigation-sidebar,
window.view .nautilus-list-view listview, window.view .nautilus-list-view columnview,
window.view .nautilus-grid-view gridview, window.view .nautilus-network-view listview {{
  background-color: transparent; background-image: none;
}}
dialog-host > dialog.background {{ background-color: transparent; background-image: none; }}
dialog-host > dialog.background sheet, dialog-host > dialog sheet,
window.dialog, window.dialog-window, window.messagedialog {{ background-color: {glass}; color: {role['on_surface']}; }}
/* The properties pane also appears inside the main Nautilus window. Its
   transparent containers let the one glass window/dialog layer show through. */
.nautilus-properties, .nautilus-properties viewport, .nautilus-properties navigation-view,
.nautilus-properties navigation-view > navigation-page, .nautilus-properties preferencespage {{ background-color: transparent; }}
.nautilus-properties headerbar {{ background-color: transparent; box-shadow: none; }}
.nautilus-properties list.boxed-list {{ background-color: @card_bg_color; }}
"""
    # GTK 4 popovers have a transparent outer node and a rounded `contents`
    # child. Libadwaita gives that node the `background` class, whose selector
    # is more specific than plain `popover`; reset its full background so only
    # the rounded child is painted.
    popover_rules = (f"""
popover, popover.background {{ background-color: transparent; background-image: none; color: {role['on_surface']}; }}
popover > contents {{ background-color: {floating}; background-image: none; color: {role['on_surface']}; border: 1px solid {border}; border-radius: 12px; }}
popover > contents modelbutton {{ color: {role['on_surface']}; border-radius: 8px; }}
popover > contents modelbutton:hover {{ background-color: {role['surface_container_highest']}; color: {role['on_surface']}; }}
popover > contents separator {{ background-color: {border}; }}
""" if gtk4 else f"""
popover.background {{ background-color: {floating}; background-image: none; color: {role['on_surface']}; border-color: {border}; border-radius: 12px; }}
popover.background label, popover.background menuitem {{ color: inherit; }}
""")
    gtk3_rules = "" if gtk4 else """
/* GTK 3 themes can paint controls with background images, which otherwise
   cover the generated Material colors (most visibly on disabled buttons). */
button, combobox button, spinbutton button { background-image: none; }
button:hover, button:active, button:checked, button:disabled { background-image: none; }
"""
    rules = f"""
window, window.background {{ background-color: {glass}; color: {role['on_background']}; }}
window:backdrop, window.background:backdrop {{ background-color: {glass}; color: {role['on_surface']}; }}
headerbar, .titlebar {{ background-color: {header}; background-image: none; color: {role['on_surface']}; border-color: {border}; box-shadow: none; }}
headerbar:backdrop, .titlebar:backdrop {{ background-color: {header}; color: {role['on_surface']}; }}
headerbar label, headerbar image, .titlebar label, .titlebar image {{ color: inherit; }}
menu, .menu {{ background-color: {floating}; color: {role['on_surface']}; border-color: {border}; border-radius: 12px; }}
menu label, menuitem {{ color: inherit; }}
tooltip, tooltip.background {{ background-color: {floating}; background-image: none; color: {role['on_surface']}; }}
tooltip label {{ color: {role['on_surface']}; }}
entry, textview, textview text, treeview.view, iconview, list, listview {{ background-color: {role['surface_container_low']}; color: {role['on_surface']}; }}
entry:focus {{ border-color: {role['primary']}; }}
button {{ background-color: {role['surface_container_high']}; color: {role['on_surface']}; border-color: {border}; }}
button:not(.circular):not(.pill) {{ border-radius: 8px; }}
button label, button image {{ color: inherit; }}
button:hover {{ background-color: {role['surface_container_highest']}; color: {role['on_surface']}; }}
button.flat, button.image-button, button.circular, headerbar button, .titlebar button, .toolbar button {{ background-color: transparent; border-color: transparent; box-shadow: none; }}
button.flat:hover, button.image-button:hover, button.circular:hover, headerbar button:hover, .titlebar button:hover, .toolbar button:hover {{ background-color: {rgba_color(role['on_surface'], 0.08)}; }}
button:disabled {{ color: {muted}; }}
button:disabled label, button:disabled image {{ color: inherit; }}
button:checked, button.toggle:checked, headerbar button:checked, .toolbar button:checked {{ background-color: {role['primary']}; background-image: none; color: {role['on_primary']}; border-color: transparent; }}
button:checked label, button:checked image {{ color: {role['on_primary']}; }}
button.suggested-action {{ background-color: {role['primary']}; color: {role['on_primary']}; }}
button.suggested-action label, button.suggested-action image {{ color: {role['on_primary']}; }}
button.destructive-action {{ background-color: {role['error']}; color: {role['on_error']}; }}
button.destructive-action label, button.destructive-action image {{ color: {role['on_error']}; }}
placessidebar, placessidebar list {{ background-color: {role['surface_container_low']}; color: {role['on_surface']}; }}
placessidebar row {{ background-color: transparent; color: {role['on_surface_variant']}; }}
placessidebar row label, placessidebar row image {{ color: {role['on_surface_variant']}; }}
placessidebar row:hover {{ background-color: {role['surface_container_high']}; color: {role['on_surface']}; }}
.navigation-sidebar row, placessidebar row {{ border-radius: 10px; }}
filechooser .dialog-action-box {{ background-color: {header}; color: {role['on_surface']}; border-color: {border}; }}
check:checked, check:indeterminate, radio:checked, radio:indeterminate,
switch:checked, scale highlight, progressbar progress {{ background-color: {role['primary']}; background-image: none; color: {role['on_primary']}; border-color: {role['primary']}; }}
switch:checked slider {{ background-color: {role['on_primary']}; }}
rubberband {{ background-color: {rgba_color(role['primary'], 0.18)}; border: 1px solid {role['primary']}; border-radius: 6px; }}
"""
    for selector, background, foreground in (
            ("button:checked", "primary", "on_primary"),
            ("button.suggested-action", "primary", "on_primary"),
            ("button.destructive-action", "error", "on_error")):
        selectors = ", ".join(selector + state for state in ("", ":hover", ":active", ":backdrop"))
        rules += f"\n{selectors} {{ background-color: {role[background]}; background-image: none; color: {role[foreground]}; }}\n"
        rules += f"{selector} label, {selector} image {{ color: {role[foreground]}; }}\n"
    # Keep this last, including the sidebar/hover/backdrop selectors: state or
    # child overrides must not change the accent or its matching foreground.
    selected = ["selection", "treeview.view:selected", "iconview:selected",
                "row:selected", "flowboxchild:selected", ".view:selected",
                "placessidebar row:selected", ".navigation-sidebar row:selected",
                "stacksidebar row:selected"]
    if gtk4:
        selected += ["gridview > child:selected", "listview > row:selected"]
    states = ("", ":hover", ":active", ":backdrop")
    selectors = [selector + state for selector in selected for state in states]
    selection_rules = "\n" + ",\n".join(selectors) + f""" {{
  background-color: {role['primary']}; background-image: none;
  color: {role['on_primary']};
}}
row:selected label, row:selected image, flowboxchild:selected label, flowboxchild:selected image,
placessidebar row:selected label, placessidebar row:selected image,
.navigation-sidebar row:selected label, .navigation-sidebar row:selected image {{ color: {role['on_primary']}; opacity: 1; }}
"""
    if gtk4:
        selection_rules += f"""
gridview > child:selected label, gridview > child:selected image {{ color: {role['on_primary']}; }}
entry:focus-within {{ outline-color: {role['primary']}; }}
*:focus-visible {{ outline-color: {role['primary']}; }}
"""
    # Keep popup rules last: .menu and stock hover/focus rules must not put a
    # second surface on the popover shell or retain the base theme's colors.
    menu_rules = f"""
/* One palette surface per popup, with matching pointer/keyboard states. */
tooltip, tooltip.background {{ background-color: {floating}; background-image: none; color: {role['on_surface']}; border: 1px solid {border}; border-radius: 8px; text-shadow: none; }}
tooltip label, tooltip image {{ color: {role['on_surface']}; text-shadow: none; }}
"""
    if gtk4:
        menu_rules += f"""
popover, popover.background, popover.menu, popover.menu.background {{ background-color: transparent; background-image: none; color: {role['on_surface']}; }}
popover > contents, popover.menu > contents {{ background-color: {floating}; background-image: none; color: {role['on_surface']}; border: 1px solid {border}; border-radius: 12px; }}
popover > contents scrolledwindow, popover > contents viewport, popover > contents stack,
popover.menu > contents box, popover.menu > contents list, popover.menu > contents listview {{ background-color: transparent; background-image: none; }}
popover.menu modelbutton, popover.menu button.model {{ background-color: transparent; background-image: none; color: {role['on_surface']}; border-color: transparent; border-radius: 8px; box-shadow: none; text-shadow: none; }}
popover.menu modelbutton:hover, popover.menu modelbutton:focus, popover.menu modelbutton:selected,
popover.menu modelbutton:active, popover.menu button.model:hover, popover.menu button.model:focus,
popover.menu button.model:selected, popover.menu button.model:active {{ background-color: {role['primary']}; background-image: none; color: {role['on_primary']}; }}
popover.menu modelbutton:disabled, popover.menu button.model:disabled {{ background-color: transparent; background-image: none; color: {menu_muted}; opacity: 1; }}
popover.menu modelbutton label, popover.menu modelbutton image, popover.menu modelbutton arrow,
popover.menu button.model label, popover.menu button.model image, popover.menu button.model arrow {{ color: inherit; opacity: 1; }}
popover.menu modelbutton check, popover.menu modelbutton radio,
popover.menu button.model check, popover.menu button.model radio {{ color: {role['primary']}; background-color: transparent; background-image: none; }}
popover.menu modelbutton:hover check, popover.menu modelbutton:focus check, popover.menu modelbutton:selected check,
popover.menu modelbutton:hover radio, popover.menu modelbutton:focus radio, popover.menu modelbutton:selected radio,
popover.menu button.model:hover check, popover.menu button.model:focus check, popover.menu button.model:selected check,
popover.menu button.model:hover radio, popover.menu button.model:focus radio, popover.menu button.model:selected radio {{ color: {role['on_primary']}; }}
popover.menu separator, popover.menu separator:backdrop {{ background-color: {border}; background-image: none; color: {border}; }}
"""
    else:
        menu_rules += f"""
menu, menu:backdrop, .menu, popover.background {{ background-color: {floating}; background-image: none; color: {role['on_surface']}; border-color: {border}; border-radius: 12px; text-shadow: none; }}
menu menuitem, menuitem, popover modelbutton {{ background-color: transparent; background-image: none; color: {role['on_surface']}; border-color: transparent; border-radius: 8px; box-shadow: none; text-shadow: none; }}
menu menuitem:hover, menu menuitem:focus, menu menuitem:selected, menu menuitem:active,
menuitem:hover, menuitem:focus, menuitem:selected, menuitem:active,
popover modelbutton:hover, popover modelbutton:focus, popover modelbutton:selected, popover modelbutton:active {{ background-color: {role['primary']}; background-image: none; color: {role['on_primary']}; }}
menu menuitem:disabled, menuitem:disabled, popover modelbutton:disabled {{ background-color: transparent; background-image: none; color: {menu_muted}; opacity: 1; }}
menuitem label, menuitem image, menuitem arrow, popover modelbutton label, popover modelbutton image, popover modelbutton arrow {{ color: inherit; opacity: 1; }}
menuitem check, menuitem radio, popover modelbutton check, popover modelbutton radio {{ color: {role['primary']}; background-color: transparent; background-image: none; }}
menuitem:hover check, menuitem:focus check, menuitem:selected check,
menuitem:hover radio, menuitem:focus radio, menuitem:selected radio,
popover modelbutton:hover check, popover modelbutton:focus check, popover modelbutton:selected check,
popover modelbutton:hover radio, popover modelbutton:focus radio, popover modelbutton:selected radio {{ color: {role['on_primary']}; }}
menu separator, popover separator {{ background-color: {border}; background-image: none; color: {border}; }}
"""
    return head + variables + popover_rules + gtk3_rules + rules + selection_rules + menu_rules


def write_ini(path: Path, updates: dict[str, dict[str, str]]) -> None:
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    if path.exists():
        try:
            config.read(path)
        except configparser.Error:
            pass
    for section, values in updates.items():
        if not config.has_section(section):
            config.add_section(section)
        for key, value in values.items():
            config.set(section, key, str(value))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        config.write(stream, space_around_delimiters=False)
    temporary.replace(path)


def install_gtk_theme(role: dict[str, str], mode: str, data: Path) -> None:
    """Keep GTK's existing control geometry and assets under the Avethy name."""
    theme = data / "themes" / gtk_theme_name(mode)
    base = Path("/usr/share/themes") / ("adw-gtk3-dark" if mode == "dark" else "adw-gtk3")
    if base.is_dir():
        shutil.copytree(base, theme, dirs_exist_ok=True)
    atomic_write(theme / "index.theme", f"[Desktop Entry]\nType=X-GNOME-Metatheme\nName={gtk_theme_name(mode)}\n"
                 f"\n[X-GNOME-Metatheme]\nGtkTheme={gtk_theme_name(mode)}\n")
    for version in ("gtk-3.0", "gtk-4.0"):
        for filename in ("gtk.css", "gtk-dark.css"):
            original = base / version / filename
            content = original.read_text(encoding="utf-8") if original.is_file() else ""
            atomic_write(theme / version / filename,
                         content + "\n" + gtk_css(role, gtk4=(version == "gtk-4.0")))
    atomic_write(theme / "gtk-2.0/gtkrc", gtk2_rc(role))


def install_gtk(role: dict[str, str], mode: str) -> None:
    install_gtk_theme(role, mode, HOME / ".local/share")
    for version in ("gtk-3.0", "gtk-4.0"):
        css = gtk_css(role, gtk4=(version == "gtk-4.0"))
        directory = CONFIG_HOME / version
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / "gtk.css"
        preserve_once(target)
        preserve_once(directory / "gtk-dark.css")
        atomic_write(target, css)
        atomic_write(directory / "gtk-dark.css", css)
        write_ini(directory / "settings.ini", {"Settings": {
            "gtk-theme-name": gtk_theme_name(mode),
            "gtk-icon-theme-name": desktop_icon_theme(mode),
            "gtk-application-prefer-dark-theme": "1" if mode == "dark" else "0",
        }})
    preserve_once(HOME / ".gtkrc-2.0")
    atomic_write(HOME / ".gtkrc-2.0", gtk2_rc(role))


def gtk2_rc(role: dict[str, str]) -> str:
    background = tuple(int(role["background"][i:i+2], 16) for i in (1, 3, 5))
    mode = "dark" if rgb_to_oklab(background)[0] < .5 else "light"
    names = {
        "bg_color": role["background"], "fg_color": role["on_background"],
        "base_color": role["surface_container_low"], "text_color": role["on_surface"],
        "selected_bg_color": role["primary"], "selected_fg_color": role["on_primary"],
        "tooltip_bg_color": role["surface_container_high"], "tooltip_fg_color": role["on_surface"],
        "menu_bg_color": role["surface_container_high"], "menu_fg_color": role["on_surface"],
    }
    scheme = "\\n".join(f"{name}:{value}" for name, value in names.items())
    states = {
        "NORMAL": ("background", "on_background", "surface_container_low", "on_surface"),
        "PRELIGHT": ("surface_container_highest", "on_surface", "surface_container_low", "on_surface"),
        "ACTIVE": ("primary", "on_primary", "primary", "on_primary"),
        "SELECTED": ("primary", "on_primary", "primary", "on_primary"),
        "INSENSITIVE": ("surface_container", "on_surface_variant", "surface_container_low", "on_surface_variant"),
    }
    lines = ["# Generated Avethy wallpaper colors.", f'gtk-theme-name = "{gtk_theme_name(mode)}"',
             f'gtk-icon-theme-name = {json.dumps(desktop_icon_theme(mode), ensure_ascii=False)}',
             'gtk-font-name = "SF Pro Text 10"', f'gtk-color-scheme = "{scheme}"',
             'style "avethy" {']
    for state, values in states.items():
        for key, name in zip(("bg", "fg", "base", "text"), values):
            lines.append(f'  {key}[{state}] = "{role[name]}"')
    lines += ["}", 'class "*" style "avethy"']
    lines += ['style "avethy-menu" = "avethy" {']
    for state in ("NORMAL", "PRELIGHT", "ACTIVE", "SELECTED", "INSENSITIVE"):
        selected = state in ("PRELIGHT", "ACTIVE", "SELECTED")
        background = role["primary" if selected else "surface_container_high"]
        foreground = role["on_primary" if selected else "on_surface"]
        if state == "INSENSITIVE":
            foreground = blend_color(role["on_surface"], role["surface_container_high"], .55)
        for key, value in (("bg", background), ("base", background), ("fg", foreground), ("text", foreground)):
            lines.append(f'  {key}[{state}] = "{value}"')
    lines += ['}', 'widget_class "*Menu*" style "avethy-menu"']
    return "\n".join(lines) + "\n"


def install_flatpak_configs(role: dict[str, str], mode: str) -> None:
    """Mirror native configs into existing Flatpak per-app XDG homes."""
    root = HOME / ".var/app"
    if not root.is_dir():
        return
    for app in root.iterdir():
        config = app / "config"
        if not config.is_dir():
            continue
        install_gtk_theme(role, mode, app / "data")
        atomic_write(config / "gtk-2.0/gtkrc", gtk2_rc(role))
        for version in ("gtk-3.0", "gtk-4.0"):
            css = gtk_css(role, gtk4=(version == "gtk-4.0"))
            directory = config / version
            target = directory / "gtk.css"
            preserve_once(target)
            atomic_write(target, css)
            preserve_once(directory / "gtk-dark.css")
            atomic_write(directory / "gtk-dark.css", css)
            write_ini(directory / "settings.ini", {"Settings": {
                "gtk-theme-name": gtk_theme_name(mode),
                "gtk-icon-theme-name": desktop_icon_theme(mode),
                "gtk-application-prefer-dark-theme": "1" if mode == "dark" else "0",
            }})
        install_qtct(role, mode, config)
        atomic_write(config / "qt6ct/gtk3-palette.json", qt_gtk_bridge(role))
        kde_updates = parse_ini_text(kde_colors(role))
        kde_updates.setdefault("General", {})["ColorScheme"] = SCHEME_NAME
        kde_updates["Icons"] = {"Theme": desktop_icon_theme(mode)}
        kde_updates["UiSettings"] = {"ColorScheme": SCHEME_NAME}
        kde_updates.setdefault("KDE", {})["widgetStyle"] = QT_STYLE_NAME
        scheme_path = app / "data/color-schemes" / f"{SCHEME_NAME}.colors"
        atomic_write(scheme_path, kde_colors(role))
        atomic_write(config / "avethy/palette.json", qt_native_theme(role, mode, scheme_path))
        atomic_write(config / "avethy/qtquickcontrols2.conf", qt_quick_config())
        copy_native_qt_plugins(config / "avethy/qt-plugins")
        sync_kde_app_schemes(config, role)
        write_ini(config / "kdeglobals", kde_updates)


def kde_colors(role: dict[str, str]) -> str:
    bg = csv_color(role["background"]); surface = csv_color(role["surface_container"])
    high = csv_color(role["surface_container_high"]); fg = csv_color(role["on_surface"])
    muted = csv_color(role["on_surface_variant"]); primary = csv_color(role["primary"])
    on_primary = csv_color(role["on_primary"]); outline = csv_color(role["outline_variant"])
    error = csv_color(role["error"]); success = csv_color(role["success"]); warning = csv_color(role["warning"])
    color_set = lambda background: f'''BackgroundAlternate={high}\nBackgroundNormal={background}\nDecorationFocus={primary}\nDecorationHover={primary}\nForegroundActive={primary}\nForegroundInactive={muted}\nForegroundLink={primary}\nForegroundNegative={error}\nForegroundNeutral={warning}\nForegroundNormal={fg}\nForegroundPositive={success}\nForegroundVisited={csv_color(role['tertiary'])}'''
    selection = f'''BackgroundAlternate={primary}\nBackgroundNormal={primary}\nDecorationFocus={primary}\nDecorationHover={primary}\nForegroundActive={on_primary}\nForegroundInactive={on_primary}\nForegroundLink={on_primary}\nForegroundNegative={on_primary}\nForegroundNeutral={on_primary}\nForegroundNormal={on_primary}\nForegroundPositive={on_primary}\nForegroundVisited={on_primary}'''
    inactive_header = color_set(bg).replace(f"ForegroundNormal={fg}", f"ForegroundNormal={muted}")
    tooltip = color_set(high)
    return f'''[ColorEffects:Disabled]\nColor={muted}\nColorAmount=0\nColorEffect=0\nContrastAmount=0.35\nContrastEffect=1\nEnable=true\nIntensityAmount=0.1\nIntensityEffect=2\n\n[ColorEffects:Inactive]\nChangeSelectionColor=false\nColor={muted}\nColorAmount=0.025\nColorEffect=0\nContrastAmount=0.1\nContrastEffect=2\nEnable=false\nIntensityAmount=0\nIntensityEffect=0\n\n[Colors:Button]\n{color_set(high)}\n\n[Colors:Complementary]\n{color_set(high)}\n\n[Colors:Header]\n{color_set(surface)}\n\n[Colors:Header][Inactive]\n{inactive_header}\n\n[Colors:Selection]\n{selection}\n\n[Colors:Tooltip]\n{tooltip}\n\n[Colors:View]\n{color_set(csv_color(role['surface_container_low']))}\n\n[Colors:Window]\n{color_set(bg)}\n\n[General]\nColorScheme={SCHEME_NAME}\nName=Avethy\nshadeSortColumn=true\n\n[KDE]\ncontrast=4\n\n[WM]\nactiveBackground={surface}\nactiveBlend={surface}\nactiveForeground={fg}\ninactiveBackground={bg}\ninactiveBlend={bg}\ninactiveForeground={muted}\n'''


def parse_ini_text(content: str) -> dict[str, dict[str, str]]:
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config.read_string(content)
    return {section: dict(config.items(section)) for section in config.sections()}


def qt_palette_groups(role: dict[str, str], accent: bool = True) -> dict[str, list[str]]:
    """QPalette enum order: 21 legacy roles plus Qt 6.6's Accent role."""
    def argb(name: str) -> str:
        return "#ff" + role[name][1:]
    active = [
        argb("on_surface"), argb("surface_container_high"), argb("surface_container_highest"),
        argb("surface_container_highest"), argb("surface_dim"), argb("outline"),
        argb("on_surface"), argb("error"), argb("on_surface"), argb("surface_container_low"),
        argb("background"), argb("shadow"), argb("primary"), argb("on_primary"),
        argb("primary"), argb("tertiary"), argb("surface_container"),
        argb("on_surface"), argb("surface_container_high"), argb("on_surface"),
        "#ff" + blend_color(role["on_surface"], role["surface_container_low"], 0.60)[1:],
    ]
    if accent:
        active.append(argb("primary"))
    disabled = active.copy()
    # Opaque disabled text avoids platform-dependent alpha blending. Each
    # foreground is muted against the background where it is actually used.
    for index, background in ((0, "background"), (6, "surface_container_low"),
                              (7, "background"), (8, "surface_container_high"),
                              (14, "surface_container_low"), (15, "surface_container_low"),
                              (20, "surface_container_low")):
        disabled[index] = "#ff" + blend_color(role["on_surface"], role[background], 0.45)[1:]
    disabled[12] = "#ff" + blend_color(role["primary"], role["background"], 0.35)[1:]
    disabled[13] = "#ff" + blend_color(role["on_surface"], role["background"], 0.75)[1:]
    if accent:
        disabled[21] = disabled[12]
    inactive = active.copy()
    return {"Active": active, "Inactive": inactive, "Disabled": disabled}


def qt_palette_colors(role: dict[str, str], accent: bool = True) -> str:
    groups = qt_palette_groups(role, accent)
    return "[ColorScheme]\n" + "\n".join((
        "active_colors=" + ", ".join(groups["Active"]),
        "inactive_colors=" + ", ".join(groups["Inactive"]),
        "disabled_colors=" + ", ".join(groups["Disabled"]),
    )) + "\n"


def qt6ct_colors(role: dict[str, str]) -> str:
    return qt_palette_colors(role)


def qt5ct_colors(role: dict[str, str]) -> str:
    return qt_palette_colors(role, accent=False)


def qt_gtk_bridge(role: dict[str, str]) -> str:
    """Explicit Qt 6 GTK platform palette; avoids missing/derived GTK roles.

    Qt's GTK plugin supports QT_GUI_GTK_JSON. Its default widget mapping
    leaves Accent black and derives unrelated surfaces from disabled GTK
    widgets. Keep the GTK dialogs/plugin while supplying the shared palette.
    """
    system: dict[str, list[dict]] = {}
    for group, colors in qt_palette_groups(role).items():
        for name, color in zip(QT_COLOR_ROLES, colors):
            if name == "NoRole":
                continue
            system.setdefault(name, []).append({
                "ColorGroup": group, "ColorScheme": "Unknown", "SourceType": "Fixed",
                "SourceData": {"FixedBrush": {"Color": color, "Width": 0, "Height": 0}},
            })
    return json.dumps({"QtGtk3Palettes": {"SystemPalette": system}}, indent=2) + "\n"


def install_qtct(role: dict[str, str], mode: str, config: Path) -> None:
    for toolkit, colors in (("qt5ct", qt5ct_colors(role)), ("qt6ct", qt6ct_colors(role))):
        path = config / toolkit / "colors" / f"{SCHEME_NAME}.conf"
        atomic_write(path, colors)
        write_ini(config / toolkit / f"{toolkit}.conf", {"Appearance": {
            "color_scheme_path": str(path), "custom_palette": "true", "style": QT_STYLE_NAME,
            "icon_theme": desktop_icon_theme(mode)}})


def install_qt(role: dict[str, str], mode: str) -> None:
    scheme = kde_colors(role)
    kde_path = HOME / ".local/share/color-schemes" / f"{SCHEME_NAME}.colors"
    atomic_write(kde_path, scheme)
    install_qtct(role, mode, CONFIG_HOME)
    atomic_write(CONFIG_HOME / "qt6ct/gtk3-palette.json", qt_gtk_bridge(role))
    kde_updates = parse_ini_text(scheme)
    kde_updates.setdefault("General", {})["ColorScheme"] = SCHEME_NAME
    kde_updates["KDE"] = {"LookAndFeelPackage": "org.kde.breezedark.desktop" if mode == "dark" else "org.kde.breeze.desktop",
                          "contrast": "4", "widgetStyle": QT_STYLE_NAME}
    kde_updates["UiSettings"] = {"ColorScheme": SCHEME_NAME}
    kde_updates["Icons"] = {"Theme": desktop_icon_theme(mode)}
    write_ini(CONFIG_HOME / "kdeglobals", kde_updates)
    sync_kde_app_schemes(CONFIG_HOME, role)
    atomic_write(QT_THEME_DIR / "qtquickcontrols2.conf", qt_quick_config())
    # Publish the live palette last, after KDE has a complete scheme to read.
    atomic_write(QT_THEME_DIR / "palette.json", qt_native_theme(role, mode, kde_path))
    legacy = CONFIG_HOME / "quickshell-desktop/palette.json"
    if legacy.is_file():
        atomic_write(legacy, qt_native_theme(role, mode, kde_path))


def qt_native_theme(role: dict[str, str], mode: str, scheme: Path) -> str:
    return json.dumps({"version": 1, "name": "Avethy", "mode": mode, "roles": role,
                       "palette": qt_palette_groups(role), "kde_scheme": str(scheme)}, indent=2) + "\n"


def qt_quick_config() -> str:
    return f"[Controls]\nStyle={QT_QUICK_STYLE_NAME}\nFallbackStyle=Fusion\n\n[Fusion]\nFont\\Family=SF Pro Text\n"


def sync_kde_app_schemes(config: Path, role: dict[str, str]) -> None:
    """Replace saved GUI scheme overrides without touching editor/terminal colors."""
    schemes = parse_ini_text(kde_colors(role))
    for path in config.glob("*rc"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            content = path.read_text(encoding="utf-8")
            settings = parse_ini_text(content)
        except (OSError, UnicodeError, configparser.Error):
            continue
        updates: dict[str, dict[str, str]] = {}
        if "ColorScheme" in settings.get("UiSettings", {}):
            updates["UiSettings"] = {"ColorScheme": SCHEME_NAME}
        # Some KDE apps save GUI colors inline instead of using the manager.
        for section in settings:
            if section.startswith("Colors:") and section in schemes:
                updates[section] = schemes[section]
        if updates:
            preserve_once(path)
            write_ini(path, updates)
    # Dolphin must have an explicit scheme even outside a Plasma session.
    path = config / "dolphinrc"
    preserve_once(path)
    write_ini(path, {"UiSettings": {"ColorScheme": SCHEME_NAME}})


def copy_native_qt_plugins(destination: Path) -> None:
    """Refresh sandbox copies from image assets; host apps use assets directly."""
    for kind in ("styles", "generic"):
        expected = set()
        for build in (QT5_PLUGIN_DIR, QT_PLUGIN_DIR):
            for source in (build / kind).glob("libavethy-*.so"):
                expected.add(source.name)
                target = destination / kind / source.name
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists() or source.read_bytes() != target.read_bytes():
                    temporary = target.with_name(target.name + ".tmp")
                    shutil.copy2(source, temporary)
                    temporary.replace(target)
        # Removed plugins must disappear from this generated sandbox directory
        # too, otherwise Qt may keep selecting code removed by an image update.
        for previous in (destination / kind).glob("libavethy-*.so"):
            if previous.name not in expected:
                previous.unlink()
    source = QT_QML_DIR / QT_QUICK_STYLE_NAME
    target = destination / "qml" / QT_QUICK_STYLE_NAME
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True)
        source_files = {path.relative_to(source) for path in source.rglob("*") if path.is_file()}
        for previous in target.rglob("*"):
            if previous.is_file() and previous.relative_to(target) not in source_files:
                previous.unlink()


def qt_plugin_directories() -> list[Path]:
    """Qt rejects incompatible major versions in its shared plugin search path."""
    return [directory for directory in (QT_PLUGIN_DIR, QT5_PLUGIN_DIR) if directory.is_dir()]


def qt_environment(mode: str | None = None) -> dict[str, str]:
    """Shared by compositor, D-Bus activation, user services and shell launches."""
    result = {"QT_GUI_GTK_JSON": str(CONFIG_HOME / "qt6ct/gtk3-palette.json"),
              "QT_QPA_PLATFORMTHEME": "gtk3",
              "GTK_THEME": gtk_theme_name(current_mode(mode)),
              "GTK2_RC_FILES": str(HOME / ".gtkrc-2.0")}
    directories = qt_plugin_directories()
    if not any((directory / "styles" / f"libavethy-style-qt{major}.so").is_file()
               for directory in directories for major in (5, 6)):
        return result
    def prepend(key: str, paths: list[Path], separator: str = ":") -> str:
        values = [*(str(path) for path in paths), *os.environ.get(key, "").split(separator)]
        obsolete = {str(HOME / f".local/lib/{name}/qt-plugins") + suffix
                    for name in ("quickshell", "avethy") for suffix in ("", "/qml")}
        return separator.join(dict.fromkeys(value for value in values if value and value not in obsolete))
    generic = ["avethy-theme", *(value for value in os.environ.get("QT_QPA_GENERIC_PLUGINS", "").split(",")
                               if value != "quickshell-theme")]
    result.update({
        "QT_STYLE_OVERRIDE": QT_STYLE_NAME,
        "QT_PLUGIN_PATH": prepend("QT_PLUGIN_PATH", directories),
        "QT_QPA_GENERIC_PLUGINS": ",".join(dict.fromkeys(value for value in generic if value)),
        "AVETHY_QT_THEME": str(QT_THEME_DIR / "palette.json"),
        "QT_QUICK_CONTROLS_STYLE": QT_QUICK_STYLE_NAME,
        "QT_QUICK_CONTROLS_STYLE_PATH": str(QT_QML_DIR),
        "QT_QUICK_CONTROLS_FALLBACK_STYLE": "Fusion",
        "QT_QUICK_CONTROLS_CONF": str(QT_THEME_DIR / "qtquickcontrols2.conf"),
        "QML_IMPORT_PATH": prepend("QML_IMPORT_PATH", [QT_QML_DIR]),
        "QML2_IMPORT_PATH": prepend("QML2_IMPORT_PATH", [QT_QML_DIR]),
    })
    return result


def hyprland_theme(role: dict[str, str], bridge_path: Path, mode: str | None = None) -> str:
    # This generated state is included by the immutable compositor config.
    environment = qt_environment(mode)
    environment["QT_GUI_GTK_JSON"] = str(bridge_path)
    exports = "\n".join(f"hl.env({json.dumps(key)}, {json.dumps(value, ensure_ascii=False)})"
                        for key, value in environment.items())
    return f'''-- Managed by the Avethy wallpaper palette.
{exports}
hl.config({{
    general = {{
        col = {{
            active_border = "rgba({role['primary'][1:]}ff)",
            inactive_border = "rgba({role['outline_variant'][1:]}aa)",
        }},
    }},
}})
'''


def sync_qt_gtk_environment(role: dict[str, str], mode: str | None = None) -> None:
    """Export the generated GTK bridge to compositor and D-Bus app launches."""
    bridge = CONFIG_HOME / "qt6ct/gtk3-palette.json"
    content = hyprland_theme(role, bridge, mode)
    if not HYPR_THEME.exists() or HYPR_THEME.read_text(encoding="utf-8") != content:
        atomic_write(HYPR_THEME, content)
        if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and shutil.which("hyprctl"):
            subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)
    environment = os.environ.copy()
    environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"
    values = qt_environment(mode)
    # A systemd environment generator makes the same settings survive login.
    directory = CONFIG_HOME / "environment.d"
    path = directory / "90-avethy-theme.conf"
    atomic_write(path, "# Managed by the Avethy wallpaper palette.\n" +
                 "".join(f'{key}={json.dumps(value)}\n' for key, value in values.items()))
    previous = directory / "90-quickshell-theme.conf"
    if previous.is_file() and previous.read_text(encoding="utf-8").startswith("# Managed by the Quickshell wallpaper palette."):
        previous.unlink()  # Otherwise its later filename overrides Avethy at login.
    environment.update(values)
    assignments = [f"{key}={value}" for key, value in values.items()]
    for command in (["systemctl", "--user", "set-environment", *assignments],
                    ["dbus-update-activation-environment", "--systemd", *assignments]):
        if shutil.which(command[0]):
            subprocess.run(command, env=environment, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)


def nearest_gnome_accent(color: str) -> str:
    rgb = tuple(int(color[i:i+2], 16) for i in (1, 3, 5))
    choices = {
        "blue": (53, 132, 228), "teal": (0, 153, 153), "green": (51, 209, 122),
        "yellow": (246, 211, 45), "orange": (255, 120, 0), "red": (224, 27, 36),
        "pink": (213, 97, 153), "purple": (145, 65, 172), "slate": (111, 131, 150),
    }
    _, chroma, hue = oklch(rgb)
    if chroma < 0.025:
        return "slate"
    def distance(reference: tuple[int, int, int]) -> float:
        _, reference_chroma, reference_hue = oklch(reference)
        angle = abs(math.atan2(math.sin(hue-reference_hue), math.cos(hue-reference_hue)))
        return angle + 0.15*abs(chroma-reference_chroma)
    return min(choices, key=lambda name: distance(choices[name]))


def set_gsettings(mode: str, role: dict[str, str]) -> None:
    if not shutil.which("gsettings"):
        return
    gsettings = gsettings_command()
    legacy_scheme = ";".join((
        f"bg_color:{role['background']}", f"fg_color:{role['on_background']}",
        f"base_color:{role['surface']}", f"text_color:{role['on_surface']}",
        f"selected_bg_color:{role['primary']}", f"selected_fg_color:{role['on_primary']}",
    ))
    chooser_palette = ":".join(role[name] for name in (
        "primary", "secondary", "tertiary", "error", "success", "warning",
        "surface", "surface_container", "on_surface", "outline"))
    desired_theme = gtk_theme_name(mode)
    reload_theme = "Adwaita"
    desired_scheme = "prefer-dark" if mode == "dark" else "prefer-light"
    reload_scheme = "prefer-light" if mode == "dark" else "prefer-dark"
    commands = [
        [gsettings, "set", "org.gnome.desktop.interface", "color-scheme", reload_scheme],
        [gsettings, "set", "org.gnome.desktop.interface", "gtk-theme", reload_theme],
        [gsettings, "set", "org.gnome.desktop.interface", "icon-theme", desktop_icon_theme(mode)],
        [gsettings, "set", "org.gnome.desktop.interface", "accent-color", nearest_gnome_accent(role["primary"])],
        [gsettings, "set", "org.gnome.desktop.interface", "gtk-color-scheme", legacy_scheme],
        [gsettings, "set", "org.gnome.desktop.interface", "gtk-color-palette", chooser_palette],
    ]
    for command in commands:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    # Keep the two writes in separate DConf notifications. GTK 3, GTK 4 and
    # Qt's GTK platform theme then rebuild their providers/palettes in-process.
    time.sleep(0.08)
    for key, value in (("color-scheme", desired_scheme), ("gtk-theme", desired_theme)):
        subprocess.run([gsettings, "set", "org.gnome.desktop.interface", key, value],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def broadcast_kde_theme_change(changes: tuple[int, ...] = (0, 2, 4)) -> None:
    """Tell live KColorScheme consumers to reload kdeglobals immediately."""
    if not shutil.which("dbus-send"):
        return
    environment = os.environ.copy()
    environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"
    for change_type in changes:  # PaletteChanged, StyleChanged, IconChanged
        subprocess.run([
            "dbus-send", "--session", "--type=signal", "/KGlobalSettings",
            "org.kde.KGlobalSettings.notifyChange", f"int32:{change_type}", "int32:0",
        ], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def apply_icon_theme(mode: str, config: Path | None = None) -> None:
    """Sync icons independently of wallpaper colors, plugin installs and restarts.

    Qt's gtk3 platform theme reads GtkSettings' gtk-icon-theme-name directly.
    KDE's own icon loader reads kdeglobals instead; keep both in agreement.
    """
    selected = desktop_icon_theme(mode, config)
    targets = [(CONFIG_HOME, HOME / ".gtkrc-2.0")]
    flatpaks = HOME / ".var/app"
    if flatpaks.is_dir():
        targets.extend((app / "config", app / "config/gtk-2.0/gtkrc")
                       for app in flatpaks.iterdir() if (app / "config").is_dir())
    for directory, gtk2 in targets:
        for version in ("gtk-3.0", "gtk-4.0"):
            write_ini(directory / version / "settings.ini", {
                "Settings": {"gtk-icon-theme-name": selected}})
        content = gtk2.read_text(encoding="utf-8") if gtk2.is_file() else ""
        setting = "gtk-icon-theme-name = " + json.dumps(selected, ensure_ascii=False)
        updated, count = re.subn(r"^\s*gtk-icon-theme-name\s*=.*$", lambda _: setting,
                                 content, flags=re.MULTILINE)
        if not count:
            updated = content.rstrip("\n") + ("\n" if content else "") + setting + "\n"
        if content != updated:
            preserve_once(gtk2)
            atomic_write(gtk2, updated)
        write_ini(directory / "kdeglobals", {"Icons": {"Theme": selected}})
        # Keep existing compatibility configs consistent without depending on
        # qt5ct/qt6ct. The active Qt provider remains the native GTK bridge.
        for toolkit in ("qt5ct", "qt6ct"):
            path = directory / toolkit / f"{toolkit}.conf"
            if path.is_file():
                write_ini(path, {"Appearance": {"icon_theme": selected}})
    if shutil.which("gsettings"):
        subprocess.run([gsettings_command(), "set", "org.gnome.desktop.interface", "icon-theme", selected],
                       check=True)
    if os.environ.get("FLATPAK_ID") and shutil.which("flatpak-spawn"):
        command = ["flatpak-spawn", "--host", "flatpak"]
    elif shutil.which("flatpak"):
        command = ["flatpak"]
    else:
        command = []
    if command:
        subprocess.run([*command, "override", "--user", f"--env=ICON_THEME={selected}"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    broadcast_kde_theme_change((4,))


def sync_flatpak_theme(mode: str) -> None:
    theme = gtk_theme_name(mode)
    icons = desktop_icon_theme(mode)
    if os.environ.get("FLATPAK_ID") and shutil.which("flatpak-spawn"):
        command = ["flatpak-spawn", "--host", "flatpak"]
    elif shutil.which("flatpak"):
        command = ["flatpak"]
    else:
        return
    subprocess.run([*command, "override", "--user", f"--env=GTK_THEME={theme}", f"--env=ICON_THEME={icons}"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    root = HOME / ".var/app"
    if root.is_dir():
        for app in root.iterdir():
            bridge = app / "config/qt6ct/gtk3-palette.json"
            if bridge.is_file():
                values = qt_environment(mode)
                values["QT_GUI_GTK_JSON"] = str(bridge)
                values["GTK2_RC_FILES"] = str(app / "config/gtk-2.0/gtkrc")
                desktop = app / "config/avethy"
                plugins = desktop / "qt-plugins"
                if plugins.is_dir() and "QT_STYLE_OVERRIDE" in values:
                    values.update({"QT_PLUGIN_PATH": str(plugins),
                                   "AVETHY_QT_THEME": str(desktop / "palette.json"),
                                   "QT_QUICK_CONTROLS_CONF": str(desktop / "qtquickcontrols2.conf"),
                                   "QT_QUICK_CONTROLS_STYLE_PATH": str(plugins / "qml"),
                                   "QML_IMPORT_PATH": str(plugins / "qml"),
                                   "QML2_IMPORT_PATH": str(plugins / "qml")})
                assignments = [f"--env={key}={value}" for key, value in values.items()]
                subprocess.run([*command, "override", "--user", *assignments, app.name],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def restart_settings_portal() -> None:
    environment = os.environ.copy()
    environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"
    commands = [
        ["systemctl", "--user", "start", "hyprland-session.target"],
        # Stop the broker first so it drops its connection to the old backend,
        # then explicitly kill/reopen GTK and finally reopen the broker.
        ["systemctl", "--user", "stop", "xdg-desktop-portal.service"],
        ["systemctl", "--user", "stop", "xdg-desktop-portal-gtk.service"],
        ["systemctl", "--user", "start", "xdg-desktop-portal-gtk.service"],
        ["systemctl", "--user", "start", "xdg-desktop-portal.service"],
    ]
    if os.environ.get("FLATPAK_ID") and shutil.which("flatpak-spawn"):
        commands = [["flatpak-spawn", "--host", *command] for command in commands]
    elif not shutil.which("systemctl"):
        return
    for command in commands:
        try:
            subprocess.run(command, env=environment, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=True, timeout=10)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"material-palette: portal refresh failed: {error}", file=sys.stderr)


def nautilus_running(environment: dict[str, str]) -> bool:
    if not shutil.which("pgrep"):
        return False
    result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "nautilus"],
                            env=environment, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, check=False, timeout=3)
    return result.returncode == 0


def nautilus_locations(environment: dict[str, str]) -> list[str]:
    """Snapshot Nautilus's published folder URIs before quitting it."""
    if not shutil.which("gdbus"):
        return []
    try:
        result = subprocess.run([
            "gdbus", "call", "--session", "--dest", "org.gnome.Nautilus",
            "--object-path", "/org/freedesktop/FileManager1", "--method",
            "org.freedesktop.DBus.Properties.Get", "org.freedesktop.FileManager1",
            "OpenLocations",
        ], env=environment, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, check=False, timeout=3)
        # gdbus prints a GVariant tuple, e.g. (<['file:///home/user']>,).
        match = re.search(r"\[.*\]", result.stdout)
        locations = ast.literal_eval(match.group()) if match and result.returncode == 0 else []
        if isinstance(locations, list) and all(isinstance(uri, str) for uri in locations):
            return list(dict.fromkeys(locations))
    except (OSError, subprocess.SubprocessError, SyntaxError, ValueError):
        pass
    return []


def restart_gtk_desktop() -> None:
    """Reload GTK services and reopen an existing Nautilus fully detached."""
    environment = os.environ.copy()
    environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"
    restart_nautilus = False
    locations: list[str] = []
    if shutil.which("nautilus"):
        try:
            restart_nautilus = nautilus_running(environment)
            if restart_nautilus:
                locations = nautilus_locations(environment)
                subprocess.run(["nautilus", "-q"], env=environment,
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, check=True, timeout=5)
                # Quit is a D-Bus request. Wait for the old process to actually
                # exit so the launch cannot use the old CSS provider.
                deadline = time.monotonic() + 5
                while nautilus_running(environment):
                    if time.monotonic() >= deadline:
                        raise TimeoutError("Nautilus did not exit after nautilus -q")
                    time.sleep(0.1)
        except (OSError, subprocess.SubprocessError, TimeoutError) as error:
            restart_nautilus = False
            print(f"material-palette: Nautilus refresh failed: {error}", file=sys.stderr)
    restart_settings_portal()
    if restart_nautilus:
        try:
            # A separate session and closed stdio are the subprocess equivalent
            # of launching a shell job in the background and disowning it.
            subprocess.Popen(["nautilus", "--new-window", "--", *locations],
                             env=environment, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True, close_fds=True)
        except OSError as error:
            print(f"material-palette: Nautilus relaunch failed: {error}", file=sys.stderr)


def current_mode(requested: str | None = None) -> str:
    if requested in ("dark", "light"):
        return requested
    try:
        value = subprocess.check_output([gsettings_command(), "get", "org.gnome.desktop.interface", "color-scheme"],
                                        text=True, stderr=subprocess.DEVNULL)
        return "dark" if "dark" in value else "light"
    except (OSError, subprocess.SubprocessError):
        return "dark"


def read_roles() -> dict[str, dict[str, str]]:
    result = {"light": {}, "dark": {}}
    if not PALETTE_FILE.exists():
        return result
    for line in PALETTE_FILE.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^(light|dark)\.([a-z_]+)=(#[0-9a-fA-F]{6})$", line)
        if match:
            result[match.group(1)][match.group(2)] = match.group(3)
    return result


def startup(mode: str) -> None:
    """Restore the complete theme before the shell starts launching apps."""
    legacy = HOME / ".cache/quickshell/material-palette.ini"
    if not PALETTE_FILE.exists() and legacy.is_file():
        atomic_write(PALETTE_FILE, "# Avethy palette\nname=Avethy\n" + legacy.read_text(encoding="utf-8"))
    roles = read_roles()
    source = wallpaper_from_config()
    cached_source = None
    if PALETTE_FILE.is_file():
        for line in PALETTE_FILE.read_text(encoding="utf-8").splitlines():
            if line.startswith("source="):
                cached_source = line[7:]
                break
    required = material_roles(tonal_palette(FALLBACK_SEED))[mode].keys()
    if not all(required <= roles[appearance].keys() for appearance in ("light", "dark")) or source != cached_source:
        generate(source, mode)
    else:
        apply(roles, mode)


def apply(roles: dict[str, dict[str, str]], mode: str) -> None:
    role = roles[mode]
    if not role:
        raise RuntimeError("palette has not been generated yet")
    install_gtk(role, mode)
    install_qt(role, mode)
    install_flatpak_configs(role, mode)
    sync_qt_gtk_environment(role, mode)
    set_gsettings(mode, role)
    sync_flatpak_theme(mode)
    broadcast_kde_theme_change()
    # Hyprland gets the same primary/outline colors immediately.
    if shutil.which("hyprctl"):
        for key, value in (("active_border", role["primary"]), ("inactive_border", role["outline_variant"])):
            rgba = "rgba(" + value[1:] + ("ff" if key == "active_border" else "aa") + ")"
            subprocess.run(["hyprctl", "keyword", f"general:col.{key}", rgba],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    restart_gtk_desktop()


def generate(source: str, mode: str, preview_dir: Path | None = None) -> dict[str, dict[str, str]]:
    if not source:
        print("material-palette: no wallpaper configured; using fallback seed", file=sys.stderr)
    pixels = wallpaper_pixels(source) if source else []
    seed = dominant_seed(pixels)
    tones = tonal_palette(seed)
    roles = material_roles(tones)
    if preview_dir is None:
        write_palette(source, tones, roles)
        apply(roles, mode)
    else:
        write_preview(preview_dir, source, tones, roles)
    print(f"Avethy: {hex_color(seed)} from {source or 'fallback'} ({mode})", file=sys.stderr)
    return roles


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", help="image/video path or URL; defaults to config.ini")
    parser.add_argument("--mode", choices=("dark", "light"))
    parser.add_argument("--apply-only", action="store_true", help="reapply the cached palette")
    parser.add_argument("--startup", action="store_true", help="force Avethy at shell startup, generating missing or changed wallpaper colors")
    parser.add_argument("--icons-only", action="store_true", help="sync the configured icon pack to GTK and Qt without applying wallpaper colors")
    parser.add_argument("--config", type=Path, help="config.ini to read with --icons-only")
    parser.add_argument("--shell-environment", action="store_true", help="print safely quoted theme exports for the launcher")
    parser.add_argument("--preview-dir", type=Path,
                        help="write light/dark theme files here without applying them")
    args = parser.parse_args()
    if args.icons_only and (args.startup or args.apply_only or args.preview_dir or args.source is not None or args.shell_environment):
        parser.error("--icons-only cannot be combined with palette options")
    if args.config and not args.icons_only:
        parser.error("--config requires --icons-only")
    if args.preview_dir and (args.apply_only or args.startup or args.shell_environment):
        parser.error("--preview-dir cannot be combined with apply/startup/environment options")
    if args.startup and args.apply_only:
        parser.error("--startup cannot be combined with --apply-only")
    mode = current_mode(args.mode)
    if args.shell_environment and not args.startup:
        parser.error("--shell-environment requires --startup")
    if args.preview_dir:
        generate(args.source if args.source is not None else wallpaper_from_config(), mode, args.preview_dir)
    else:
        CACHE.mkdir(parents=True, exist_ok=True)
        with (CACHE / "theme.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if args.icons_only:
                apply_icon_theme(mode, args.config)
            elif args.startup:
                startup(mode)
            elif args.apply_only:
                apply(read_roles(), mode)
            else:
                generate(args.source if args.source is not None else wallpaper_from_config(), mode)
    if args.shell_environment:
        for key, value in qt_environment(mode).items():
            print(f"export {key}={shlex.quote(value)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
