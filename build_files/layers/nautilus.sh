#!/bin/bash
set -euo pipefail

# Fedora's gvfs-goa package includes the OneDrive backend.
dnf5 install -y --setopt=install_weak_deps=False \
    nautilus nautilus-extensions nautilus-python \
    7zip zip unzip unar \
    sushi \
    localsearch tinysparql \
    gnome-keyring libsecret \
    gnome-online-accounts \
    gnome-disk-utility \
    gparted \
    xdg-user-dirs xdg-user-dirs-gtk \
    ffmpegthumbnailer papers-thumbnailer gnome-epub-thumbnailer \
    gdk-pixbuf2-modules-extra glycin-loaders \
    webp-pixbuf-loader heif-pixbuf-loader avif-pixbuf-loader jxl-pixbuf-loader \
    gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugin-libav \
    gvfs gvfs-client gvfs-fuse gvfs-archive gvfs-goa \
    gvfs-mtp gvfs-gphoto2 gvfs-afc gvfs-afp \
    gvfs-nfs gvfs-smb \
    openssh-clients fuse-sshfs \
    exfatprogs ntfs-3g ntfsprogs dosfstools btrfs-progs xfsprogs \
    samba-client samba-common samba-common-tools cifs-utils libsmbclient \
    avahi avahi-tools nss-mdns \
    wsdd \
    nfs-utils rpcbind \
    cups-browsed
