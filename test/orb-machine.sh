#!/usr/bin/env bash
# On a Mac with OrbStack: build a Linux Mint 22.3 Xfce test machine (amd64, runs under Rosetta) to try mintosh on.
#   bash test/orb-machine.sh            # creates "mintosh-test" with a user "alex"
# Then: orb -m mintosh-test -u root bash test/desktop.sh   (virtual 1366x768 desktop + VNC on mintosh-test.orb.local:5900)
# Mint 22.3 is Ubuntu 24.04 plus Mint's repository, so this is Ubuntu 24.04 with Mint's Xfce desktop on top.
set -euo pipefail
M="${MACHINE:-mintosh-test}"
orb list | grep -q "^$M " || orb create -a amd64 --user alex ubuntu:noble "$M"
orb -m "$M" -u root bash -s <<'IN'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq wget ca-certificates gnupg >/dev/null
cd /tmp && wget -q -r -l1 -nd -A "linuxmint-keyring_*_all.deb" http://packages.linuxmint.com/pool/main/l/linuxmint-keyring/
dpkg -i "$(ls linuxmint-keyring_*.deb | sort -V | tail -1)"
echo "deb http://packages.linuxmint.com zena main upstream import backport" > /etc/apt/sources.list.d/linuxmint.list
printf "Package: *\nPin: origin packages.linuxmint.com\nPin-Priority: 700\n" > /etc/apt/preferences.d/linuxmint
apt-get update -qq
apt-get install -y mint-meta-xfce xserver-xorg-video-dummy xserver-xorg-input-libinput x11vnc xdotool wmctrl \
  imagemagick python3-evdev xclip libinput-tools
echo "alex ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alex   # test machine only: lets the scripts' sudo steps run unattended
IN
echo "Ready. Next: orb -m $M -u root bash test/desktop.sh"
