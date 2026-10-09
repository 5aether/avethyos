#!/usr/bin/env python3
"""Tests for the EDID monitor-name parser.

The descriptor offsets are pinned here rather than left to be discovered
against real hardware: the tag byte was read one position early during
development, which produced no name at all rather than an error, so the bug
was silent.
"""
import importlib.util
import pathlib
import unittest

MODULE = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "monitor-names.py"

spec = importlib.util.spec_from_file_location("monitor_names", MODULE)
monitor_names = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor_names)


def edid_with_descriptor(tag: int, name: str = "") -> bytes:
    """A 128-byte EDID carrying one 18-byte descriptor block at offset 54."""
    edid = bytearray(128)
    edid[0:3] = b"\x01\x02\x03"  # non-zero, so it is not a dead connector
    edid[54] = 0x00
    edid[55] = 0x00
    edid[56] = 0x00
    edid[57] = tag
    edid[58] = 0x00
    if name:
        edid[59:59 + len(name)] = name.encode("latin-1")
        edid[59 + len(name)] = 0x0A
    return bytes(edid)


class MonitorName(unittest.TestCase):
    def test_reads_monitor_name_descriptor(self):
        self.assertEqual(monitor_names.monitor_name(edid_with_descriptor(0xFC, "LG ULTRAGEAR")),
                         "LG ULTRAGEAR")

    def test_reads_a_name_at_the_last_block(self):
        # Offset 108 is the final descriptor block, so it also proves the loop
        # covers the whole descriptor area.
        edid = bytearray(128)
        edid[0:3] = b"\x01\x02\x03"
        edid[108] = 0x00
        edid[109] = 0x00
        edid[110] = 0x00
        edid[111] = 0xFC
        edid[112] = 0x00
        edid[113:117] = b"ACER"
        edid[117] = 0x0A
        self.assertEqual(monitor_names.monitor_name(bytes(edid)), "ACER")

    def test_ignores_a_serial_descriptor_only(self):
        # A serial number is not a label, so it must not become the name.
        self.assertEqual(monitor_names.monitor_name(edid_with_descriptor(0xFF, "1234")), "")

    def test_returns_empty_for_an_unused_descriptor(self):
        self.assertEqual(monitor_names.monitor_name(edid_with_descriptor(0x10)), "")

    def test_returns_empty_for_all_zero_edid(self):
        self.assertEqual(monitor_names.monitor_name(bytes(128)), "")

    def test_returns_empty_for_a_truncated_edid(self):
        self.assertEqual(monitor_names.monitor_name(bytes(40)), "")

    def test_strips_padding_and_control_bytes(self):
        # Overwrite the whole name field with a NUL, spaces, the name and a
        # trailing newline, which is how panels pad the descriptor.
        edid = bytearray(edid_with_descriptor(0xFC, "LG"))
        edid[59:72] = b"\x00 ULTRAGEAR \x0a"
        self.assertEqual(monitor_names.monitor_name(bytes(edid)), "ULTRAGEAR")


if __name__ == "__main__":
    unittest.main()
