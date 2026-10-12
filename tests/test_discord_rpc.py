"""Real Unix streams in temporary runtime directories; never modify the host."""

import asyncio
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "system_files/usr/libexec/avethyos-discord-rpc"
LOADER = importlib.machinery.SourceFileLoader("discord_bridge", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
rpc = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(rpc)


def frame(opcode, payload):
    return struct.pack("<II", opcode, len(payload)) + payload


class KernelSocketIdentityTests(unittest.TestCase):
    def test_raw_kernel_device_layout_and_32bit_inode(self):
        # UNIX_DIAG_VFS exports raw kernel s_dev (MKDEV in linux/kdev_t.h),
        # whereas stat st_dev uses the userspace encoding returned by makedev.
        for major, minor, kernel_device in ((0, 47, 47), (8, 513, 0x800201),
                                             (259, 4097, 0x10301001)):
            with self.subTest(major=major, minor=minor):
                info = SimpleNamespace(st_mode=stat.S_IFSOCK, st_dev=os.makedev(major, minor),
                                       st_ino=0x100001234)
                path = SimpleNamespace(lstat=lambda: info)
                self.assertTrue(rpc.real_socket(path, {(kernel_device, 0x1234)}))
                self.assertFalse(rpc.real_socket(path, {(kernel_device, 0x1235)}))


class DiscordRPCTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="rpc-")
        self.runtime = Path(self.temporary.name)
        self.bridge = rpc.Bridge(self.runtime)
        self.providers = []
        self.tasks = set()
        self.received = bytearray()
        await self.bridge.start()

    async def asyncTearDown(self):
        await self.bridge.stop()
        for provider in self.providers:
            provider.close()
            await provider.wait_closed()
        for task in tuple(self.tasks):
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        self.temporary.cleanup()

    async def provider(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)

        async def echo(reader, writer):
            task = asyncio.current_task()
            self.tasks.add(task)
            try:
                while data := await reader.read(4096):
                    self.received.extend(data)
                    writer.write(data)
                    await writer.drain()
            finally:
                writer.close()
                await writer.wait_closed()
                self.tasks.discard(task)

        server = await asyncio.start_unix_server(echo, path=str(path))
        self.providers.append(server)
        return server

    def sandbox(self, app):
        private = self.runtime / ".flatpak" / app / "xdg-run"
        private.mkdir(parents=True, exist_ok=True)
        # Model Flatpak's narrow bind of the proxy directory, without mounting
        # anything or adding permissions to installed host applications.
        (private / "discord-rpc").symlink_to(self.bridge.directory)
        return private

    async def roundtrip(self, path, payload=b"RPC payload\x00\xff"):
        reader, writer = await asyncio.open_unix_connection(str(path))
        writer.write(payload)
        await writer.drain()
        result = await asyncio.wait_for(reader.readexactly(len(payload)), 2)
        self.assertEqual(payload, result)
        writer.close()
        await writer.wait_closed()

    async def test_native_source_to_unknown_flatpak_client_preserves_all_rpc_bytes(self):
        socket = self.runtime / ".flatpak/example.NewClient/xdg-run/discord-ipc-7"
        await self.provider(socket)
        self.bridge.refresh()
        self.assertEqual(socket, self.bridge.targets[7])
        payload = (frame(0, b'{"v":1,"client_id":"steam-game"}')
                   + frame(1, json.dumps({"cmd": "SET_ACTIVITY", "args": {
                       "activity": {"type": 2, "details": "Media player", "state": "song"}}}).encode())
                   + frame(3, bytes(range(256)) * 600)
                   + frame(4, b"pong") + frame(2, b"close"))
        reader, writer = await asyncio.open_unix_connection(str(self.runtime / "discord-ipc-7"))
        # Unix streams may split headers and JSON at any byte boundary.
        for offset in range(0, len(payload), 319):
            writer.write(payload[offset:offset + 319])
            await writer.drain()
        result = await asyncio.wait_for(reader.readexactly(len(payload)), 2)
        self.assertEqual(payload, result)
        self.assertEqual(payload, self.received)
        writer.close()
        await writer.wait_closed()

    async def test_flatpak_source_opened_first_reaches_later_native_client(self):
        consumer = self.sandbox("example.Player")
        self.bridge.refresh()
        self.assertFalse((consumer / "discord-ipc-0").exists())
        native = self.runtime / "discord-ipc-0"
        await self.provider(native)
        before = native.lstat()
        self.bridge.refresh()
        self.assertFalse(native.is_symlink())
        self.assertEqual(before.st_ino, native.lstat().st_ino)
        await self.roundtrip(consumer / "discord-ipc-0")

    async def test_flatpak_source_reaches_flatpak_export_directory(self):
        consumer = self.sandbox("example.Steam")
        socket = self.runtime / "app/example.AnotherDiscord/discord-ipc-4"
        await self.provider(socket)
        self.bridge.refresh()
        await self.roundtrip(consumer / "discord-ipc-4")

    async def test_multiple_clients_are_assigned_separate_stable_slots(self):
        native = self.runtime / "discord-ipc-0"
        first = self.runtime / "app/example.A/discord-ipc-0"
        second = self.runtime / "app/example.B/discord-ipc-0"
        for path in (native, first, second):
            await self.provider(path)
        self.bridge.refresh()
        self.assertEqual({0: native, 1: first, 2: second}, self.bridge.targets)
        self.bridge.refresh()
        self.assertEqual({0: native, 1: first, 2: second}, self.bridge.targets)
        for slot in (1, 2):
            await self.roundtrip(self.runtime / f"discord-ipc-{slot}")

    async def test_native_socket_replacing_bridge_link_keeps_its_slot(self):
        exported = self.runtime / "app/example.A/discord-ipc-0"
        await self.provider(exported)
        self.bridge.refresh()
        native = self.runtime / "discord-ipc-0"
        native.unlink()
        await self.provider(native)
        self.bridge.refresh()
        self.assertEqual({0: native, 1: exported}, self.bridge.targets)
        self.assertFalse(native.is_symlink())
        await self.roundtrip(self.runtime / "discord-ipc-1")

    async def test_closed_client_socket_is_not_a_live_provider(self):
        socket = self.runtime / "app/example.A/discord-ipc-0"
        server = await self.provider(socket)
        self.bridge.refresh()
        server.close()
        await server.wait_closed()
        self.bridge.refresh()
        self.assertEqual({}, self.bridge.targets)
        self.assertFalse(os.path.lexists(self.runtime / "discord-ipc-0"))

    async def test_client_restart_keeps_directory_mount_and_reconnects(self):
        consumer = self.sandbox("example.Steam")
        socket = self.runtime / "app/example.A/discord-ipc-0"
        server = await self.provider(socket)
        self.bridge.refresh()
        directory_inode = self.bridge.directory.stat().st_ino
        await self.roundtrip(consumer / "discord-ipc-0")
        server.close()
        await server.wait_closed()
        self.bridge.refresh()
        socket.unlink(missing_ok=True)
        await self.provider(socket)
        self.bridge.refresh()
        self.assertEqual(directory_inode, self.bridge.directory.stat().st_ino)
        await self.roundtrip(consumer / "discord-ipc-0", b"after restart")

    async def test_bridge_restart_preserves_directory_and_ignores_its_links(self):
        socket = self.runtime / "app/example.A/discord-ipc-0"
        await self.provider(socket)
        self.bridge.refresh()
        inode = self.bridge.directory.stat().st_ino
        await self.bridge.stop()
        self.bridge = rpc.Bridge(self.runtime)
        await self.bridge.start()
        self.assertEqual(inode, self.bridge.directory.stat().st_ino)
        self.assertEqual({0: socket}, self.bridge.targets)
        await self.roundtrip(self.runtime / "discord-ipc-0")

    async def test_user_links_files_and_symlink_loops_are_preserved(self):
        own_link = self.runtime / "discord-ipc-0"
        own_link.symlink_to("discord-ipc-0")
        own_file = self.runtime / "discord-ipc-1"
        own_file.write_text("keep me")
        socket = self.runtime / "app/example.A/discord-ipc-0"
        await self.provider(socket)
        self.bridge.refresh()
        self.assertEqual("discord-ipc-0", os.readlink(own_link))
        self.assertEqual("keep me", own_file.read_text())
        self.assertEqual({2: socket}, self.bridge.targets)
        await self.roundtrip(self.runtime / "discord-ipc-2")

    async def test_only_stale_links_from_legacy_image_are_removed(self):
        stale = self.runtime / "discord-ipc-0"
        stale.symlink_to(".flatpak/com.discordapp.Discord/xdg-run/discord-ipc-0")
        user_link = self.runtime / "discord-ipc-1"
        user_link.symlink_to(".flatpak/example.Mine/xdg-run/discord-ipc-1")
        self.bridge.refresh()
        self.assertFalse(os.path.lexists(stale))
        self.assertTrue(user_link.is_symlink())

    async def test_half_close_delivers_pending_provider_bytes(self):
        socket = self.runtime / "app/example.A/discord-ipc-0"
        await self.provider(socket)
        self.bridge.refresh()
        reader, writer = await asyncio.open_unix_connection(str(self.runtime / "discord-ipc-0"))
        writer.write(b"final bytes")
        await writer.drain()
        writer.write_eof()
        self.assertEqual(b"final bytes", await asyncio.wait_for(reader.read(), 2))
        writer.close()
        await writer.wait_closed()

    @unittest.skipUnless(shutil.which("bwrap"), "bubblewrap is unavailable")
    async def test_client_created_inside_sandbox_is_discovered_by_inode(self):
        private = self.runtime / ".flatpak/example.Discord/xdg-run"
        private.mkdir(parents=True)
        sandbox_runtime = f"/run/user/{os.getuid()}"
        code = '''
import socket, sys
server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1] + "/discord-ipc-0")
server.listen()
print("ready", flush=True)
channel, _ = server.accept()
while data := channel.recv(4096):
    channel.sendall(data)
channel.close()
server.close()
'''
        child = await asyncio.create_subprocess_exec(
            "bwrap", "--unshare-user", "--die-with-parent", "--ro-bind", "/", "/",
            "--tmpfs", "/run", "--bind", str(private), sandbox_runtime,
            "--", sys.executable, "-c", code, sandbox_runtime,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            ready = await asyncio.wait_for(child.stdout.readline(), 2)
            if not ready:
                error = (await child.stderr.read()).decode()
                if "namespace" in error or "Operation not permitted" in error:
                    self.skipTest(error.strip())
                self.fail(error)
            self.assertEqual(b"ready\n", ready)
            self.bridge.refresh()
            self.assertEqual({0: private / "discord-ipc-0"}, self.bridge.targets)
            await self.roundtrip(self.runtime / "discord-ipc-0")
            self.assertEqual(0, await asyncio.wait_for(child.wait(), 2))
            self.bridge.refresh()
            self.assertEqual({}, self.bridge.targets)
        finally:
            if child.returncode is None:
                child.terminate()
                await child.wait()

    @unittest.skipUnless(shutil.which("bwrap"), "bubblewrap is unavailable")
    async def test_readonly_sandbox_mount_survives_late_client_and_restart(self):
        # The user tmpfiles service has provisioned the directory, but the RPC
        # helper itself need not be running when this application starts.
        await self.bridge.stop()
        self.bridge = rpc.Bridge(self.runtime)
        private = self.runtime / ".flatpak/example.Source/xdg-run"
        private.mkdir(parents=True)
        (private / "discord-rpc").mkdir()
        sandbox_runtime = f"/run/user/{os.getuid()}"
        code = '''
import os, socket, sys, time
runtime = sys.argv[1]
try:
    with open(runtime + "/discord-rpc/permission-check", "w"):
        pass
except OSError:
    print("readonly", flush=True)
else:
    raise SystemExit("proxy mount should be readonly")
for message in (b"first", b"restarted"):
    for attempt in range(200):
        channel = socket.socket(socket.AF_UNIX)
        try:
            channel.connect(runtime + "/discord-ipc-0")
            break
        except OSError:
            channel.close()
            time.sleep(0.01)
    else:
        raise SystemExit("no Discord RPC socket")
    channel.sendall(message)
    assert channel.recv(100) == message
    channel.close()
    print(message.decode(), flush=True)
    if message == b"first":
        sys.stdin.readline()
'''
        child = await asyncio.create_subprocess_exec(
            "bwrap", "--unshare-user", "--die-with-parent", "--ro-bind", "/", "/",
            "--tmpfs", "/run", "--bind", str(private), sandbox_runtime,
            "--ro-bind", str(self.bridge.directory), sandbox_runtime + "/discord-rpc",
            "--", sys.executable, "-c", code, sandbox_runtime,
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE)
        try:
            first = await asyncio.wait_for(child.stdout.readline(), 2)
            if not first:
                error = (await child.stderr.read()).decode()
                if "namespace" in error or "Operation not permitted" in error:
                    self.skipTest(error.strip())
                self.fail(error)
            self.assertEqual(b"readonly\n", first)
            await self.bridge.start()
            socket = self.runtime / "app/example.A/discord-ipc-0"
            server = await self.provider(socket)
            self.bridge.refresh()
            self.assertEqual(b"first\n", await asyncio.wait_for(child.stdout.readline(), 3))
            server.close()
            await server.wait_closed()
            self.bridge.refresh()
            socket.unlink(missing_ok=True)
            await self.provider(socket)
            self.bridge.refresh()
            child.stdin.write(b"reconnect\n")
            await child.stdin.drain()
            self.assertEqual(b"restarted\n", await asyncio.wait_for(child.stdout.readline(), 3))
            self.assertEqual(0, await asyncio.wait_for(child.wait(), 2))
        finally:
            if child.returncode is None:
                child.terminate()
                await child.wait()


class FlatpakRPCSetupTests(unittest.TestCase):
    def test_boot_permission_migration_preserves_custom_overrides(self):
        with tempfile.TemporaryDirectory(prefix="rpc-setup-") as temporary:
            root = Path(temporary)
            overrides = root / "overrides/global"
            overrides.parent.mkdir()
            commands = root / "commands"
            executable = root / "flatpak"
            executable.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$RPC_TEST_COMMANDS"\n'
                                  'if [[ $1 == remotes ]]; then printf "flathub\\t-\\n"; fi\n')
            executable.chmod(0o755)
            environment = {**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                           "FLATPAK_SYSTEM_DIR": str(root), "RPC_TEST_COMMANDS": str(commands)}
            script = ROOT / "system_files/usr/libexec/avethyos-flatpak-setup"
            legacy = "[Context]\nfilesystems=xdg-run;xdg-run/discord-ipc-*:create;\n"
            overrides.write_text(legacy)
            subprocess.run(["bash", str(script)], env=environment, check=True)
            self.assertFalse(overrides.exists())
            self.assertIn("override --system --filesystem=xdg-run/discord-rpc:ro", commands.read_text())
            customized = legacy + "devices=dri;\n"
            overrides.write_text(customized)
            subprocess.run(["bash", str(script)], env=environment, check=True)
            self.assertEqual(customized, overrides.read_text())


if __name__ == "__main__":
    unittest.main()
