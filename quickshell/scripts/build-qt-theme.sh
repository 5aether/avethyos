#!/bin/sh
# Build the project's native style and startup plugin with the installed Qt SDK.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
major=${1:-6}
case "$major" in 5|6) ;; *) echo "usage: $0 [5|6] [build directory]" >&2; exit 2 ;; esac
build=${2:-"${root}/native/qt-theme/build-qt${major}"}
cmake -S "${root}/native/qt-theme" -B "$build" -DQT_MAJOR="$major" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build "$build" --parallel 2
