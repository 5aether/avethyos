#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

just check

# Parse every shell/Python helper, including executable files without a suffix.
# Parsing Python directly avoids adding bytecode to the build context.
python3 - <<'PY'
import ast
from pathlib import Path
import subprocess

count = 0
for root in (Path("build_files"), Path("system_files"), Path("quickshell")):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(part in (".git", "__pycache__") for part in path.parts):
            continue
        if path.suffix not in ("", ".sh", ".py"):
            continue
        data = path.read_bytes()
        first_line = data.split(b"\n", 1)[0]
        if path.suffix == ".py" or (first_line.startswith(b"#!") and b"python" in first_line):
            ast.parse(data, filename=str(path))
        elif path.suffix == ".sh" or first_line.startswith((b"#!/bin/bash", b"#!/bin/sh", b"#!/usr/bin/env bash")):
            shell = "sh" if first_line == b"#!/bin/sh" else "bash"
            subprocess.run([shell, "-n", str(path)], check=True)
        else:
            continue
        count += 1
print(f"Parsed {count} shell and Python sources.")
PY

python3 -B -m unittest discover -s tests -v
node --test quickshell/tests/*.test.js
python3 -B -m unittest discover -s quickshell/tests -p 'test_*.py'
python3 -B quickshell/tests/qml-check.py
