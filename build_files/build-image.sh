#!/usr/bin/env bash

set -euo pipefail
source image-template.env
target_image=${1:-$IMAGE_NAME}
tag=${2:-$DEFAULT_TAG}
variant=${3:-standard}

case "${variant}" in
    standard|nvidia) ;;
    *) echo "Unknown image variant: ${variant}" >&2; exit 1 ;;
esac

BUILD_ARGS=()
LABELS=()

# CI resolves these once in its upstream validation stage. Local builds do
# the same here so both Fedora stages and the OGC layer use fixed inputs.
BASE_REF="${BASE_IMAGE_REF:-}"
if [[ -z "$BASE_REF" ]]; then
    BASE_METADATA=$(skopeo inspect --retry-times=3 "docker://${BASE_IMAGE}")
    BASE_REF=$(jq -er '.Name + "@" + .Digest' <<< "$BASE_METADATA")
fi
OGC_KERNEL_DIGEST="${OGC_KERNEL_DIGEST_REF:-}"
if [[ -z "$OGC_KERNEL_DIGEST" ]]; then
    OGC_KERNEL_DIGEST=$(podman run --rm --pull=newer ghcr.io/oras-project/oras:v1.3.4 \
        resolve --full-reference "${OGC_KERNEL_REF:-ghcr.io/opengamingcollective/kernel-packages-fedora:latest-fc44}")
fi
[[ "$BASE_REF" =~ @sha256:[a-f0-9]{64}$ ]]
[[ "$OGC_KERNEL_DIGEST" =~ @sha256:[a-f0-9]{64}$ ]]
BUILD_ARGS+=(--build-arg "BASE_IMAGE=${BASE_REF}")
BUILD_ARGS+=(--build-arg "OGC_KERNEL_REF=${OGC_KERNEL_DIGEST}")

GIT_REVISION=$(git rev-parse HEAD)
SOURCE_REPO="${GITHUB_REPOSITORY:-${REPO_ORGANIZATION}/${IMAGE_NAME}}"
VERSION="${IMAGE_VERSION:-${tag}.$(date -u +%Y%m%d)-${GIT_REVISION:0:7}}"
if [[ -n "$(git status -s)" && "${GITHUB_ACTIONS:-false}" != true ]]; then
    VERSION+="-dirty"
fi
LABELS+=("--label" "org.opencontainers.image.revision=${GIT_REVISION}")
LABELS+=("--label" "org.opencontainers.image.version=${VERSION}")
LABELS+=("--label" "org.opencontainers.image.licenses=Apache-2.0")
LABELS+=("--label" "org.opencontainers.image.base.name=${BASE_IMAGE}")
LABELS+=("--label" "org.opencontainers.image.base.digest=${BASE_REF##*@}")
LABELS+=("--label" "io.avethyos.kernel.ref=${OGC_KERNEL_DIGEST}")
LABELS+=("--label" "io.avethyos.variant=${variant}")
LABELS+=("--label" "containers.bootc=1")
LABELS+=("--label" "org.opencontainers.image.source=https://github.com/${SOURCE_REPO}")
if [[ -z "$(git status -s)" ]]; then
    LABELS+=("--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/${SOURCE_REPO}/${GIT_REVISION}/README.md")
    LABELS+=("--label" "org.opencontainers.image.documentation=https://raw.githubusercontent.com/${SOURCE_REPO}/${GIT_REVISION}/README.md")
    LABELS+=("--label" "org.opencontainers.image.url=https://github.com/${SOURCE_REPO}/tree/${GIT_REVISION}")
fi

# Metadata used by the package index and image registry.
LABELS+=("--label" "io.artifacthub.package.deprecated=false")
LABELS+=("--label" "io.artifacthub.package.keywords=${IMAGE_KEYWORDS}")
LABELS+=("--label" "io.artifacthub.package.license=Apache-2.0")
LABELS+=("--label" "io.artifacthub.package.logo-url=${IMAGE_LOGO_URL}")
LABELS+=("--label" "io.artifacthub.package.prerelease=false")
LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
LABELS+=("--label" "org.opencontainers.image.description=${IMAGE_DESC}")
LABELS+=("--label" "org.opencontainers.image.title=${IMAGE_NAME}")
LABELS+=("--label" "org.opencontainers.image.vendor=${REPO_ORGANIZATION}")

PODMAN_BUILD_ARGS=("${BUILD_ARGS[@]}" "${LABELS[@]}" --layers --pull=newer --target "${variant}" --tag "${target_image}:${tag}" --file Containerfile)

podman build "${PODMAN_BUILD_ARGS[@]}" .
