#!/usr/bin/env bash
# Run on THIS Mac after Mint is installed on the old Mac and SSH is on (sudo apt install openssh-server):
#   BACKUP_DIR=~/backups/<machine> bash 3-linux/0-enviar-desde-mac.sh <user>@<ip>
# Authorizes a temporary key (asks the Linux password once) and copies the organised files + these scripts
# to ~/respaldo-mac on the target. Remove the key from ~/.ssh/authorized_keys on the target when done.
set -euo pipefail
DEST="${1:?usage: $0 user@ip}"
B="${BACKUP_DIR:?set BACKUP_DIR to the folder holding organizado/}"
KEY="${KEY:-$HOME/.ssh/mac-to-mint}"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -d "$B/organizado" ] || { echo "Missing $B/organizado (run 2-organize/organize.py first)"; exit 1; }
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C mac-to-mint -f "$KEY"
SSH=(ssh -o IdentitiesOnly=yes -i "$KEY")

# The reinstall gives the machine a new host key; drop the old macOS one
ssh-keygen -R "${DEST#*@}" >/dev/null 2>&1 || true
ssh-copy-id -o IdentitiesOnly=yes -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -i "$KEY.pub" "$DEST"

"${SSH[@]}" "$DEST" 'mkdir -p ~/respaldo-mac'
# Only the reorganised copy + scripts go over; the raw backup stays on this Mac.
rsync -a --partial --progress -e "${SSH[*]} -o ServerAliveInterval=15" \
  --exclude '_registro/' "$B/organizado" "$HERE" "$DEST:respaldo-mac/"

echo
echo "Copied. On the target:"
echo "  cd ~/respaldo-mac/3-linux"
echo "  sudo bash 1-configurar-sistema.sh   # then reboot"
echo "  bash 2-restaurar-datos.sh"
echo "  bash 3-apariencia-macos.sh"
