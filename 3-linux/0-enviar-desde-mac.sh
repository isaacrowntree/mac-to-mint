#!/usr/bin/env bash
# Run on THIS Mac after Mint is installed on the old Mac and SSH is on (sudo apt install openssh-server):
#   BACKUP_DIR=~/backups/<machine> bash 3-linux/0-enviar-desde-mac.sh <user>@<ip>
# Authorizes a temporary key (asks the Linux password once) and copies the organised files + these scripts
# to ~/respaldo-mac on the target. Remove the key from ~/.ssh/authorized_keys on the target when done.
# Without BACKUP_DIR only the scripts go over (re-running scripts 3-5 on a machine that is already set up).
# AVATAR: macOS picture for the login screen (default: Sunflower). Made from this Mac's own copy, never stored in git.
set -euo pipefail
DEST="${1:?usage: $0 user@ip}"
B="${BACKUP_DIR:-}"
KEY="${KEY:-$HOME/.ssh/mintosh}"
HERE="$(cd "$(dirname "$0")" && pwd)"
AVATAR="${AVATAR:-/Library/User Pictures/Flowers/Sunflower.heic}"
[ -z "$B" ] || [ -d "$B/organizado" ] || { echo "Missing $B/organizado (run 2-organize/organize.py first)"; exit 1; }
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C mintosh -f "$KEY"
SSH=(ssh -o IdentitiesOnly=yes -i "$KEY")

if ! "${SSH[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$DEST" true 2>/dev/null; then
  # The reinstall gives the machine a new host key; drop the old macOS one
  ssh-keygen -R "${DEST#*@}" >/dev/null 2>&1 || true
  ssh-copy-id -o IdentitiesOnly=yes -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -i "$KEY.pub" "$DEST"
fi

mkdir -p "$HERE/mac-assets"
if [ -f "$AVATAR" ]; then
  sips -s format png -Z 512 "$AVATAR" --out "$HERE/mac-assets/avatar.png" >/dev/null
else
  echo "No picture at $AVATAR - the login screen keeps the default (pick one in /Library/User Pictures)"
fi

"${SSH[@]}" "$DEST" 'mkdir -p ~/respaldo-mac'
# Only the reorganised copy + scripts go over; the raw backup stays on this Mac.
SRC=("$HERE"); [ -z "$B" ] || SRC=("$B/organizado" "$HERE")
rsync -a --partial --progress -e "${SSH[*]} -o ServerAliveInterval=15" \
  --exclude '_registro/' "${SRC[@]}" "$DEST:respaldo-mac/"

echo
echo "Copied. On the target:"
echo "  cd ~/respaldo-mac/3-linux"
[ -z "$B" ] || echo "  sudo bash 1-configurar-sistema.sh   # then reboot"
[ -z "$B" ] || echo "  bash 2-restaurar-datos.sh"
echo "  bash 3-apariencia-macos.sh"
echo "  sudo bash 4-sistema-macos.sh"
echo "  bash 5-atajos-mac.sh                # then log out and back in"
