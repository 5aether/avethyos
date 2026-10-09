#!/usr/bin/env python3
"""Restart this shell through its Avethy-aware launcher."""

import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    listing = subprocess.check_output(["qs", "list"], text=True)
    for block in listing.split("Instance ")[1:]:
        config = re.search(r"Config path: (.+)", block)
        process = re.search(r"Process ID: (\d+)", block)
        if not config or not process or Path(config[1].strip()) != ROOT / "shell.qml":
            continue
        pid = int(process[1])
        subprocess.run(["qs", "kill", "--pid", str(pid)], check=True)
        for _ in range(100):
            try:
                state = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
                if state == "Z":
                    break
            except FileNotFoundError:
                break
            time.sleep(.1)
        else:
            raise RuntimeError("previous shell did not exit; restart stopped")
    launcher = str(ROOT / "scripts/run.sh")
    os.execv("/usr/bin/bash", ["bash", launcher, "--no-duplicate", *sys.argv[1:]])


if __name__ == "__main__":
    main()
