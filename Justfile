set dotenv-filename := "image-template.env"
set dotenv-load
set positional-arguments

image_name := env_var("IMAGE_NAME")
default_tag := env_var("DEFAULT_TAG")
nvidia_tag := if default_tag == "latest" { "nvidia" } else { default_tag + "-nvidia" }

alias build-vm := build-iso
alias rebuild-vm := rebuild-iso
alias run-vm := run-vm-iso

# List image development commands. On the installed OS, use avethyos instead.
default:
    @just --list

# Check formatting of the repository's recipe files.
check:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(find . -type f \( -name '*.just' -o -name Justfile \) -not -path './.git/*')
    while IFS= read -r file; do
        just --unstable --fmt --check --justfile "$file"
    done <<< "$files"

# Format the repository's recipe files.
fix:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(find . -type f \( -name '*.just' -o -name Justfile \) -not -path './.git/*')
    while IFS= read -r file; do
        just --unstable --fmt --justfile "$file"
    done <<< "$files"

# Build the standard image, or pass a name, tag and variant.
build target_image=image_name tag=default_tag variant="standard":
    bash build_files/build-image.sh "$1" "$2" "$3"

# Build the NVIDIA variant only.
build-nvidia target_image=image_name tag=nvidia_tag:
    bash build_files/build-image.sh "$1" "$2" nvidia

# Check packages, bootc layout, kernel, and the installed desktop.
check-image target_image=image_name tag=default_tag variant="standard":
    bash build_files/ci/check-image.sh "$1:$2" "$3"

# Arrange reusable layers for smaller downloads on future updates.
rechunk target_image=image_name tag=default_tag:
    bash build_files/rechunk-image.sh "$1" "$2"

# Build an installer ISO from a local or remote image.
build-iso target_image=("localhost/" + image_name) tag=default_tag:
    bash build_files/build-iso.sh "$1" "$2" output

# Build an installer ISO from the NVIDIA image.
build-iso-nvidia target_image=("localhost/" + image_name) tag=nvidia_tag:
    bash build_files/build-iso.sh "$1" "$2" output/nvidia

# Build a fresh standard image and its installer.
rebuild-iso target_image=("localhost/" + image_name) tag=default_tag: (build target_image tag) && (build-iso target_image tag)

# Build a fresh NVIDIA image and its installer.
rebuild-iso-nvidia target_image=("localhost/" + image_name) tag=nvidia_tag: (build-nvidia target_image tag) && (build-iso-nvidia target_image tag)

# Start an isolated virtual machine using the standard installer.
run-vm-iso target_image=("localhost/" + image_name) tag=default_tag:
    bash build_files/run-vm.sh "$1" "$2"

# Release tag helpers consumed by GitHub Actions.
[private]
image_name:
    @echo "{{ image_name }}"

[private]
generate-default-tag:
    @echo "{{ default_tag }}"

[private]
generate-nvidia-tag:
    @echo "{{ nvidia_tag }}"

[private]
generate-build-tags target_image=image_name tag=default_tag variant="standard":
    #!/usr/bin/env bash
    set -euo pipefail
    today=$(date -u +%Y%m%d)
    date_tag=$today
    [[ "$3" != nvidia ]] || date_tag+=-nvidia
    revision=$(git rev-parse --short HEAD)
    printf '%s\n' "$2-$revision $2-$today-$revision $date_tag-$revision $date_tag $2-$today $2"

# Remove generated local build output.
clean:
    rm -rf -- output _build-* *_chunkah_*

# Check shell helper style; install ShellCheck on your development machine.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(find build_files system_files quickshell -type f -name '*.sh')
    while IFS= read -r file; do shellcheck "$file"; done <<< "$files"

# Format shell helpers; install shfmt on your development machine.
format:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(find build_files system_files quickshell -type f -name '*.sh')
    while IFS= read -r file; do shfmt --write "$file"; done <<< "$files"
