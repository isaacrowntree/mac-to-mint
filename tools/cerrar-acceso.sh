#!/usr/bin/env bash
# On THIS Mac: undo tools/servir-acceso.sh on the Mint machine and delete the key here.
#   bash tools/cerrar-acceso.sh user@ip
# Removes the key from authorized_keys, then (a few seconds later, from a systemd unit, so this SSH session
# isn't cut off half-way) turns SSH off and deletes the password-free sudo rule.
set -euo pipefail
DEST="${1:?usage: $0 user@ip}"
KEY="${KEY:-$HOME/.ssh/mintosh}"
PUB=$(cut -d' ' -f2 "$KEY.pub")
ssh -o IdentitiesOnly=yes -i "$KEY" "$DEST" "
  sed -i '\#$PUB#d' ~/.ssh/authorized_keys
  sudo systemd-run --on-active=5 --unit=cerrar-acceso-\$(date +%s) \
    sh -c 'systemctl disable --now ssh.socket ssh; rm -f /etc/sudoers.d/99-mintosh-setup'
  echo 'Access removed on the Mint machine.'"
sleep 10
if nc -z -G 3 "${DEST#*@}" 22 2>/dev/null; then echo "!! SSH still answers on ${DEST#*@}"; else echo "SSH is off."; fi
rm -f "$KEY" "$KEY.pub"
echo "Key deleted on this Mac."
