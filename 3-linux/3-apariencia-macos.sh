#!/usr/bin/env bash
# Run on the new Mint Xfce install as the normal user (NOT sudo), inside the desktop session:
#   bash 3-apariencia-macos.sh
# macOS look: WhiteSur theme/icons/cursor, dock (Plank) at the bottom, menu bar panel at the top with an Apple
# logo and a macOS-style right side, Spotlight-style search, Finder-like file manager, Mac screenshots,
# notifications and battery warnings. Safe to re-run. Best effort: each step reports, none is fatal.
# Then: sudo bash 4-sistema-macos.sh (boot + login screen, trackpad, power) and bash 5-atajos-mac.sh (⌘ shortcuts).
set -uo pipefail
export TERM="${TERM:-xterm}"   # the WhiteSur installer calls setterm, which fails without TERM (e.g. over ssh)
log() { printf '\n==> %s\n' "$*"; }
# Set an xfconf value; keep the type of an existing property (a wrong -t on an existing one fails)
X() {
  if xfconf-query -c "$1" -p "$2" >/dev/null 2>&1; then xfconf-query -c "$1" -p "$2" -s "$4"
  else xfconf-query -c "$1" -p "$2" --create -t "$3" -s "$4"; fi || echo "   (could not set $1 $2)"
}
plugins() { xfconf-query -c xfce4-panel -l -v | awk -v t="$1" '$2==t{print $1}'; }   # /plugins/plugin-N of a type
T="$HOME/.cache/whitesur-src"; mkdir -p "$T"
I="$HOME/.local/share/icons/hicolor/scalable/apps"; A="$HOME/.local/share/applications"; B="$HOME/.local/bin"
mkdir -p "$I" "$A" "$B"
DESK="$(xdg-user-dir DESKTOP)"

log "Download WhiteSur theme, icons, cursors"
for r in WhiteSur-gtk-theme WhiteSur-icon-theme WhiteSur-cursors; do
  [ -d "$T/$r" ] || git clone -q --depth 1 "https://github.com/vinceliuice/$r.git" "$T/$r"
done

log "Install them (into your home folder, no sudo)"
if [ -d "$HOME/.themes/WhiteSur-Light" ]; then echo "   already installed"; else
  (cd "$T/WhiteSur-gtk-theme" && ./install.sh -c Light) || echo "   gtk theme install failed - check README flags"
  (cd "$T/WhiteSur-icon-theme" && ./install.sh)          || echo "   icon theme install failed"
  (cd "$T/WhiteSur-cursors" && ./install.sh)             || echo "   cursor install failed"
fi

log "Apply theme, icons, cursor, bigger fonts"
X xsettings /Net/ThemeName string WhiteSur-Light
X xsettings /Net/IconThemeName string WhiteSur-light   # dark system icons; plain WhiteSur's are white (for dark panels) and vanish in the menu
X xsettings /Gtk/CursorThemeName string WhiteSur-cursors
X xsettings /Gtk/CursorThemeSize int 32
X xsettings /Gtk/FontName string "Inter 12"   # fonts-inter (script 1): open stand-in for SF Pro
X xfwm4 /general/theme string WhiteSur-Light
X xfwm4 /general/title_font string "Inter Semi-Bold 12"
X xfwm4 /general/button_layout string "CHM|"     # close, minimize, maximize on the left like macOS

log "Windows like macOS: centred titles, soft shadows, double-click the title bar to zoom"
X xfwm4 /general/title_alignment string center
X xfwm4 /general/use_compositing bool true      # also needed for rounded menus, Spotlight and notifications
X xfwm4 /general/show_frame_shadow bool true
X xfwm4 /general/show_popup_shadow bool true
X xfwm4 /general/double_click_action string maximize

log "Apple menu: the app menu button shows an Apple logo"
# Taken from the WhiteSur source at run time (not stored in this repo); dark grey to match a light menu bar
cp "$T/WhiteSur-gtk-theme/src/assets/gnome-shell/activities-black/activities-apple.svg" "$I/apple-menu.svg" \
  || echo "   (Apple logo not found in the WhiteSur source)"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
for p in $(plugins whiskermenu); do
  X xfce4-panel "$p/button-icon" string apple-menu
  X xfce4-panel "$p/show-button-icon" bool true
  X xfce4-panel "$p/show-button-title" bool false
  # Whisker only uses a translucent (rounded, no black corners) window below 100% opacity; WhiteSur's installer
  # writes this to the old whiskermenu .rc file, which Xfce 4.18+ ignores
  X xfce4-panel "$p/menu-opacity" int 95
done

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

log "Desktop: only her own files (no Home / File System / Trash icons), external drives still shown"
X xfce4-desktop /desktop-icons/style int 2
X xfce4-desktop /desktop-icons/file-icons/show-home bool false
X xfce4-desktop /desktop-icons/file-icons/show-filesystem bool false
X xfce4-desktop /desktop-icons/file-icons/show-trash bool false
X xfce4-desktop /desktop-icons/file-icons/show-removable bool true

log "Top panel as a menu bar"
X xfce4-panel /panels/panel-1/position string "p=6;x=0;y=0"
X xfce4-panel /panels/panel-1/size uint 30     # already taller than macOS's bar (24); bigger text, not a bigger bar
X xfce4-panel /panels/panel-1/icon-size uint 18

log "Gemini (Google's assistant) as its own app - type, or tap the microphone to talk"
G="$HOME/.local/share/icons/hicolor/512x512/apps"; mkdir -p "$G"
curl -fsSL -o "$G/gemini.png" https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png \
  || echo "   (icon download failed; the menu entry uses a generic icon)"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
cat > "$A/gemini.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Gemini
Comment=Ask Google's AI assistant
Comment[es]=Pregúntele al asistente de Google
Exec=google-chrome --app=https://gemini.google.com/app
Icon=gemini
Categories=Utility;
StartupWMClass=gemini.google.com__app
EOF
cat > "$A/spotlight.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Search
Name[es]=Buscar
Exec=$B/spotlight
Icon=system-search-symbolic
NoDisplay=true
EOF

log "Menu bar right side like macOS Sierra: ES/US, Wi-Fi, volume, battery %, 'Sat 25 Oct 3:42 PM', Search, Gemini (where Siri was)"
# Search (magnifier, opens Spotlight) and Gemini buttons at the far right, as Spotlight and Siri were on her Mac
for f in "spotlight:$B/spotlight" "gemini:gemini.google.com"; do
  grep -qs "^Exec=.*${f#*:}" "$HOME"/.config/xfce4/panel/launcher-*/*.desktop \
    || { xfce4-panel --add=launcher "$A/${f%%:*}.desktop"; sleep 1; }
done
# Keyboard indicator: add if missing, show text instead of a flag. Languages button: removed (Settings > Languages).
[ -n "$(plugins xkb)" ] || xfce4-panel --add=xkb
for p in $(plugins xkb); do X xfce4-panel "$p/display-type" uint 1; X xfce4-panel "$p/display-name" uint 0; done
for p in $(plugins clock); do
  X xfce4-panel "$p/mode" uint 2                                # digital
  X xfce4-panel "$p/digital-layout" uint 3                      # one line (the time format holds the date)
  X xfce4-panel "$p/digital-time-format" string "%a %-d %b  %-l:%M %p"
  X xfce4-panel "$p/digital-time-font" string "Inter 12"         # same size as the menu text
  X xfce4-panel "$p/digital-format" string "%a %-d %b  %-l:%M %p"  # Xfce < 4.18
done
X xfce4-power-manager /xfce4-power-manager/show-panel-label int 1   # battery percentage next to the icon
for p in $(plugins pulseaudio); do X xfce4-panel "$p/show-notifications" bool true; done
ids=$(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | grep -E '^[0-9]+$')
keep=(); declare -A bytype=()
for id in $ids; do
  t=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null)
  if [ "$t" = launcher ] && grep -qs mintlocale "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; then
    xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" -r -R; rm -rf "$HOME/.config/xfce4/panel/launcher-$id"
    continue
  fi
  if [ "$t" = launcher ] && grep -qs "^Exec=$B/spotlight" "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; then t=search; fi
  if [ "$t" = launcher ] && grep -qs "gemini.google.com" "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; then t=gemini; fi
  case "$t" in
    xkb|systray|pulseaudio|power-manager-plugin|notification-plugin|clock|search|gemini) bytype[$t]+="$id ";;
    *) keep+=("$id");;
  esac
done
for t in xkb systray pulseaudio power-manager-plugin notification-plugin clock search gemini; do keep+=(${bytype[$t]:-}); done
if [ ${#keep[@]} -gt 0 ]; then
  args=(); for id in "${keep[@]}"; do args+=(-t int -s "$id"); done
  xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids --force-array "${args[@]}" || echo "   (could not reorder the panel)"
fi

log "Dock (Plank) with the everyday apps"
PT="$(find "$T/WhiteSur-gtk-theme" -type d -path '*plank*' -name '*Light*' | head -1)"
if [ -n "$PT" ]; then mkdir -p "$HOME/.local/share/plank/themes/WhiteSur-Light" && cp -r "$PT"/. "$HOME/.local/share/plank/themes/WhiteSur-Light/"; fi

L="$HOME/.config/plank/dock1/launchers"; mkdir -p "$L"
items=()
for app in thunar google-chrome libreoffice-writer libreoffice-calc libreoffice-impress xreader; do
  f=$(ls /usr/share/applications/$app.desktop "$A/$app.desktop" 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "   (no launcher for $app)"; continue; }
  printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$f" > "$L/$app.dockitem"
  items+=("'$app.dockitem'")
done
# macOS sections: apps | Downloads, Trash. Plank has no separator item, so a launcher with a thin-line icon stands in.
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
gsettings set "$D" theme 'WhiteSur-Light' 2>/dev/null || true   # its dots under open apps, like macOS
gsettings set "$D" icon-size 56 2>/dev/null || true
gsettings set "$D" zoom-enabled true 2>/dev/null || true
gsettings set "$D" current-workspace-only false 2>/dev/null || true

mkdir -p "$HOME/.config/autostart"
printf '[Desktop Entry]\nType=Application\nName=Plank\nExec=plank\nX-GNOME-Autostart-enabled=true\n' > "$HOME/.config/autostart/plank.desktop"
pgrep -x plank >/dev/null || (plank >/dev/null 2>&1 &)

log "Files (Thunar) like Finder: icon view, folders first, photo previews, sidebar favourites"
X thunar /last-view string ThunarIconView
X thunar /misc-folders-first bool true
X thunar /misc-thumbnail-mode string THUNAR_THUMBNAIL_MODE_ALWAYS
X thunar /last-location-bar string ThunarLocationButtons
X thunar /last-side-pane string ThunarShortcutsPane
BM="$HOME/.config/gtk-3.0/bookmarks"; mkdir -p "${BM%/*}"; touch "$BM"
for d in DOCUMENTS DOWNLOAD PICTURES MUSIC VIDEOS; do
  p=$(xdg-user-dir "$d"); [ -d "$p" ] && [ "$p" != "$HOME" ] || continue
  u=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$p")
  grep -q "^$u\( \|$\)" "$BM" || echo "$u" >> "$BM"
done

log "Spotlight: ⌘Space (Super+Space) opens a centred search bar (rofi: starts on demand, uses no memory when closed)"
mkdir -p "$HOME/.local/share/rofi/themes"
cat > "$HOME/.local/share/rofi/themes/spotlight.rasi" <<'EOF'
* { font: "Inter 15"; bg: #f6f6f6f2; fg: #1d1d1f; dim: #86868b; sel: #0a64d6; selfg: #ffffff;
    background-color: transparent; text-color: @fg; }
window { location: north; anchor: north; y-offset: 22%; width: 620px; padding: 10px;
         border: 1px; border-color: #0000001f; border-radius: 14px; background-color: @bg; }
mainbox { children: [ inputbar, listview ]; spacing: 6px; }
inputbar { children: [ entry ]; padding: 8px 10px; }
entry { placeholder-color: @dim; font: "Inter 19"; }
listview { lines: 7; fixed-height: false; scrollbar: false; spacing: 2px; }
element { padding: 6px 10px; spacing: 12px; border-radius: 8px; }
element selected.normal { background-color: @sel; text-color: @selfg; }
element-icon { size: 28px; }
element-text { text-color: inherit; vertical-align: 0.5; }
EOF
cat > "$B/spotlight" <<'EOF'
#!/usr/bin/env bash
# Spotlight-style app search; pressing the shortcut again closes it
pkill -x rofi && exit 0
case "${LANG:-}" in es*) ph="Buscar";; *) ph="Search";; esac
exec rofi -show drun -show-icons -drun-display-format '{name}' -theme spotlight \
  -theme-str "entry { placeholder: \"$ph\"; }"
EOF
chmod +x "$B/spotlight"
X xfce4-keyboard-shortcuts "/commands/custom/<Super>space" string "$B/spotlight"   # Toshy turns ⌘Space into this

log "Screenshots like macOS: ⌘⇧3 whole screen, ⌘⇧4 an area, saved to the Desktop"
# <Super> = the ⌘ key itself; <Primary> = ⌘ once Toshy (script 5) turns ⌘ shortcuts into Ctrl ones
for m in "<Shift><Super>" "<Primary><Shift>"; do
  X xfce4-keyboard-shortcuts "/commands/custom/${m}3" string "xfce4-screenshooter -f -s $DESK"
  X xfce4-keyboard-shortcuts "/commands/custom/${m}4" string "xfce4-screenshooter -r -s $DESK"
done

log "Keyboard: Spanish (matches the Air's keys) + English US, switch with Alt+Shift"
X keyboard-layout /Default/XkbDisable bool false
X keyboard-layout /Default/XkbLayout string "es,us"
X keyboard-layout /Default/XkbVariant string ","
X keyboard-layout /Default/XkbOptions/Group string "grp:alt_shift_toggle"

log "Mac top-row keys: F3 (Mission Control) = list of open windows, F4 (Launchpad) = app menu"
X xfce4-keyboard-shortcuts /commands/custom/XF86LaunchA string "xfdesktop --windowlist"
X xfce4-keyboard-shortcuts /commands/custom/XF86LaunchB string xfce4-popup-whiskermenu

log "On-screen pop-ups for the volume and brightness keys, like macOS"
X xfce4-power-manager /xfce4-power-manager/handle-brightness-keys bool true
X xfce4-power-manager /xfce4-power-manager/show-brightness-popup bool true

log "Notifications: rounded, light, top right, gone after 5 s, like macOS banners"
N="$HOME/.local/share/themes/macOS/xfce-notify-4.0"; mkdir -p "$N"
cat > "$N/gtk.css" <<'EOF'
#XfceNotifyWindow { background-color: rgba(246, 246, 246, 0.96); border: 1px solid rgba(0, 0, 0, 0.12);
                    border-radius: 14px; padding: 10px 12px; }
#XfceNotifyWindow label#summary { font-weight: 600; color: #1d1d1f; }
#XfceNotifyWindow label#body { color: #3a3a3c; }
#XfceNotifyWindow image#icon { margin-right: 8px; }
#XfceNotifyWindow button { border-radius: 8px; }
EOF
X xfce4-notifyd /theme string macOS
X xfce4-notifyd /notify-location uint 2       # top right
X xfce4-notifyd /expire-timeout int 5
X xfce4-notifyd /do-slideout bool true

log "Battery like macOS: dim a little on battery, sleep at 5 %, warnings at 20 % and 10 %"
P=/xfce4-power-manager
X xfce4-power-manager $P/brightness-on-battery uint 120         # after 2 min idle on battery...
X xfce4-power-manager $P/brightness-level-on-battery uint 40    # ...dim to 40 %
X xfce4-power-manager $P/blank-on-battery int 5
X xfce4-power-manager $P/dpms-on-battery-sleep uint 10
X xfce4-power-manager $P/dpms-on-battery-off uint 15
X xfce4-power-manager $P/inactivity-on-battery uint 30          # sleep after 30 min idle on battery
X xfce4-power-manager $P/inactivity-sleep-mode-on-battery uint 1
X xfce4-power-manager $P/lid-action-on-battery uint 1           # close the lid = sleep, as on a Mac
X xfce4-power-manager $P/lid-action-on-ac uint 1
X xfce4-power-manager $P/critical-power-level uint 5
X xfce4-power-manager $P/critical-power-action uint 1           # sleep (keeps open work) rather than shut down
cat > "$B/aviso-bateria" <<'EOF'
#!/usr/bin/env bash
# macOS-style "Low Battery" warnings at 20 % and 10 % while unplugged (a few KB of memory, checks once a minute)
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1); [ -n "$BAT" ] || exit 0
warned=100
while sleep 60; do
  cap=$(<"$BAT/capacity"); st=$(<"$BAT/status")
  [ "$st" = Discharging ] || { warned=100; continue; }
  for lvl in 10 20; do
    [ "$cap" -le $lvl ] && [ $warned -gt $lvl ] || continue
    warned=$lvl
    case "${LANG:-}" in
      es*) t="Batería baja"; m="Queda $cap % de batería. Conecte el cargador pronto." ;;
      *)   t="Low Battery";  m="$cap% battery remaining. Plug in to a power outlet soon." ;;
    esac
    notify-send -u critical -i battery-caution -a Battery "$t" "$m"
    break
  done
done
EOF
chmod +x "$B/aviso-bateria"
printf '[Desktop Entry]\nType=Application\nName=Low battery warning\nExec=%s\nNoDisplay=true\n' "$B/aviso-bateria" \
  > "$HOME/.config/autostart/aviso-bateria.desktop"
pgrep -f "$B/aviso-bateria" >/dev/null || (setsid "$B/aviso-bateria" >/dev/null 2>&1 &)

log "How-to note on the desktop"
cat > "$DESK/Change language - Cambiar idioma.txt" <<'EOF'
English -> Español
  Menu > Settings > Languages  (Menú > Configuración > Idiomas)
  Pick "Español (Colombia)", click "Apply System-Wide", then log out and back in.

Español -> English
  Menú > Configuración > Idiomas, elija "English (United States)",
  pulse "Aplicar a todo el sistema" y cierre sesión.

Keyboard / Teclado:  Alt + Shift switches Spanish <-> English keys (ES / US in the top bar).
EOF

[ -n "${DISPLAY:-}" ] && xfce4-panel -r >/dev/null 2>&1 &
log "Done. Log out and back in to see everything applied."
