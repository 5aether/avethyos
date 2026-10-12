#!/bin/bash
set -euo pipefail
image=${1:?Specify an image}
tag=${2:?Specify a tag}
iso="${PWD}/output/bootiso/install.iso"
if [[ ! -f "$iso" ]]; then
    bash build_files/build-iso.sh "$image" "$tag" output
fi
port=8006
while [[ -n "$(ss -tlnH "sport = :${port}")" ]]; do
    ((port+=1))
done
printf 'VM screen: http://localhost:%s\n' "$port"
podman run --rm --privileged --pull=newer \
    --publish "127.0.0.1:${port}:8006" --device /dev/kvm \
    --env CPU_CORES=4 --env RAM_SIZE=8G --env DISK_SIZE=64G \
    --env TPM=Y --env GPU=Y --volume "$iso:/boot.iso:ro" docker.io/qemux/qemu
