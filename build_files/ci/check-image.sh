#!/bin/bash
set -euo pipefail

image="${1:?Specify the local image reference}"
variant="${2:?Specify standard or nvidia}"
artifacts="${IMAGE_ARTIFACTS:-${RUNNER_TEMP:-/tmp}/avethyos-${variant}}"
mkdir -p "$artifacts"

podman inspect "$image" > "$artifacts/image-inspect.json"
jq -e --arg revision "$(git rev-parse HEAD)" --arg variant "$variant" '
    .[0].Config.Labels
    | .["containers.bootc"] == "1"
      and .["org.opencontainers.image.revision"] == $revision
      and .["org.opencontainers.image.licenses"] == "Apache-2.0"
      and .["io.avethyos.variant"] == $variant
      and (.["org.opencontainers.image.version"] | strings | length > 0)
      and (.["org.opencontainers.image.source"] | strings | length > 0)
      and (.["org.opencontainers.image.base.digest"] | strings | test("^sha256:[a-f0-9]{64}$"))
      and (.["io.avethyos.kernel.ref"] | strings | test("@sha256:[a-f0-9]{64}$"))
' "$artifacts/image-inspect.json" > "$artifacts/metadata-check.txt"

podman run --rm --pull=never --network=none \
    --env "EXPECTED_FEDORA_VERSION=${FEDORA_VERSION:-}" \
    --volume "${PWD}/build_files/check-system.sh:/check-system.sh:ro" \
    --entrypoint /bin/bash "$image" /check-system.sh "$variant" \
    2>&1 | tee "$artifacts/system-checks.log"

podman run --rm --pull=never --network=none \
    --volume "${PWD}/build_files/check-desktop.sh:/check-desktop.sh:ro" \
    --entrypoint /bin/bash "$image" /check-desktop.sh \
    2>&1 | tee "$artifacts/desktop-checks.log"

# Run optional Qt/Quickshell integration tests with the installed libraries.
podman run --rm --pull=never --network=none \
    --env QT_QPA_PLATFORM=offscreen --env QT_QUICK_BACKEND=software \
    --env LIBGL_ALWAYS_SOFTWARE=1 \
    --env PYTHONDONTWRITEBYTECODE=1 \
    --volume "${PWD}/quickshell:/quickshell:ro" \
    --entrypoint /usr/bin/python3 "$image" \
    -B -m unittest discover -s /quickshell/tests -p 'test_*.py' \
    2>&1 | tee "$artifacts/quickshell-checks.log"
