"""Test pairing and bounded CLI jobs using a fake child, never real BlueZ."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location(
    "bluetooth_action", Path(__file__).resolve().parents[1] / "scripts/bluetooth-action.py")
bluetooth = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bluetooth)
ADDRESS = "00:11:22:AA:BB:CC"
REAL_POPEN = subprocess.Popen


class PairingTests(unittest.TestCase):
    def test_confirmation_without_newline_preserves_leading_zeroes(self):
        prompt = bluetooth.pairing_prompt(
            "Request confirmation\r\n\x1b[0;94m[agent]\x1b[0m Confirm passkey 42 (yes/no): ")
        self.assertEqual(prompt["kind"], "confirm")
        self.assertEqual(prompt["code"], "000042")

    def test_authorization_pin_passkey_and_keyboard_display(self):
        cases = [
            ("[agent] Authorize service 0000110b (yes/no): ", "confirm", ""),
            ("[agent] Accept pairing (yes/no): ", "confirm", ""),
            ("[agent] Enter PIN code: ", "pin", ""),
            ("[agent] Enter passkey: ", "passkey", ""),
            ("[agent] Enter passkey (number in 0-999999): ", "passkey", ""),
            ("[agent] Passkey: 003829\n", "display", "003829"),
            ("[agent] PIN code: 0246\n", "display", "0246"),
            ("[agent] PIN code: ab0246\n", "display", "ab0246"),
        ]
        for text, kind, code in cases:
            with self.subTest(text=text):
                prompt = bluetooth.pairing_prompt(text)
                self.assertEqual(prompt["kind"], kind)
                self.assertEqual(prompt["code"], code)
        self.assertIsNone(bluetooth.pairing_prompt("[CHG] Device AA:BB:CC:DD:EE:FF Connected: yes"))

    def test_agent_answers_cannot_inject_additional_commands(self):
        for kind, accepted, rejected in [
            ("confirm", ["yes", "no", "YES"], ["", "y", "yes\nremove " + ADDRESS]),
            ("passkey", ["0", "000042", "123456"], ["", "1234567", "123x", "123\n", "１２３"]),
            ("pin", ["0000", "device PIN", "a" * 16], ["", "a" * 17, "1234\n", "\x03", "12\r34"]),
            ("display", [], ["yes", "123456"]),
        ]:
            for answer in accepted:
                with self.subTest(kind=kind, answer=answer):
                    self.assertTrue(bluetooth.valid_answer({"kind": kind}, answer))
            for answer in rejected:
                with self.subTest(kind=kind, answer=answer):
                    self.assertFalse(bluetooth.valid_answer({"kind": kind}, answer))

    def test_error_feedback_identifies_authentication_hardware_and_timeout(self):
        self.assertIn("rejected", bluetooth.error_message("Failed to pair: org.bluez.Error.AuthenticationRejected", "pair"))
        self.assertIn("adapter is off", bluetooth.error_message("org.bluez.Error.NotReady", "connect"))
        self.assertIn("pairing mode", bluetooth.error_message("", "pair", timed_out=True))
        self.assertIn("awake", bluetooth.error_message("", "connect", timed_out=True))
        self.assertEqual(bluetooth.error_message("Failed: unknown\n", "connect"), "Failed: unknown")

    def test_pairing_requires_pair_then_trust_then_connect(self):
        with patch.object(bluetooth, "run_phase", return_value=(True, "")) as phase:
            self.assertEqual(bluetooth.run_action("pair", ADDRESS), (True, ""))
        self.assertEqual([call.args for call in phase.call_args_list], [
            ("pair", ADDRESS, 60), ("trust", ADDRESS, 20), ("connect", ADDRESS, 20)])

    def test_saved_device_is_trusted_before_connection(self):
        with patch.object(bluetooth, "run_phase", return_value=(True, "")) as phase:
            self.assertEqual(bluetooth.run_action("connect", ADDRESS), (True, ""))
        self.assertEqual([call.args[0] for call in phase.call_args_list], ["trust", "connect"])

    def test_failed_pair_does_not_trust_or_connect_and_partial_pair_is_clear(self):
        with patch.object(bluetooth, "run_phase", return_value=(False, "Rejected")) as phase:
            self.assertEqual(bluetooth.run_action("pair", ADDRESS), (False, "Rejected"))
            self.assertEqual(phase.call_count, 1)
        with patch.object(bluetooth, "run_phase", side_effect=[(True, ""), (True, ""), (False, "Device is asleep")]):
            self.assertEqual(bluetooth.run_action("pair", ADDRESS), (False, "Paired and saved. Device is asleep"))

    def test_disconnect_and_forget_do_not_trigger_pairing(self):
        for kind in ["disconnect", "remove"]:
            with self.subTest(kind=kind), patch.object(bluetooth, "run_phase", return_value=(True, "")) as phase:
                self.assertEqual(bluetooth.run_action(kind, ADDRESS), (True, ""))
                phase.assert_called_once_with(kind, ADDRESS, 20)

    def test_address_validation_rejects_options_and_shell_text(self):
        for value in [ADDRESS, ADDRESS.lower()]:
            self.assertTrue(bluetooth.ADDRESS.fullmatch(value))
        for value in ["--agent", ADDRESS + "; power off", "00:11:22:33:44", ADDRESS + "\n", ":::::::1111111111"]:
            self.assertFalse(bluetooth.ADDRESS.fullmatch(value))

    def test_stuck_child_is_killed_after_bounded_terminate(self):
        child = Mock()
        child.poll.return_value = None
        child.wait.side_effect = [subprocess.TimeoutExpired("fake", 1), 0]
        bluetooth.stop_child(child)
        child.terminate.assert_called_once()
        child.kill.assert_called_once()
        self.assertEqual(child.wait.call_count, 2)


class FakeCliTests(unittest.TestCase):
    def fake_phase(self, phase, program, timeout=1, answer=None):
        """Run the real PTY/select transport against a local fake process."""
        events = []
        reader, writer = os.pipe()
        self.addCleanup(os.close, reader)
        self.addCleanup(os.close, writer)
        fake_stdin = Mock()
        fake_stdin.fileno.return_value = reader
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fake_bluetoothctl.py"
            path.write_text(program)

            def launch(command, **kwargs):
                self.assertEqual(command[0], "bluetoothctl")
                self.assertIn("--timeout", command)
                if phase == "pair":
                    self.assertIn("KeyboardDisplay", command)
                return REAL_POPEN([sys.executable, "-u", str(path)], **kwargs)

            def emit(**event):
                events.append(event)
                if event["event"] == "prompt" and answer is not None:
                    import json
                    os.write(writer, (json.dumps({"answer": answer}) + "\n").encode())

            with patch.object(bluetooth.subprocess, "Popen", side_effect=launch), \
                    patch.object(bluetooth.sys, "stdin", fake_stdin), \
                    patch.object(bluetooth, "emit", side_effect=emit):
                result = bluetooth.run_phase(phase, ADDRESS, timeout)
        return result, events

    def test_confirmation_waits_for_explicit_answer_before_pairing(self):
        result, events = self.fake_phase("pair", """
import sys
print("[agent] Confirm passkey 000042 (yes/no): ", end="", flush=True)
answer = sys.stdin.readline().strip()
print("Pairing successful" if answer == "yes" else "Failed to pair: org.bluez.Error.AuthenticationRejected", flush=True)
""", answer="yes")
        self.assertEqual(result, (True, ""))
        self.assertEqual([event["event"] for event in events], ["phase", "prompt"])
        self.assertEqual(events[1]["code"], "000042")

    def test_zero_exit_code_with_dbus_error_is_not_success(self):
        result, _ = self.fake_phase("connect", "print('Failed to connect: org.bluez.Error.NotReady', flush=True)")
        self.assertFalse(result[0])
        self.assertIn("adapter is off", result[1])

    def test_explicit_connection_success_is_accepted(self):
        result, _ = self.fake_phase("connect", "print('Connection successful', flush=True)")
        self.assertEqual(result, (True, ""))

    def test_external_cli_failure_after_success_message_is_not_success(self):
        result, _ = self.fake_phase("connect", "import sys; print('Connection successful', flush=True); sys.exit(1)")
        self.assertFalse(result[0])

    def test_already_connected_device_is_an_idempotent_success(self):
        result, _ = self.fake_phase("connect", "import sys; print('Failed to connect: org.bluez.Error.AlreadyConnected', flush=True); sys.exit(1)")
        self.assertEqual(result, (True, ""))

    def test_no_response_is_bounded_and_child_is_stopped(self):
        result, _ = self.fake_phase("connect", "import time; time.sleep(30)", timeout=0.01)
        self.assertFalse(result[0])
        self.assertIn("did not respond", result[1])


if __name__ == "__main__":
    unittest.main()
