#!/usr/bin/env bash
# Run on the new Mint Xfce install as the normal user (NOT sudo), inside the desktop session:
#   bash 3-apariencia-macos.sh
# macOS look: WhiteSur theme/icons/cursor, dock (Plank) at the bottom, menu bar panel at the top,
# window buttons on the left, larger fonts for easier reading. Best effort: each step reports, none is fatal.
set -uo pipefail
export TERM="${TERM:-xterm}"   # the WhiteSur installer calls setterm, which fails without TERM (e.g. over ssh)
log() { printf '\n==> %s\n' "$*"; }
X() { xfconf-query -c "$1" -p "$2" --create -t "$3" -s "$4" || echo "   (could not set $1 $2)"; }
T="$HOME/.cache/whitesur-src"; mkdir -p "$T"

log "Download WhiteSur theme, icons, cursors"
for r in WhiteSur-gtk-theme WhiteSur-icon-theme WhiteSur-cursors; do
  [ -d "$T/$r" ] || git clone -q --depth 1 "https://github.com/vinceliuice/$r.git" "$T/$r"
done

log "Install them (into your home folder, no sudo)"
(cd "$T/WhiteSur-gtk-theme" && ./install.sh -c Light) || echo "   gtk theme install failed - check README flags"
(cd "$T/WhiteSur-icon-theme" && ./install.sh)          || echo "   icon theme install failed"
(cd "$T/WhiteSur-cursors" && ./install.sh)             || echo "   cursor install failed"

log "Apply theme, icons, cursor, bigger fonts"
X xsettings /Net/ThemeName string WhiteSur-Light
X xsettings /Net/IconThemeName string WhiteSur-light   # dark system icons; plain WhiteSur's are white (for dark panels) and vanish in the menu
X xsettings /Gtk/CursorThemeName string WhiteSur-cursors
X xsettings /Gtk/CursorThemeSize int 32
X xsettings /Gtk/FontName string "Inter 12"   # fonts-inter (script 1): open stand-in for SF Pro
X xfwm4 /general/theme string WhiteSur-Light
# Whisker only uses a translucent (rounded, no black corners) window below 100% opacity; WhiteSur's installer
# writes this to the old whiskermenu .rc file, which Xfce 4.18+ ignores
for p in $(xfconf-query -c xfce4-panel -l -v | awk '$2=="whiskermenu"{print $1}'); do X xfce4-panel "$p/menu-opacity" int 95; done
X xfwm4 /general/title_font string "Inter Semi-Bold 12"
X xfce4-keyboard-shortcuts "/commands/custom/<Super>space" string xfce4-popup-whiskermenu   # Spotlight-style search
X xfwm4 /general/button_layout string "CHM|"     # close, minimize, maximize on the left like macOS

log "macOS-style wallpapers (WhiteSur recreations), random, changing every hour"
[ -d "$T/WhiteSur-wallpapers" ] || git clone -q --depth 1 https://github.com/vinceliuice/WhiteSur-wallpapers.git "$T/WhiteSur-wallpapers"
W="$HOME/.local/share/backgrounds/macos"; mkdir -p "$W"
cp "$T"/WhiteSur-wallpapers/2k/*.jpg "$T"/WhiteSur-wallpapers/4k/{Sonoma,Ventura}-*.jpg "$W"/   # 2k lacks Sonoma/Ventura
for p in $(xfconf-query -c xfce4-desktop -l | grep -E "workspace[0-9]+/last-image$"); do
  b=${p%/last-image}
  X xfce4-desktop "$b/last-image" string "$W/Sonoma-light.jpg"
  X xfce4-desktop "$b/image-style" int 5                       # zoomed
  X xfce4-desktop "$b/backdrop-cycle-enable" bool true          # cycles through the folder of last-image
  X xfce4-desktop "$b/backdrop-cycle-period" int 4              # hourly
  X xfce4-desktop "$b/backdrop-cycle-random-order" bool true
done

log "Top panel as a menu bar"
X xfce4-panel /panels/panel-1/position string "p=6;x=0;y=0"
X xfce4-panel /panels/panel-1/size uint 30

log "Dock (Plank) with the everyday apps"
PT="$(find "$T/WhiteSur-gtk-theme" -type d -path '*plank*' -name '*Light*' | head -1)"
if [ -n "$PT" ]; then mkdir -p "$HOME/.local/share/plank/themes/WhiteSur-Light" && cp -r "$PT"/. "$HOME/.local/share/plank/themes/WhiteSur-Light/"; fi

L="$HOME/.config/plank/dock1/launchers"; mkdir -p "$L"
items=()
for app in thunar google-chrome libreoffice-writer libreoffice-calc libreoffice-impress xreader; do
  f=$(ls /usr/share/applications/$app.desktop "$HOME/.local/share/applications/$app.desktop" 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "   (no launcher for $app)"; continue; }
  printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$f" > "$L/$app.dockitem"
  items+=("'$app.dockitem'")
done
# macOS sections: apps | Downloads, Trash. Plank has no separator item, so a launcher with a thin-line icon stands in.
I="$HOME/.local/share/icons/hicolor/scalable/apps"; A="$HOME/.local/share/applications"; mkdir -p "$I" "$A"
cat > "$I/dock-separator.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><rect x="31" y="6" width="2" height="52" rx="1" fill="#000" fill-opacity="0.28"/></svg>
EOF
printf '[Desktop Entry]\nType=Application\nName=\xe2\x80\x8b\nExec=true\nIcon=dock-separator\nNoDisplay=true\n' > "$A/dock-separator.desktop"
printf '[Desktop Entry]\nType=Application\nName=Downloads\nName[es]=Descargas\nExec=thunar "%s"\nIcon=folder-download\nNoDisplay=true\n' "$(xdg-user-dir DOWNLOAD)" > "$A/dock-downloads.desktop"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$A/dock-separator.desktop" > "$L/separator.dockitem"
printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$A/dock-downloads.desktop" > "$L/downloads.dockitem"
printf '[PlankDockItemPreferences]\nLauncher=docklet://trash\n' > "$L/trash.dockitem"
items+=("'separator.dockitem'" "'downloads.dockitem'" "'trash.dockitem'")
D=net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/
gsettings set "$D" dock-items "[$(IFS=,; echo "${items[*]}")]" 2>/dev/null || true
gsettings set "$D" theme 'WhiteSur-Light' 2>/dev/null || true
gsettings set "$D" icon-size 56 2>/dev/null || true
gsettings set "$D" zoom-enabled true 2>/dev/null || true

mkdir -p "$HOME/.config/autostart"
printf '[Desktop Entry]\nType=Application\nName=Plank\nExec=plank\nX-GNOME-Autostart-enabled=true\n' > "$HOME/.config/autostart/plank.desktop"
pgrep -x plank >/dev/null || (plank >/dev/null 2>&1 &)

log "Keyboard: Spanish (matches the Air's keys) + English US, switch with Alt+Shift"
X keyboard-layout /Default/XkbDisable bool false
X keyboard-layout /Default/XkbLayout string "es,us"
X keyboard-layout /Default/XkbVariant string ","
X keyboard-layout /Default/XkbOptions/Group string "grp:alt_shift_toggle"

log "Mac top-row keys: F3 (Mission Control) = list of open windows, F4 (Launchpad) = app menu"
X xfce4-keyboard-shortcuts /commands/custom/XF86LaunchA string "xfdesktop --windowlist"
X xfce4-keyboard-shortcuts /commands/custom/XF86LaunchB string xfce4-popup-whiskermenu

log "On-screen pop-ups for the volume and brightness keys, like macOS"
for p in $(xfconf-query -c xfce4-panel -l -v | awk '$2=="pulseaudio"{print $1}'); do X xfce4-panel "$p/show-notifications" bool true; done
X xfce4-power-manager /xfce4-power-manager/handle-brightness-keys bool true
X xfce4-power-manager /xfce4-power-manager/show-brightness-popup bool true

log "Top right of the panel: Languages button + keyboard layout indicator (click to switch)"
xfconf-query -c xfce4-panel -l -v | grep -q " xkb$" || {
  xfce4-panel --add=launcher /usr/share/applications/mintlocale.desktop
  xfce4-panel --add=xkb
}

log "How-to note on the desktop"
cat > "$(xdg-user-dir DESKTOP)/Change language - Cambiar idioma.txt" <<'EOF'
English -> Español
  Menu > Settings > Languages  (Menú > Configuración > Idiomas)
  Pick "Español (Colombia)", click "Apply System-Wide", then log out and back in.

Español -> English
  Menú > Configuración > Idiomas, elija "English (United States)",
  pulse "Aplicar a todo el sistema" y cierre sesión.

Keyboard / Teclado:  Alt + Shift switches Spanish <-> English keys.
EOF

log "Done. Log out and back in to see everything applied."
