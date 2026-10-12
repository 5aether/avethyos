"""Account setup preserves mappings and grants native GameMode helper access."""

import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("user_access", str(
    ROOT / "system_files/usr/libexec/avethyos-user-access"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
access = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(access)


class UserAccessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.etc = Path(temporary.name)
        (self.etc / "login.defs").write_text("UID_MIN 1000\nUID_MAX 60000\n")
        (self.etc / "passwd").write_text(
            "root:x:0:0::/root:/bin/bash\n"
            "service:x:964:964::/:/usr/sbin/nologin\n"
            "disabled:x:1001:1001::/home/disabled:/usr/sbin/nologin\n"
            "alice:x:1000:1000::/home/alice:/bin/bash\n"
            "bob:x:1002:1002::/home/bob:/bin/bash\n")
        (self.etc / "subuid").write_text("older:524288:65536\n")
        (self.etc / "subgid").write_text("older:655360:65536\n")
        self.members = []
        self.group = patch.object(access.grp, "getgrnam", side_effect=lambda _: SimpleNamespace(
            gr_mem=self.members[:], gr_gid=964))
        self.group.start()
        self.addCleanup(self.group.stop)
        self.commands = []

    def usermod(self, arguments, check):
        self.assertTrue(check)
        self.assertEqual("usermod", arguments[0])
        self.commands.append(arguments)
        name = arguments[-1]
        for kind in ("uid", "gid"):
            option = f"--add-sub{kind}s"
            if option in arguments:
                first, last = map(int, arguments[arguments.index(option) + 1].split("-"))
                with (self.etc / f"sub{kind}").open("a") as output:
                    output.write(f"{name}:{first}:{last - first + 1}\n")
        if "--groups" in arguments:
            self.members.append(name)

    def test_upgraded_accounts_receive_disjoint_ranges_once(self):
        access.prepare(self.etc, self.usermod)
        self.assertEqual({"alice", "bob"}, {command[-1] for command in self.commands})
        for kind in ("uid", "gid"):
            records = access.mappings(self.etc / f"sub{kind}")
            for _, first, count in records:
                others = [(start, length) for _, start, length in records if start != first]
                self.assertTrue(all(first + count <= start or start + length <= first
                                    for start, length in others))
        self.assertEqual(["alice", "bob"], self.members)
        self.commands.clear()
        access.prepare(self.etc, self.usermod)
        self.assertEqual([], self.commands)

    def test_existing_name_and_numeric_id_mappings_are_preserved(self):
        original = "alice:800000:65536\n1002:900000:65536\n"
        for kind in ("uid", "gid"):
            (self.etc / f"sub{kind}").write_text(original)
        self.members.extend(["alice", "bob"])
        access.prepare(self.etc, self.usermod)
        self.assertEqual([], self.commands)
        self.assertEqual(original, (self.etc / "subuid").read_text())
        self.assertEqual(original, (self.etc / "subgid").read_text())

    def test_one_missing_mapping_does_not_replace_the_other(self):
        (self.etc / "subuid").write_text("alice:800000:65536\nbob:900000:65536\n")
        access.prepare(self.etc, self.usermod)
        self.assertTrue(all("--add-subuids" not in command for command in self.commands))
        self.assertTrue(all("--add-subgids" in command for command in self.commands))

    def test_accounts_without_subordinate_id_files_are_prepared(self):
        (self.etc / "subuid").unlink()
        (self.etc / "subgid").unlink()
        access.prepare(self.etc, self.usermod)
        self.assertEqual({"alice", "bob"}, {owner for owner, _, _ in access.mappings(self.etc / "subuid")})
        self.assertEqual(0o644, (self.etc / "subuid").stat().st_mode & 0o777)

    def test_exhausted_ranges_fail_without_running_usermod(self):
        with (self.etc / "login.defs").open("a") as output:
            output.write("SUB_UID_MAX 589823\n")
        with self.assertRaisesRegex(ValueError, "No subordinate UID range"):
            access.prepare(self.etc, self.usermod)
        self.assertEqual([], self.commands)


if __name__ == "__main__":
    unittest.main()
