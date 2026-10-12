ARG BASE_IMAGE=quay.io/fedora/fedora-bootc:44

FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY README.md LICENSE /docs/

FROM scratch AS desktop
COPY hypr /hypr
COPY quickshell /quickshell

FROM ${BASE_IMAGE} AS ogc-kernel
ARG OGC_KERNEL_REF=ghcr.io/opengamingcollective/kernel-packages-fedora:latest-fc44

RUN --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    dnf5 install -y --setopt=install_weak_deps=False golang-oras && \
    oras pull --output /kernel-rpms "${OGC_KERNEL_REF}"

FROM ${BASE_IMAGE} AS base

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/repo-tools.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=bind,from=ogc-kernel,source=/kernel-rpms,target=/kernel-rpms \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/kernel.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/pre-install.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/appstream.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/codecs.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/firmware.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/hyprland.sh

FROM base AS quickshell-build

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=bind,from=desktop,source=/quickshell,target=/source \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/quickshell-build.sh

FROM base AS common

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/nautilus.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=bind,from=quickshell-build,source=/out,target=/theme \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/quickshell.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/distrobox.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/steam.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/flatpak.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/discord-rpc.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/homebrew.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/sddm.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/silentsddm.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/layers/topgrade.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=desktop,source=/,target=/defaults \
    bash /ctx/layers/desktop-configs.sh

FROM common AS nvidia

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=bind,from=ogc-kernel,source=/kernel-rpms,target=/kernel-rpms \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/etc/pki/akmods \
    bash /ctx/layers/nvidia.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/post-install.sh

RUN /usr/libexec/avethyos-image-cleanup && bootc container lint --fatal-warnings

FROM common AS standard

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ctx,source=/dnf-cache.conf,target=/etc/dnf/libdnf5.conf.d/99-avethyos-build-cache.conf \
    --mount=type=cache,dst=/var/cache,id=avethyos-packages,sharing=locked \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/post-install.sh

RUN /usr/libexec/avethyos-image-cleanup && bootc container lint --fatal-warnings
