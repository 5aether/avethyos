"""Exercise the CTM wire protocol against a small independent compositor."""
import importlib.util
import socket
import struct
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "night_light", Path(__file__).resolve().parents[1] / "scripts/night-light.py")
night_light = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(night_light)


def uint(value):
    return struct.pack("=I", value)


def string(value):
    data = value.encode() + b"\0"
    return uint(len(data)) + data + b"\0" * (-len(data) % 4)


class Compositor:
    def __init__(self, version=2):
        self.client, self.server = socket.socketpair()
        self.version = version
        self.registry = None
        self.manager = None
        self.blocked = False
        self.bindings = {}
        self.matrices = {}
        self.committed = {}
        self.commits = 0
        self.destroyed = 0
        self.failure = None
        self.event_lock = threading.Lock()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def event(self, target, opcode, data=b""):
        message = struct.pack("=II", target, ((len(data) + 8) << 16) | opcode) + data
        # Split even the header to exercise buffered event parsing.
        # Hotplug events arrive from the test thread while sync callbacks are
        # sent by serve(). Keep each fragmented protocol message contiguous.
        with self.event_lock:
            self.server.sendall(message[:3])
            self.server.sendall(message[3:])

    def advertise(self, name, interface, version):
        self.event(self.registry, 0, uint(name) + string(interface) + uint(version))

    def exact(self, size):
        data = b""
        while len(data) < size:
            chunk = self.server.recv(size - len(data))
            if not chunk:
                raise EOFError
            data += chunk
        return data

    def serve(self):
        try:
            while True:
                target, header = struct.unpack("=II", self.exact(8))
                opcode = header & 0xFFFF
                data = self.exact((header >> 16) - 8)
                if target == 1 and opcode == 1:
                    self.registry = struct.unpack("=I", data)[0]
                    if self.version:
                        self.advertise(10, "hyprland_ctm_control_manager_v1", self.version)
                    self.advertise(20, "wl_output", 4)
                    self.advertise(21, "wl_output", 4)
                elif target == 1 and opcode == 0:
                    callback = struct.unpack("=I", data)[0]
                    self.event(callback, 0, uint(0))
                    self.event(1, 1, uint(callback))
                elif target == self.registry:
                    name, size = struct.unpack_from("=II", data)
                    interface = data[8:8 + size - 1].decode()
                    offset = 8 + ((size + 3) & ~3)
                    version, object_id = struct.unpack_from("=II", data, offset)
                    self.bindings[object_id] = (name, interface, version)
                    if interface == "hyprland_ctm_control_manager_v1":
                        self.manager = object_id
                        if self.blocked:
                            self.event(object_id, 0)
                elif target == self.manager:
                    if opcode == 0:
                        output, *matrix = struct.unpack("=I9i", data)
                        self.matrices[self.bindings[output][0]] = tuple(matrix)
                    elif opcode == 1:
                        self.committed = dict(self.matrices)
                        self.commits += 1
                    elif opcode == 2:
                        if not self.blocked:
                            self.matrices.clear()
                            self.committed.clear()
                        self.destroyed += 1
                        self.manager = None
                        self.event(1, 1, uint(target))
                elif self.bindings[target][1] == "wl_output" and opcode == 0:
                    self.event(1, 1, uint(target))
        except (EOFError, ConnectionError):
            pass
        except Exception as error:
            self.failure = error

    def close(self):
        self.client.close()
        self.thread.join(2)
        self.server.close()
        if self.failure:
            raise self.failure


class NightLightTests(unittest.TestCase):
    def connect(self, version=2):
        compositor = Compositor(version)
        self.addCleanup(compositor.close)
        return compositor, night_light.NightLight(compositor.client)

    def test_disabled_does_not_claim_control_and_neutral_is_identity(self):
        compositor, light = self.connect()
        self.assertFalse(light.apply(False, 4500)["active"])
        self.assertIsNone(compositor.manager)
        self.assertTrue(light.apply(True, 6500)["active"])
        identity = (256, 0, 0, 0, 256, 0, 0, 0, 256)
        self.assertEqual(compositor.committed, {20: identity, 21: identity})
        self.assertFalse(light.apply(False, 4500)["active"])
        self.assertEqual(compositor.committed, {})
        self.assertEqual(compositor.destroyed, 1)

    def test_temperature_updates_all_outputs_and_hotplug_inherits_it(self):
        compositor, light = self.connect()
        light.apply(True, 2500)
        warm = compositor.committed[20]
        self.assertEqual(warm, compositor.committed[21])
        self.assertGreater(warm[0], warm[4])
        self.assertGreater(warm[4], warm[8])
        compositor.advertise(22, "wl_output", 4)
        light.roundtrip()
        self.assertTrue(light.dirty)
        light.apply(light.enabled, light.temperature)
        self.assertEqual(compositor.committed[22], warm)
        compositor.event(compositor.registry, 1, uint(21))
        light.roundtrip()
        self.assertNotIn(21, light.outputs)
        light.apply(True, 6500)
        self.assertEqual(compositor.committed[20][8], 256)
        light.release()
        self.assertEqual(compositor.committed, {})

    def test_ownership_conflict_is_reported_without_committing_and_can_retry(self):
        compositor, light = self.connect()
        compositor.blocked = True
        status = light.apply(True, 4000)
        self.assertFalse(status["active"])
        self.assertIn("another application", status["error"])
        self.assertEqual(compositor.commits, 0)
        compositor.blocked = False
        self.assertTrue(light.apply(True, 4000)["active"])
        self.assertEqual(compositor.commits, 1)
        light.release()

    def test_unsupported_compositor_never_claims_control(self):
        for version in (0, 1):
            compositor, light = self.connect(version)
            status = light.apply(True, 4000)
            self.assertFalse(status["available"])
            self.assertFalse(status["active"])
            self.assertIsNone(compositor.manager)

    def test_kelvin_is_clamped_and_blue_decreases_with_warmth(self):
        self.assertEqual(night_light.temperature_rgb(9000), (1, 1, 1))
        self.assertEqual(night_light.temperature_rgb(0), night_light.temperature_rgb(1000))
        blues = [night_light.temperature_rgb(k)[2] for k in range(1000, 6501, 100)]
        self.assertEqual(blues, sorted(blues))

    def test_migration_preserves_other_shaders_and_clears_only_owned_paths(self):
        for shader, expected in (("/home/user/custom.frag", 1),
                                 ("/tmp/runtime/quickshell-nightlight-a.frag", 2)):
            with self.subTest(shader=shader):
                calls = []
                class Ipc:
                    def __enter__(self):
                        self.read = False
                        return self
                    def __exit__(self, *args):
                        pass
                    def settimeout(self, value):
                        pass
                    def connect(self, value):
                        pass
                    def sendall(self, data):
                        calls.append(data.decode())
                    def recv(self, size):
                        if self.read:
                            return b""
                        self.read = True
                        if len(calls) == 1:
                            return ('{"str": "' + shader + '"}').encode()
                        return b"ok"
                with patch.dict("os.environ", XDG_RUNTIME_DIR="/tmp/runtime",
                                HYPRLAND_INSTANCE_SIGNATURE="test"), \
                        patch.object(night_light.socket, "socket", side_effect=lambda *a: Ipc()):
                    night_light.clear_legacy_shader()
                self.assertEqual(len(calls), expected)
                if expected == 2:
                    self.assertEqual(calls[-1], "keyword decoration:screen_shader ")


if __name__ == "__main__":
    unittest.main()
