# AvethyOS

AvethyOS is a Fedora bootc desktop with Hyprland and Quickshell.

## Updates

Update the installed system with:

```bash
sudo bootc upgrade
```

Reboot to start the updated deployment. Bootc keeps the previous deployment for
rollback.

Published standard and NVIDIA images are split into content-based layers with
[chunkah](https://github.com/coreos/chunkah). Bootc reuses layers already present
on the system and downloads changed layers. A package or desktop configuration
update can therefore download only a fraction of the image.

This works at the layer level: a changed layer can contain unchanged files too.
Large package updates, changes to package grouping, and Fedora version upgrades
can still require larger downloads. The first upgrade from an older, unchunked
image can download most of the image; subsequent upgrades reuse the new layout.

The build uses stable directory timestamps, a fixed timestamp when splitting
layers, and reproducible initramfs generation to reduce changes caused only by
rebuilding or package installation. The publishing workflow reports the full
compressed image size and the estimated download from the previous image of the
same variant. This estimate counts new layer digests; it does not include metadata
or reflect clients upgrading from older releases.

## Local image builds

Run rechunking after building and before pushing a local image:

```bash
just build
just rechunk
```

For NVIDIA:

```bash
just build-nvidia
just rechunk avethyos nvidia
```

Rechunking checks the resulting image with `bootc container lint` before replacing
the local image tag. GitHub Actions performs this step for both variants before
tagging, publishing, and signing them.
