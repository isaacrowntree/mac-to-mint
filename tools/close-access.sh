#!/usr/bin/env bash
# On THIS Mac: undo tools/open-access.sh on the Mint machine and delete the key here.
#   bash tools/close-access.sh user@ip
# Removes the key from authorized_keys, then (a few seconds later, from a systemd unit, so this SSH session
# isn't cut off half-way) turns SSH off and deletes the password-free sudo rule and the TUNNEL=1 tunnel.
# Through the tunnel: bash tools/close-access.sh user@mintosh
set -euo pipefail
DEST="${1:?usage: $0 user@ip}"
KEY="${KEY:-$HOME/.ssh/mintosh}"
PUB=$(cut -d' ' -f2 "$KEY.pub")
ssh -o IdentitiesOnly=yes -i "$KEY" "$DEST" "
  sed -i '\#$PUB#d' ~/.ssh/authorized_keys
  rm -f ~/.ssh/mintosh-tunnel
  sudo systemd-run --on-active=5 --unit=close-access-\$(date +%s) \
    sh -c 'systemctl disable --now ssh.socket ssh mintosh-tunnel; rm -f /etc/sudoers.d/99-mintosh-setup /etc/systemd/system/mintosh-tunnel.service; systemctl daemon-reload'
  echo 'Access removed on the Mint machine.'"
sleep 10
if [ "${DEST#*@}" = mintosh ]; then
  if nc -z -G 3 127.0.0.1 2222 2>/dev/null; then echo "!! The tunnel is still open"; else echo "Tunnel is closed."; fi
elif nc -z -G 3 "${DEST#*@}" 22 2>/dev/null; then echo "!! SSH still answers on ${DEST#*@}"; else echo "SSH is off."; fi
if [ -f "$KEY-tunnel.pub" ]; then
  sed -i '' "\#$(cut -d' ' -f2 "$KEY-tunnel.pub")#d" ~/.ssh/authorized_keys 2>/dev/null || true
  rm -f "$KEY-tunnel" "$KEY-tunnel.pub"
  echo "Tunnel key removed from this Mac's authorized_keys."
fi
rm -f "$KEY" "$KEY.pub"
echo "Key deleted on this Mac."
