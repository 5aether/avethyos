#!/usr/bin/env bash

set -euo pipefail
source image-template.env
target_image=${1:-$IMAGE_NAME}
tag=${2:-$DEFAULT_TAG}

# Chunking needs a temporary complete copy of the image.
CHUNKAH_CONFIG_FILE="$(mktemp)"

# Use the build filesystem instead of the smaller /tmp partition.
CHUNKAH_OUTPUT_DIR="$(mktemp -d ./_build-chunkah.XXXXXXXXXX)"

trap 'rm -f "${CHUNKAH_CONFIG_FILE}"; rm -rf "${CHUNKAH_OUTPUT_DIR}"' EXIT
podman inspect "${target_image}:${tag}" > "${CHUNKAH_CONFIG_FILE}"

# Keep the packer and timestamp fixed across releases for layer reuse.
podman run --rm \
  --mount=type=image,src="${target_image}:${tag}",target=/chunkah,rw=true \
  -v "${PWD}/build_files/rechunk.sh:/rechunk.sh:ro,Z" \
  -v "${CHUNKAH_CONFIG_FILE}:/chunkah-config.json:ro,Z" \
  -v "${CHUNKAH_OUTPUT_DIR}:/run/out:Z" \
  --env SOURCE_DATE_EPOCH=0 \
  --entrypoint=/bin/bash \
  quay.io/coreos/chunkah:v0.6.0@sha256:ff8b8b466a942ec6000445d4001fc661e2fc5a952ad9ee29b4de9ab09d1d1708 \
  /rechunk.sh \
  build \
  --verbose \
  --compressed \
  --max-layers 128 \
  --prune /sysroot/ \
  --label ostree.commit- --label ostree.final-diffid- \
  --config /chunkah-config.json \
  --output oci:/run/out/chunked

CHUNKED_IMAGE="$(podman pull --quiet "oci:${CHUNKAH_OUTPUT_DIR}/chunked")"
# Check the final layout before replacing the original image tag.
podman run --rm --pull=never --entrypoint=bootc "${CHUNKED_IMAGE}" container lint
podman tag "${CHUNKED_IMAGE}" "${target_image}:${tag}"
