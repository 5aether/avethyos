#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    git-core /usr/bin/curl file procps-ng \
    gcc gcc-c++ make patch tar gzip bzip2 unzip \
    sudo util-linux policycoreutils

install -Dm644 /ctx/homebrew/sysusers.conf /usr/lib/sysusers.d/avethyos-homebrew.conf
systemd-sysusers /usr/lib/sysusers.d/avethyos-homebrew.conf
install -d -o linuxbrew -g linuxbrew -m755 /var/home/linuxbrew

installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
runuser -u linuxbrew -- env NONINTERACTIVE=1 HOMEBREW_NO_SUDO=1 \
    /bin/bash -c "$installer"

mkdir -p /usr/share/avethyos
cp -a /home/linuxbrew/.linuxbrew /usr/share/avethyos/homebrew
chown -R root:root /usr/share/avethyos/homebrew
rm -rf /var/home/linuxbrew

install -Dm755 /ctx/homebrew/bootstrap.sh /usr/libexec/avethyos-homebrew-bootstrap
install -Dm755 /ctx/homebrew/brew.sh /usr/libexec/avethyos-homebrew/bin/brew
install -Dm644 /ctx/homebrew/homebrew.service /usr/lib/systemd/system/avethyos-homebrew.service
install -Dm644 /ctx/homebrew/profile.sh /etc/profile.d/avethyos-homebrew.sh
install -Dm644 /ctx/homebrew/environment.conf /etc/environment.d/60-avethyos-homebrew.conf
install -Dm440 /ctx/homebrew/sudoers /etc/sudoers.d/avethyos-homebrew
systemctl enable avethyos-homebrew.service
