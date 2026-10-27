#!/usr/bin/env bash
# Run on the new Mint install, from the copied 3-linux folder:
#   sudo bash 1-system-setup.sh
# Installs English + a second language (English default), Chrome, LibreOffice, PDF reader, printer drivers, fonts,
# and the fixes old Macs need (each one only runs when its hardware is present).
# Time zone is left as chosen in the installer. English only by default; for a second language the user can switch
# to in Settings > Languages, pass it: sudo LANG2=es_CO bash 1-system-setup.sh   (or fr_FR, de_DE, pt_BR, ...)
# IOMMU_OFF=1 adds intel_iommu=off, for the Marvell SSDs in some 2013-14 Macs that otherwise fail to boot.
set -uo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
log() { printf '\n==> %s\n' "$*"; }
has_pci() { lspci -nn | grep -qi "$1"; }
APPLE=$(grep -qi apple /sys/class/dmi/id/sys_vendor 2>/dev/null && echo 1 || echo 0)
LANG2="${LANG2:-}"; L2="${LANG2%%_*}"

if [ -n "${IOMMU_OFF:-}" ]; then
  log "SSD: Intel IOMMU off (some Marvell 88SS9183 SSDs in 2013-14 MacBook Air/Pro fail to IDENTIFY with it on)"
  grep -q intel_iommu=off /etc/default/grub || sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&intel_iommu=off /' /etc/default/grub
elif has_pci '1b4b:9183'; then
  echo "   Marvell 88SS9183 SSD: if it fails to boot with 'failed to IDENTIFY' errors (seen on Toshiba TS0256F), re-run with IOMMU_OFF=1"
fi
# SATA link power saving depends on who made the SSD: Toshiba (APPLE SSD TS...) drops the link with it on (freezes
# after ~1 h), SanDisk (APPLE SSD SD...) drops it with it OFF (errors within a minute, link slows to 1.5 Gb/s).
# LPM_OFF=1 / LPM_OFF=0 overrides the guess.
SSD=$(cat /sys/block/sda/device/model 2>/dev/null)
if [ "${LPM_OFF:-}" = 1 ] || { [ -z "${LPM_OFF:-}" ] && [[ "$SSD" == "APPLE SSD TS"* ]]; }; then
  log "SSD ($SSD): drops the SATA link (freezes, I/O errors) with link power saving on - keep it off"
  grep -q mobile_lpm_policy /etc/default/grub || sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&ahci.mobile_lpm_policy=1 /' /etc/default/grub
elif [ "${LPM_OFF:-}" = 0 ]; then
  sed -i 's/ahci.mobile_lpm_policy=1 //' /etc/default/grub
fi
update-grub

if has_pci 'Network controller.*Broadcom'; then
  log "Wi-Fi driver (Broadcom, e.g. BCM4360) + power saving off"
  lsmod | grep -q '^wl ' || apt-get install -y bcmwl-kernel-source || echo "!! Wi-Fi driver failed - use Driver Manager"
fi
printf '[connection]\nwifi.powersave = 2\n' > /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf

log "Update system"
apt-get update && apt-get -y full-upgrade

log "English${LANG2:+ (default) + $LANG2, switchable in Settings > Languages}"
apt-get install -y language-pack-en language-pack-gnome-en hunspell-en-us || true
[ -z "$LANG2" ] || apt-get install -y "language-pack-$L2" "language-pack-gnome-$L2" "hunspell-$L2" || true
locale-gen en_US.UTF-8 ${LANG2:+"$LANG2.UTF-8"}
update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en

log "Microsoft fonts so Word documents look the same"
echo 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' | debconf-set-selections
apt-get install -y ttf-mscorefonts-installer fonts-crosextra-carlito fonts-crosextra-caladea fonts-inter   # Inter: open stand-in for Apple's SF Pro

log "Office (English${L2:+ + $L2}), Mac-look dock, tools"
apt-get install -y libreoffice libreoffice-help-en-us mythes-en-us \
  plank git sassc libglib2.0-dev-bin libxml2-utils xdotool \
  convmv rsync openssh-server
[ -z "$L2" ] || apt-get install -y "libreoffice-l10n-$L2" "libreoffice-help-$L2" "hyphen-$L2" "mythes-$L2" || true

log "iPhone photos (HEIC) open and show thumbnails like JPGs"
apt-get install -y heif-gdk-pixbuf heif-thumbnailer || true

log "Chrome"
DEB=google-chrome-stable_current_amd64.deb
[ -f "$DEB" ] || wget -q -O "/tmp/$DEB" "https://dl.google.com/linux/direct/$DEB"
apt-get install -y "./$DEB" 2>/dev/null || apt-get install -y "/tmp/$DEB"

log "Make LibreOffice save in Word/Excel formats by default"
P=/usr/lib/libreoffice/share/registry   # every .xcd here is loaded at startup
cat > "$P/msformats.xcd" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:data xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:oor="http://openoffice.org/2001/registry">
<dependency file="main"/>
<oor:component-data oor:name="Setup" oor:package="org.openoffice">
 <node oor:name="Office"><node oor:name="Factories">
  <node oor:name="com.sun.star.text.TextDocument"><prop oor:name="ooSetupFactoryDefaultFilter"><value>MS Word 2007 XML</value></prop></node>
  <node oor:name="com.sun.star.sheet.SpreadsheetDocument"><prop oor:name="ooSetupFactoryDefaultFilter"><value>Calc MS Excel 2007 XML</value></prop></node>
  <node oor:name="com.sun.star.presentation.PresentationDocument"><prop oor:name="ooSetupFactoryDefaultFilter"><value>Impress MS PowerPoint 2007 XML</value></prop></node>
 </node></node>
</oor:component-data>
</oor:data>
EOF
log "Make Chrome the default browser"
update-alternatives --set x-www-browser /usr/bin/google-chrome-stable || true

log "Printers: common Epson (escpr) and Canon/other (gutenprint) drivers"
apt-get install -y printer-driver-escpr printer-driver-gutenprint
echo "   Newer Canon inkjets (e.g. G2010): if not auto-detected, use Canon's 'cnijfilter2' driver"

if [ "$APPLE" = 1 ]; then
  log "Mac fan control (mbpfan)"
  apt-get install -y mbpfan && systemctl enable --now mbpfan
fi
if has_pci '14e4:1570'; then
  log "FaceTime HD camera (third-party facetimehd driver, rebuilt by DKMS on kernel updates)"
  apt-get install -y dkms build-essential "linux-headers-$(uname -r)" curl xz-utils cpio
  F=/tmp/facetimehd
  [ -d "$F/firmware" ] || git clone -q --depth 1 https://github.com/patjak/facetimehd-firmware.git "$F/firmware"
  [ -d "$F/driver" ] || git clone -q --depth 1 https://github.com/patjak/facetimehd.git "$F/driver"
  (cd "$F/firmware" && make && make install) || echo "!! camera firmware failed"
  V=$(grep -oP '^PACKAGE_VERSION="?\K[^"]+' "$F/driver/dkms.conf")
  rm -rf "/usr/src/facetimehd-$V" && cp -r "$F/driver" "/usr/src/facetimehd-$V"
  # On a re-run it's already added/installed (captured, not piped to grep -q: SIGPIPE fails it under pipefail)
  { [ -n "$(dkms status -m facetimehd -v "$V" 2>/dev/null)" ] || dkms add -m facetimehd -v "$V"; } &&
    { [[ "$(dkms status -m facetimehd -v "$V" -k "$(uname -r)" 2>/dev/null)" == *installed* ]] || dkms install -m facetimehd -v "$V"; } &&
    modprobe facetimehd || echo "!! camera driver failed (check kernel support)"
fi

log "Login screen: macOS Sonoma-style wallpaper (WhiteSur recreation)"
W=/tmp/whitesur-wallpapers
[ -d "$W" ] || git clone -q --depth 1 https://github.com/vinceliuice/WhiteSur-wallpapers.git "$W"
install -D -m 644 "$W/4k/Sonoma-light.jpg" /usr/share/backgrounds/macos/Sonoma-light.jpg
[ -f /etc/lightdm/slick-greeter.conf ] || printf '[Greeter]\n' > /etc/lightdm/slick-greeter.conf
sed -i '/^background=/d;/^draw-user-backgrounds=/d' /etc/lightdm/slick-greeter.conf
sed -i '/^\[Greeter\]/a background=/usr/share/backgrounds/macos/Sonoma-light.jpg\ndraw-user-backgrounds=false' /etc/lightdm/slick-greeter.conf

log "Log in with a password (no autologin), so the keyring unlocks itself and never prompts"
sed -i -E 's/^(\s*autologin-user)/#\1/' /etc/lightdm/lightdm.conf 2>/dev/null || true

log "Automatic updates (security + kernel) via Mint Update Manager"
mintupdate-automation upgrade enable || true
mintupdate-automation autoremove enable || true

log "Done. Reboot, then run 2-restore-files.sh as the normal user (no sudo)."
