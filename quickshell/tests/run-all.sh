#!/bin/sh
# Runs every check that can run without a live Wayland session:
#   - the JS unit tests for modules/
#   - Python helpers and optional offscreen Quickshell icon/launcher integration
#   - the structural QML check
# qmllint and a live Wayland session are not required, so these checks are
# a floor, not a replacement for exercising the desktop shell.
set -e

cd "$(dirname "$0")/.."

echo "== JS unit tests"
node --test tests/*.test.js

echo
echo "== Python unit tests"
python3 -m unittest discover -s tests -p 'test_*.py'

echo
echo "== QML structure"
python3 tests/qml-check.py

echo
echo "== helper script syntax"
for script in scripts/*.sh; do
    sh -n "$script"
    echo "$script ok"
done
for script in scripts/*.py; do
    python3 -m py_compile "$script"
    echo "$script ok"
done
