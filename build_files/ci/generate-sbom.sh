#!/bin/bash
set -euo pipefail

image="${1:?Specify the local image reference}"
artifacts="${IMAGE_ARTIFACTS:?}"
syft_command="${SYFT_CMD:?}"
mkdir -p "$artifacts"

# Mount the final image in Podman's user namespace. This scans its filesystem
# without exporting a second full copy or scanning the runner's packages.
container=$(podman create --entrypoint /bin/true "$image")
trap 'podman rm -f "$container" >/dev/null' EXIT
podman unshare bash -euo pipefail -c '
    mountpoint=$(podman mount "$1")
    trap '\''podman unmount "$1" >/dev/null'\'' EXIT
    "$2" scan "dir:${mountpoint}" \
        --source-name "$3" --source-version "$4" \
        -o "spdx-json=$5/sbom.spdx.json" \
        -o "syft-json=$5/sbom.syft.json"
' _ "$container" "$syft_command" "${IMAGE_REF:?}" "${IMAGE_VERSION:?}" "$artifacts"

# Require a real SPDX document and the RPM inventory of our bootable image.
jq -e '
    (.spdxVersion | startswith("SPDX-"))
    and (.packages | length > 0)
' "$artifacts/sbom.spdx.json" >/dev/null
jq -e '
    [.artifacts[] | select(.type == "rpm") | .name] as $packages
    | ["bootc", "kernel-core", "hyprland", "quickshell", "sddm"]
    | all(. as $name | $packages | index($name) != null)
' "$artifacts/sbom.syft.json" >/dev/null
du -h "$artifacts"/sbom.*.json
