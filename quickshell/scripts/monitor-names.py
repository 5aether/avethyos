#!/usr/bin/env python3
"""Prints "connector<TAB>name" for every connected display.

ddcutil reports a DRM connector, which names the port
rather than the panel. The friendly name lives in the EDID "monitor name"
descriptor (tag 0xFC), so it is read straight from sysfs: that works on every
vendor, needs no extra package, and does not depend on ddcutil being present.

A connector with no EDID, or one with no usable name descriptor, is skipped so
the caller can fall back to whatever ddcutil reported.
"""
import pathlib
import sys


def monitor_name(edid: bytes) -> str:
    """The EDID 0xFC monitor-name descriptor, or "" if there is not one.

    Only the 0xFC tag is accepted. The 0xFF tag holds a serial number, which is
    not a label a person recognises, so it is ignored in favour of the caller's
    own fallback.
    """
    # 18-byte descriptor blocks start at byte offset 54. A name block is
    # 00 00 00 fc 00 followed by up to 13 characters, newline-terminated.
    for offset in range(54, 126, 18):
        block = edid[offset:offset + 18]
        if len(block) < 18 or block[0:3] != b"\x00\x00\x00":
            continue
        if block[3] != 0xFC:
            continue
        name = block[4:].decode("latin-1")
        # The block is space-padded, newline-terminated, and can carry a NUL
        # where a control byte was expected.
        name = name.replace("\n", "").replace("\r", "").replace("\x00", "").strip()
        if name:
            return name
    return ""


def main() -> int:
    drm = pathlib.Path("/sys/class/drm")
    if not drm.is_dir():
        return 0
    for edid in sorted(drm.glob("card*-*/edid")):
        connector = edid.parent.name
        if connector.endswith("-Writeback-1"):
            continue
        try:
            data = edid.read_bytes()
        except OSError:
            continue
        # A disconnected port reports an all-zero EDID.
        if len(data) < 126 or not any(data):
            continue
        name = monitor_name(data)
        if not name:
            continue
        print(f"{connector}\t{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
