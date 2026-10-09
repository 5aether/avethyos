#!/usr/bin/env python3
"""Print the dominant color of an MPRIS cover-art URL."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


def load_palette_module():
    path = Path(__file__).with_name("material-palette.py")
    spec = importlib.util.spec_from_file_location("material_palette", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load material-palette.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].strip():
        return 2

    palette = load_palette_module()
    source = palette.local_source(sys.argv[1].strip())
    raw = palette.decode_frame(source)
    pixels = [tuple(raw[i:i + 3]) for i in range(0, len(raw) - 2, 12)]
    if not pixels:
        return 1

    print(palette.hex_color(palette.dominant_seed(pixels)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
