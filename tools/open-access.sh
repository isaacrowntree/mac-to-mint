#!/usr/bin/env bash
# On THIS Mac: offer temporary SSH + password-free sudo access to a Mint machine on the same network.
#   bash tools/open-access.sh            # leave running; Ctrl+C when the other machine has run the command
# On the Mint machine (Terminal), run the wget line it prints; it asks for that user's password once.
# Undo everything afterwards with: bash tools/close-access.sh user@ip
# No way in to the Mint machine (phone USB tethering, guest network)? TUNNEL=1 bash tools/open-access.sh
#   makes it hold a reverse tunnel to this Mac instead (needs Remote Login on here). Then use user@mintosh,
#   with this in ~/.ssh/config:  Host mintosh / HostName localhost / Port 2222 / HostKeyAlias mintosh
set -euo pipefail
KEY="${KEY:-$HOME/.ssh/mintosh}"
PORT="${PORT:-8765}"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C mintosh -f "$KEY"
IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
TUNNEL="${TUNNEL:-}"
if [ -n "$TUNNEL" ]; then
  nc -z -G 2 127.0.0.1 22 || { echo "Turn on Remote Login (System Settings > General > Sharing) first"; exit 1; }
  TKEY="$KEY-tunnel"
  [ -f "$TKEY" ] || ssh-keygen -q -t ed25519 -N "" -C mintosh-tunnel -f "$TKEY"
  # The Mint machine gets this key, so it may only open localhost:2222 here: no shell, no other forwards
  LINE="restrict,port-forwarding,permitlisten=\"localhost:2222\",permitopen=\"localhost:1\",command=\"/usr/bin/false\" $(cat "$TKEY.pub")"
  mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  grep -qF "$(cut -d' ' -f2 "$TKEY.pub")" ~/.ssh/authorized_keys || echo "$LINE" >> ~/.ssh/authorized_keys
fi
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cat > "$D/grant-access.sh" <<EOF
#!/usr/bin/env bash
# Temporary access for setup from $(scutil --get ComputerName 2>/dev/null || hostname). Undone with tools/close-access.sh.
set -e
K='$(cat "$KEY.pub")'
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qxF "\$K" ~/.ssh/authorized_keys 2>/dev/null || echo "\$K" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "Enter the password for \$USER if asked:"
echo "\$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-mintosh-setup >/dev/null
sudo chmod 440 /etc/sudoers.d/99-mintosh-setup
sudo visudo -cf /etc/sudoers.d/99-mintosh-setup
dpkg -s openssh-server >/dev/null 2>&1 || sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh
EOF
[ -z "$TUNNEL" ] || cat >> "$D/grant-access.sh" <<EOF
umask 077
cat > ~/.ssh/mintosh-tunnel <<'KEY'
$(cat "$TKEY")
KEY
sudo tee /etc/systemd/system/mintosh-tunnel.service >/dev/null <<UNIT
[Unit]
Description=Temporary setup tunnel to $(whoami)@$IP (tools/close-access.sh removes it)
After=network-online.target ssh.service
Wants=network-online.target
[Service]
User=\$USER
ExecStart=/usr/bin/ssh -N -i \$HOME/.ssh/mintosh-tunnel -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -R 2222:localhost:22 $(whoami)@$IP
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now mintosh-tunnel
EOF
cat >> "$D/grant-access.sh" <<EOF
echo
echo "Done. This computer's address: \$(hostname -I)${TUNNEL:+ (and a tunnel to $IP is running)}"
EOF
echo "On the Mint machine, open Terminal and run:"
echo
echo "  wget -qO- http://$IP:$PORT/grant-access.sh | bash"   # wget: always on Mint, curl may not be
echo
cd "$D" && python3 -m http.server "$PORT" --bind 0.0.0.0
