#!/usr/bin/env python3
"""Quickshell-owned, capture-safe night light. No daemon or extra package.

Only registry, output, sync and hyprland-ctm-control-v1 messages are needed,
so this small Wayland client uses Python's Unix sockets directly. None of
these interfaces transfers file descriptors. Wire integers are native-endian;
CTM components use Wayland's signed 24.8 fixed-point representation.
Protocol: https://github.com/hyprwm/hyprland-protocols/blob/main/protocols/hyprland-ctm-control-v1.xml

stdin: newline-delimited {"enabled": bool, "temperature": int}.
stdout: newline-delimited status, acknowledged after compositor sync.
Closing stdin/the process releases CTM ownership and restores neutral colors.
"""

import json
import math
import os
import select
import socket
import struct
import sys
import time
from pathlib import Path

CTM_INTERFACE = "hyprland_ctm_control_manager_v1"
UINT = struct.Struct("=I")
HEADER = struct.Struct("=II")


def wire_string(value):
    data = value.encode() + b"\0"
    return UINT.pack(len(data)) + data + b"\0" * (-len(data) % 4)


def read_string(data, offset):
    length = UINT.unpack_from(data, offset)[0]
    start = offset + 4
    return data[start:start + length - 1].decode(), start + ((length + 3) & ~3)


def temperature_rgb(kelvin):
    kelvin = max(1000, min(6500, int(kelvin)))
    if kelvin == 6500:
        return (1.0, 1.0, 1.0)
    temperature = kelvin / 100
    green = 99.4708025861 * math.log(temperature) - 161.1195681661
    blue = (0 if temperature <= 19 else
            138.5177312231 * math.log(temperature - 10) - 305.0447927307)
    return (1.0, max(0, min(255, green)) / 255,
            max(0, min(255, blue)) / 255)


def clear_legacy_shader(using_lua=False):
    """Remove only our old shader; leave unrelated user shaders untouched."""
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature:
        return
    ipc_path = runtime / "hypr" / signature / ".socket.sock"

    def request(message):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ipc:
            ipc.settimeout(2)
            ipc.connect(str(ipc_path))
            ipc.sendall(message.encode())
            chunks = []
            while chunk := ipc.recv(4096):
                chunks.append(chunk)
            return b"".join(chunks).decode()

    option = json.loads(request("j/getoption decoration:screen_shader"))
    old_paths = {str(runtime / f"quickshell-nightlight-{name}.frag")
                 for name in ("a", "b")}
    if option.get("str") in old_paths:
        command = ('eval hl.config({ ["decoration.screen_shader"] = "" })'
                   if using_lua else "keyword decoration:screen_shader ")
        if request(command).strip() != "ok":
            raise RuntimeError("Could not remove the previous night-light shader")


class NightLight:
    def __init__(self, connection):
        self.socket = connection
        self.socket.settimeout(2)
        self.buffer = b""
        self.next_id = 2
        self.free_ids = []
        self.registry = self.new_id()
        self.outputs = {}
        self.objects = {}
        self.manager_global = None
        self.manager = None
        self.blocked = False
        self.waiting = None
        self.dirty = False
        self.enabled = False
        self.temperature = 6500
        self.send(1, 1, UINT.pack(self.registry))  # wl_display.get_registry
        self.roundtrip()
        self.dirty = False

    @property
    def available(self):
        # v2 reports exclusive-owner conflicts instead of silently ignoring us.
        return self.manager_global is not None

    def new_id(self):
        if self.free_ids:
            return self.free_ids.pop()
        result = self.next_id
        self.next_id += 1
        return result

    def send(self, object_id, opcode, payload=b""):
        self.socket.sendall(HEADER.pack(object_id, ((8 + len(payload)) << 16) | opcode) + payload)

    def bind(self, name, interface, version):
        object_id = self.new_id()
        self.send(self.registry, 0, UINT.pack(name) + wire_string(interface)
                  + struct.pack("=II", version, object_id))
        return object_id

    def roundtrip(self):
        callback = self.new_id()
        self.waiting = callback
        self.send(1, 0, UINT.pack(callback))  # wl_display.sync
        deadline = time.monotonic() + 2
        while self.waiting is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.socket], [], [], remaining)[0]:
                raise TimeoutError("Compositor did not acknowledge night light")
            self.receive()

    def receive(self):
        chunk = self.socket.recv(65536)
        if not chunk:
            raise ConnectionError("Wayland display disconnected")
        self.buffer += chunk
        while len(self.buffer) >= 8:
            object_id, message = HEADER.unpack_from(self.buffer)
            size, opcode = message >> 16, message & 0xFFFF
            if size < 8 or size % 4:
                raise RuntimeError("Invalid Wayland event")
            if len(self.buffer) < size:
                break
            payload = self.buffer[8:size]
            self.buffer = self.buffer[size:]
            self.event(object_id, opcode, payload)

    def event(self, object_id, opcode, payload):
        if object_id == 1:
            if opcode == 0:  # wl_display.error
                message, _ = read_string(payload, 8)
                raise RuntimeError(message)
            if opcode == 1:  # wl_display.delete_id: now safe to reuse
                self.free_ids.append(UINT.unpack(payload)[0])
        elif object_id == self.registry:
            if opcode == 0:  # registry.global
                name = UINT.unpack_from(payload)[0]
                interface, offset = read_string(payload, 4)
                version = UINT.unpack_from(payload, offset)[0]
                if interface == CTM_INTERFACE and version >= 2:
                    self.manager_global = name
                elif interface == "wl_output":
                    version = min(version, 3)
                    output = self.bind(name, interface, version)
                    self.outputs[name] = output
                    self.objects[output] = version
                    self.dirty = True
            elif opcode == 1:  # registry.global_remove
                name = UINT.unpack(payload)[0]
                if name == self.manager_global:
                    raise ConnectionError("Display color control was removed")
                output = self.outputs.pop(name, None)
                if output is not None:
                    if self.objects.pop(output) >= 3:
                        self.send(output, 0)  # wl_output.release
                    self.dirty = True
        elif object_id == self.manager and opcode == 0:  # manager.blocked
            self.blocked = True
        elif object_id == self.waiting and opcode == 0:  # callback.done
            self.waiting = None
        # Geometry/mode/scale/done output events are irrelevant to CTM.

    def status(self, event="applied", error=""):
        return {"event": event, "available": self.available,
                "active": self.enabled and bool(self.outputs) and self.manager is not None,
                "temperature": self.temperature, "error": error}

    def release(self):
        if self.manager is not None:
            self.send(self.manager, 2)  # manager.destroy resets CTMs
            self.manager = None
            self.roundtrip()

    def apply(self, enabled, temperature):
        self.enabled = bool(enabled)
        self.temperature = max(1000, min(6500, int(temperature)))
        self.dirty = False
        if not self.enabled:
            self.release()
            return self.status()
        if not self.available:
            return self.status(error="Hyprland display color control v2 is unavailable")
        if self.manager is None:
            self.blocked = False
            self.manager = self.bind(self.manager_global, CTM_INTERFACE, 2)
            self.roundtrip()
            if self.blocked:
                self.release()
                return self.status(error="Display color control is in use by another application")
        red, green, blue = (round(value * 256) for value in temperature_rgb(self.temperature))
        matrix = struct.pack("=9i", red, 0, 0, 0, green, 0, 0, 0, blue)
        for output in self.outputs.values():
            self.send(self.manager, 0, UINT.pack(output) + matrix)
        self.send(self.manager, 1)  # commit all outputs together
        self.roundtrip()
        return self.status()


def emit(status):
    print(json.dumps(status), flush=True)


def run():
    display = os.environ.get("WAYLAND_DISPLAY")
    if not display:
        raise RuntimeError("Night light requires a Wayland session")
    display_path = Path(display)
    if not display_path.is_absolute():
        display_path = Path(os.environ["XDG_RUNTIME_DIR"]) / display_path
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.connect(str(display_path))
        light = NightLight(connection)
        clear_legacy_shader("--lua" in sys.argv)
        emit(light.status("ready"))
        input_buffer = b""
        try:
            while True:
                readable, _, _ = select.select([connection, sys.stdin.buffer], [], [])
                if connection in readable:
                    light.receive()
                if sys.stdin.buffer in readable:
                    chunk = os.read(sys.stdin.fileno(), 65536)
                    if not chunk:
                        return
                    input_buffer += chunk
                    if len(input_buffer) > 65536:
                        raise ValueError("Night-light command is too large")
                    # Coalesce rapid slider updates before committing a frame.
                    commands = []
                    while b"\n" in input_buffer:
                        line, input_buffer = input_buffer.split(b"\n", 1)
                        if line.strip():
                            commands.append(json.loads(line))
                    if commands:
                        command = commands[-1]
                        emit(light.apply(command["enabled"], command["temperature"]))
                if light.dirty:
                    emit(light.apply(light.enabled, light.temperature))
        finally:
            light.release()


if __name__ == "__main__":
    try:
        run()
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        emit({"event": "error", "available": False, "active": False, "error": str(error)})
        sys.exit(1)
