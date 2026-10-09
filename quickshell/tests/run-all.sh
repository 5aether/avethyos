#!/bin/sh
# Runs every check that can run without a live Wayland session:
#   - the JS unit tests for modules/
#   - the structural QML check
# Qt tooling (qmllint) and the shell itself are not available here, so this is
# a floor, not a replacement.
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
