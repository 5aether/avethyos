#!/usr/bin/env python3
"""Bounded bluetoothctl jobs, including explicit pairing-agent prompts.

stdout is newline-delimited JSON. stdin accepts {"answer": "yes|no|PIN"}.
Every job owns its child and terminates it when the QML process is cancelled.
"""
from __future__ import annotations

import argparse
import errno
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")
ADDRESS = re.compile(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\Z")
ALLOWED = {"pair", "connect", "disconnect", "remove"}


def emit(**event: object) -> None:
    print(json.dumps(event, ensure_ascii=False), flush=True)


def clean_output(text: str) -> str:
    return ANSI.sub("", text).replace("\r", "")


def pairing_prompt(text: str) -> dict[str, str] | None:
    """Extract prompts even when bluetoothctl has not written a newline."""
    text = clean_output(text)
    confirmation = re.search(r"Confirm passkey\s+(\d{1,6})[^\n]*\(yes/no\)\s*:?\s*$", text, re.I)
    if confirmation:
        return {"kind": "confirm", "code": confirmation[1].zfill(6),
                "message": "Confirm this code matches the code shown on your device."}
    if re.search(r"(?:Authorize service|Accept pairing)[^\n]*\(yes/no\)\s*:?\s*$", text, re.I):
        return {"kind": "confirm", "code": "", "message": "Allow this device to pair and connect?"}
    if re.search(r"Enter PIN code\s*:?\s*$", text, re.I):
        return {"kind": "pin", "code": "", "message": "Enter the PIN shown on your device."}
    if re.search(r"Enter passkey(?:\s*\([^\n]*\))?\s*:?\s*$", text, re.I):
        return {"kind": "passkey", "code": "", "message": "Enter the six-digit passkey shown on your device."}
    pin_display = re.search(r"(?<!Enter )\bPIN code:\s*(\S{1,16})\s*$", text, re.I)
    if pin_display:
        return {"kind": "display", "code": pin_display[1], "message": "Type this code on your device, then press Enter there."}
    display = re.search(r"(?<!Enter )\b(?:Passkey|PIN code):\s*(\d{1,16})(?:\s+\S*)?\s*$", text, re.I)
    if display:
        return {"kind": "display", "code": display[1], "message": "Type this code on your device, then press Enter there."}
    return None


def error_message(text: str, phase: str, timed_out: bool = False) -> str:
    if timed_out:
        return "Pairing timed out. Put the device in pairing mode and try again." if phase == "pair" else "The device did not respond. Check it is awake and nearby."
    text = clean_output(text)
    reasons = {
        "AuthenticationCanceled": "Pairing was cancelled on the device.",
        "AuthenticationRejected": "The device rejected pairing. Check the code and try again.",
        "AuthenticationFailed": "Pairing failed. Check the PIN or passkey and try again.",
        "AuthenticationTimeout": "Pairing timed out. Put the device in pairing mode and try again.",
        "NotReady": "The Bluetooth adapter is off or unavailable.",
        "InProgress": "The device is already handling a connection. Try again shortly.",
        "NotAvailable": "The device is unavailable. Check it is awake and nearby.",
        "br-connection-profile-unavailable": "The device has no available connection profile. Try pairing it again.",
        "br-connection-page-timeout": "The device did not respond. Check it is awake and nearby.",
    }
    for token, message in reasons.items():
        if token.lower() in text.lower():
            return message
    lines = [line.strip() for line in text.splitlines() if re.search(r"failed|error|not available|not found|no default controller", line, re.I)]
    if lines:
        return lines[-1][:220]
    return "Bluetooth could not complete the action. Check the device and try again."


def valid_answer(prompt: dict[str, str], answer: str) -> bool:
    if prompt["kind"] == "confirm":
        return answer.lower() in {"yes", "no"}
    if prompt["kind"] == "passkey":
        return bool(re.fullmatch(r"[0-9]{1,6}", answer))
    if prompt["kind"] == "pin":
        return bool(answer) and len(answer) <= 16 and all(char.isprintable() for char in answer)
    return False


def stop_child(child: subprocess.Popen[bytes]) -> None:
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=1)


def run_phase(phase: str, address: str, timeout: float) -> tuple[bool, str]:
    emit(event="phase", phase=phase)
    master, slave = pty.openpty()
    command = ["bluetoothctl", "--timeout", str(int(timeout))]
    if phase == "pair":
        command += ["--agent", "KeyboardDisplay"]
    command += [phase, address]
    child = None
    output = ""
    pending: dict[str, str] | None = None
    seen_prompts: set[str] = set()
    input_buffer = b""
    try:
        child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                                 close_fds=True, start_new_session=True)
        os.close(slave)
        slave = -1
        os.set_blocking(master, False)
        deadline = time.monotonic() + timeout + 2
        timed_out = False
        stream_open = True
        input_open = True
        while stream_open or child.poll() is None:
            if time.monotonic() >= deadline:
                timed_out = True
                break
            readers = ([master] if stream_open else []) + ([sys.stdin.fileno()] if input_open else [])
            readable, _, _ = select.select(readers, [], [], min(0.2, max(0, deadline - time.monotonic())))
            for fd in readable:
                if fd == master:
                    try:
                        chunk = os.read(master, 16384)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            chunk = b""
                        elif error.errno == errno.EAGAIN:
                            continue
                        else:
                            raise
                    if not chunk:
                        stream_open = False
                        continue
                    output += chunk.decode("utf-8", errors="replace")
                    prompt = pairing_prompt(output[-4096:]) if phase == "pair" else None
                    if prompt:
                        key = json.dumps(prompt, sort_keys=True)
                        if key not in seen_prompts:
                            seen_prompts.add(key)
                            pending = prompt
                            emit(event="prompt", **prompt)
                else:
                    chunk = os.read(fd, 4096)
                    if not chunk:
                        input_open = False
                        continue
                    input_buffer += chunk
                    while b"\n" in input_buffer:
                        line, input_buffer = input_buffer.split(b"\n", 1)
                        try:
                            answer = str(json.loads(line).get("answer", ""))
                        except (ValueError, AttributeError):
                            continue
                        if pending and valid_answer(pending, answer):
                            os.write(master, (answer + "\n").encode())
                            pending = None
        stop_child(child) if timed_out else child.wait(timeout=1)
        text = clean_output(output)
        success_pattern = {
            "pair": r"Pairing successful|AlreadyExists",
            "trust": r"trust succeeded",
            "connect": r"Connection successful|AlreadyConnected",
            "disconnect": r"Successful disconnected|Disconnection successful|NotConnected",
            "remove": r"Device has been removed",
        }[phase]
        # Some BlueZ releases return success exit status after a D-Bus error;
        # require the operation's explicit success message as well.
        already_done = {
            "pair": "org.bluez.Error.AlreadyExists",
            "connect": "org.bluez.Error.AlreadyConnected",
            "disconnect": "org.bluez.Error.NotConnected",
        }.get(phase, "")
        success = not timed_out and ((bool(already_done) and already_done in text)
            or (child.returncode == 0 and bool(re.search(success_pattern, text, re.I))))
        return success, "" if success else error_message(text, phase, timed_out)
    finally:
        if child is not None:
            stop_child(child)
        os.close(master)
        if slave >= 0:
            os.close(slave)


def run_action(kind: str, address: str) -> tuple[bool, str]:
    phases = ["pair", "trust", "connect"] if kind == "pair" else ["trust", "connect"] if kind == "connect" else [kind]
    for phase in phases:
        success, error = run_phase(phase, address, 60 if phase == "pair" else 20)
        if not success:
            if phase == "connect" and kind == "pair":
                error = "Paired and saved. " + error
            return False, error
    return True, ""


def cancelled(_signal: int, _frame: object) -> None:
    raise InterruptedError("Cancelled")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=sorted(ALLOWED))
    parser.add_argument("address", type=str)
    args = parser.parse_args()
    if not ADDRESS.fullmatch(args.address):
        parser.error("invalid Bluetooth address")
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        success, error = run_action(args.kind, args.address)
    except InterruptedError:
        success, error = False, "Cancelled"
    except (OSError, subprocess.SubprocessError) as exception:
        success, error = False, "Bluetooth control is unavailable: " + str(exception)
    emit(event="result", success=success, error=error)
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
