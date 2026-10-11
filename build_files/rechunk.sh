#!/bin/bash
set -euo pipefail

# Package installs touch shared directories (for example /usr/lib/.build-id).
# Those directories appear in many layers, so even unchanged packages would
# otherwise get new layer digests. Normalize only directory mtimes in Podman's
# temporary writable image mount; file contents, permissions and xattrs stay intact.
find /chunkah -path '/chunkah/sysroot/*' -prune -o -type d \
    -exec touch -h -m -d "@${SOURCE_DATE_EPOCH:?}" {} +

exec chunkah "$@"
