#!/bin/bash
set -euo pipefail

brew_prefix=/home/linuxbrew/.linuxbrew
if [[ -e "$brew_prefix" || -L "$brew_prefix" ]]; then
    exit 0
fi

install -d -o linuxbrew -g linuxbrew -m755 /var/home/linuxbrew
staging_dir="$(mktemp -d /var/home/linuxbrew/.linuxbrew.XXXXXX)"
trap 'rm -rf -- "$staging_dir"' EXIT
cp -a --reflink=auto /usr/share/avethyos/homebrew/. "$staging_dir/"
chown -R linuxbrew:linuxbrew "$staging_dir"
chmod 755 "$staging_dir"
mv -T "$staging_dir" "$brew_prefix"
restorecon -RF /var/home/linuxbrew
