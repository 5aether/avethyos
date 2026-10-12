#!/bin/bash
set -euo pipefail
source image-template.env
image="${1:?Specify an image}:${2:?Specify a tag}"
output="${3:-output}"
root=()
if (( UID != 0 )); then
    root=(sudo)
fi

# The image builder uses root's container storage. Copy a local user build
# through Podman's native archive stream only when the two copies differ.
if podman image exists "$image"; then
    local_id=$(podman image inspect --format '{{.Id}}' "$image")
    root_id=$("${root[@]}" podman image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
    if [[ "$local_id" != "$root_id" ]]; then
        podman save --format oci-archive "$image" | "${root[@]}" podman load
    fi
else
    "${root[@]}" podman pull "$image"
fi

temporary=$(mktemp -d "${PWD}/_build-iso.XXXXXXXXXX")
trap '"${root[@]}" rm -rf -- "$temporary"' EXIT
"${root[@]}" podman run --rm --privileged --pull=newer --net=host \
    --security-opt label=type:unconfined_t \
    -v "${PWD}/disk_config/iso.toml:/config.toml:ro" \
    -v "$temporary:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "$BIB_IMAGE" build --type anaconda-iso --output /output \
    --use-librepo=True --rootfs=btrfs "$image"
mkdir -p "$output"
"${root[@]}" cp -a "$temporary/." "$output/"
"${root[@]}" chown -R "$(id -u):$(id -g)" "$output"
printf 'Installer: %s/bootiso/install.iso\n' "$output"
