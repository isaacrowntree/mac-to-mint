#!/usr/bin/env bash
# On THIS Mac: offer temporary SSH + password-free sudo access to a Mint machine on the same network.
#   bash tools/servir-acceso.sh            # leave running; Ctrl+C when the other machine has run the command
# On the Mint machine (Terminal), run the curl line it prints; it asks for that user's password once.
# Undo everything afterwards with: bash tools/cerrar-acceso.sh user@ip
set -euo pipefail
KEY="${KEY:-$HOME/.ssh/mac-to-mint}"
PORT="${PORT:-8765}"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C mac-to-mint -f "$KEY"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cat > "$D/abrir-acceso.sh" <<EOF
#!/usr/bin/env bash
# Temporary access for setup from $(scutil --get ComputerName 2>/dev/null || hostname). Undone with tools/cerrar-acceso.sh.
set -e
K='$(cat "$KEY.pub")'
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qxF "\$K" ~/.ssh/authorized_keys 2>/dev/null || echo "\$K" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "Enter the password for \$USER if asked:"
echo "\$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-claude-setup >/dev/null
sudo chmod 440 /etc/sudoers.d/99-claude-setup
sudo visudo -cf /etc/sudoers.d/99-claude-setup
dpkg -s openssh-server >/dev/null 2>&1 || sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh
echo
echo "Done. This computer's address: \$(hostname -I)"
EOF
IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
echo "On the Mint machine, open Terminal and run:"
echo
echo "  curl -fsS http://$IP:$PORT/abrir-acceso.sh | bash"
echo
cd "$D" && python3 -m http.server "$PORT" --bind 0.0.0.0
