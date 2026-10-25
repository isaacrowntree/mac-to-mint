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
X xfwm4 /general/show_dock_shadow bool false   # else a grey line runs across the screen at the top of Plank's (zoom) area
X xfwm4 /general/double_click_action string maximize

log "Apple menu (top left) like macOS: About, System Settings, App Store, Force Quit, Sleep, Restart, Shut Down, Lock, Log Out"
# Logo taken from the WhiteSur source at run time (not stored in this repo); dark grey to match a light menu bar.
# Apps are opened from the dock, Launchpad (F4) and Spotlight (⌘Space), as on a Mac - not from this menu.
# The source draws the logo in the middle of a 48 px canvas; crop it (logo spans x 9-39, y 6-42) so at the bar's
# 18 px icon size it is ~17 px tall, the same share of the bar as on macOS
sed 's/width="48" height="48"/width="38" height="38" viewBox="5 5 38 38"/' \
  "$T/WhiteSur-gtk-theme/src/assets/gnome-shell/activities-black/activities-apple.svg" > "$I/apple-menu.svg" \
  || echo "   (Apple logo not found in the WhiteSur source)"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
cat > "$B/acerca-de" <<'EOF'
#!/usr/bin/env bash
# "About This Mac"-style window
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
cpu=$(lscpu | sed -n 's/^Model name: *//p; s/^Nombre del modelo: *//p' | head -1)
mem=$(awk '/MemTotal/{printf "%.0f GB", $2/1048576}' /proc/meminfo)
os=$(lsb_release -ds 2>/dev/null)
disk=$(df -h --output=avail / | tail -1 | tr -d ' ')
case "${LANG:-}" in
  es*) t="Acerca de este equipo"; txt="<b>$model</b>\n\nSistema:  $os\nProcesador:  $cpu\nMemoria:  $mem\nDisco libre:  $disk" ;;
  *)   t="About This Computer";   txt="<b>$model</b>\n\nSystem:  $os\nProcessor:  $cpu\nMemory:  $mem\nDisk free:  $disk" ;;
esac
zenity --info --title="$t" --text="$txt" --width=420
EOF
cat > "$B/apple-action" <<'EOF'
#!/usr/bin/env bash
# Apple menu actions that ask first, like macOS's "Are you sure you want to restart?"
es=0; case "${LANG:-}" in es*) es=1;; esac
case "$1" in
  restart)  q=("Are you sure you want to restart your computer now?" "¿Seguro que desea reiniciar el equipo ahora?"); a=--reboot ;;
  shutdown) q=("Are you sure you want to shut down your computer now?" "¿Seguro que desea apagar el equipo ahora?"); a=--halt ;;
  logout)   q=("Are you sure you want to quit all applications and log out now?" "¿Seguro que desea cerrar todas las aplicaciones y la sesión ahora?"); a=--logout ;;
  *) exit 1 ;;
esac
zenity --question --text="${q[$es]}" --ok-label="$([ $es = 1 ] && echo Aceptar || echo OK)" \
  --cancel-label="$([ $es = 1 ] && echo Cancelar || echo Cancel)" && exec xfce4-session-logout "$a"
EOF
chmod +x "$B/acerca-de" "$B/apple-action"
# The menu is Xfce's Applications Menu button pointed at a custom menu file: a real menu, text only, with
# separators like macOS. Its entries live outside ~/.local/share/applications so Spotlight/Launchpad don't list them.
rm -rf "$A/apple-menu"   # earlier version of this menu
AM="$HOME/.local/share/apple-menu"; mkdir -p "$AM" "$HOME/.config/menus"
# The panel re-reads these files as soon as they change, so write a copy and swap it in (only if different):
# a half-written menu file pops up "Could not load the applications menu"
put() { cat > "$1.tmp"; if cmp -s "$1.tmp" "$1"; then rm -f "$1.tmp"; else mv "$1.tmp" "$1"; fi; }
am() {  # file, English name, Spanish name, command, icon (monochrome, like the SF Symbols in macOS Tahoe's menus)
  printf '[Desktop Entry]\nType=Application\nName=%s\nName[es]=%s\nExec=%s\nIcon=%s\nCategories=X-AppleMenu;\n' \
    "$2" "$3" "$4" "$5" | put "$AM/$1.desktop"
}
am about     "About This Computer" "Acerca de este equipo"      "$B/acerca-de"                   help-about-symbolic
am settings  "System Settings…"    "Configuración del sistema…" xfce4-settings-manager           emblem-system-symbolic
am store     "App Store…"          "Tienda de aplicaciones…"    mintinstall                      system-software-install-symbolic
am forcequit "Force Quit…"         "Forzar salida…"             xfce4-taskmanager                process-stop-symbolic
am sleep     "Sleep"               "Reposo"                     "xfce4-session-logout --suspend" weather-clear-night-symbolic
am restart   "Restart…"            "Reiniciar…"                 "$B/apple-action restart"        system-reboot-symbolic
am shutdown  "Shut Down…"          "Apagar…"                    "$B/apple-action shutdown"       system-shutdown-symbolic
am lock      "Lock Screen"         "Bloquear pantalla"          xflock4                          system-lock-screen-symbolic
am logout    "Log Out…"            "Cerrar sesión…"             "$B/apple-action logout"         system-log-out-symbolic
APPLE_MENU="$HOME/.config/menus/apple-menu.menu"
put "$APPLE_MENU" <<EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN" "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Apple</Name>
  <AppDir>$AM</AppDir>
  <Include><Category>X-AppleMenu</Category></Include>
  <Layout>
    <Filename>about.desktop</Filename>
    <Separator/>
    <Filename>settings.desktop</Filename>
    <Filename>store.desktop</Filename>
    <Separator/>
    <Filename>forcequit.desktop</Filename>
    <Separator/>
    <Filename>sleep.desktop</Filename>
    <Filename>restart.desktop</Filename>
    <Filename>shutdown.desktop</Filename>
    <Separator/>
    <Filename>lock.desktop</Filename>
    <Filename>logout.desktop</Filename>
  </Layout>
</Menu>
EOF

log "Launchpad: F4 or the dock icon shows all apps full screen (rofi: no memory used while closed)"
mkdir -p "$HOME/.local/share/rofi/themes"
cat > "$HOME/.local/share/rofi/themes/launchpad.rasi" <<'EOF'
* { font: "Inter 12"; background-color: transparent; text-color: #ffffff; }
/* Whole screen (the dock hides itself behind windows, so leaving its strip open showed them); Esc or F4 closes.
   Background: the blurred wallpaper (the launchpad script makes it at screen size), darkened, as on macOS */
window { fullscreen: true; background-color: #2c2c2e; }
mainbox { children: [ inputbar, listview ]; spacing: 36px; padding: 6% 9%; background-color: #00000040; }
inputbar { children: [ entry ]; margin: 0 38%; padding: 6px 12px; border-radius: 8px; background-color: #ffffff26; }
entry { placeholder-color: #ffffffaa; horizontal-align: 0.5; }
listview { columns: 7; lines: 4; flow: horizontal; fixed-columns: true; spacing: 20px; scrollbar: false; }
element { orientation: vertical; padding: 10px 6px; spacing: 8px; border-radius: 14px; }
element selected.normal { background-color: #ffffff33; }
element-icon { size: 64px; horizontal-align: 0.5; }
element-text { horizontal-align: 0.5; text-color: inherit; }
EOF
cat > "$B/launchpad" <<'EOF'
#!/usr/bin/env bash
# Launchpad-style grid of all apps; F4 again or Esc closes it
pkill -x rofi && exit 0
case "${LANG:-}" in es*) ph="Buscar";; *) ph="Search";; esac
# Blurred wallpaper at exactly the screen size, made once (scaling a bigger image left a strip uncovered)
BG="$HOME/.cache/launchpad-bg.jpg"
if [ ! -s "$BG" ] && command -v convert >/dev/null; then
  size=$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}'); size=${size:-1366x768}
  src=/usr/share/backgrounds/macos/login-blur.jpg; [ -f "$src" ] || src="$HOME/.local/share/backgrounds/macos/Sonoma-light.jpg"
  convert "$src" -resize "$size^" -gravity center -extent "$size" -blur 0x20 "$BG" 2>/dev/null
fi
# (rofi refuses a background-image in -theme-str next to another rule, so it goes in a small theme of its own)
T="$HOME/.cache/launchpad.rasi"
{ echo "@import \"$HOME/.local/share/rofi/themes/launchpad.rasi\""; [ -s "$BG" ] && echo "window { background-image: url(\"$BG\", width); }"; } > "$T"
# Apps only, like Launchpad: settings panels and system tools (Terminal...) stay in System Settings / Spotlight
# One click opens an app, as on a Mac (rofi's default is click to select, double-click to open)
exec rofi -show drun -show-icons -drun-use-desktop-cache -drun-display-format '{name}' -theme "$T" \
  -me-select-entry '' -me-accept-entry MousePrimary \
  -drun-categories Office,Network,Graphics,AudioVideo,Audio,Video,Game,Education,Utility \
  -theme-str "entry { placeholder: \"$ph\"; }"
EOF
chmod +x "$B/launchpad"
printf '[Desktop Entry]\nType=Application\nName=Launchpad\nExec=%s\nIcon=view-app-grid\nNoDisplay=true\nStartupNotify=false\n' "$B/launchpad" > "$A/launchpad.desktop"

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

log "Desktop: only the user's own files (no Home / File System / Trash icons), external drives still shown"
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
# Google's coloured Gemini sparkle; the vector one stays sharp at the menu bar's small size
G="$HOME/.local/share/icons/hicolor/512x512/apps"; mkdir -p "$G"
curl -fsSL -o "$I/google-gemini.svg" https://www.gstatic.com/lamda/images/gemini_sparkle_v002_d4735304ff6292a690345.svg \
  || curl -fsSL -o "$G/google-gemini.png" https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png \
  || echo "   (icon download failed; the menu entry uses a generic icon)"
# Menu bar version: the sparkle on a small white circle, so it shows on any wallpaper (blue on blue vanished)
if [ -s "$I/google-gemini.svg" ]; then
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 28 28"><circle cx="14" cy="14" r="14" fill="#fff"/><g transform="translate(5.5 5.5) scale(0.607)">%s</g></svg>\n' \
    "$(sed -e '1s/<svg[^>]*>//' -e 's#</svg>##' "$I/google-gemini.svg" | tr -d '\n')" > "$I/google-gemini-panel.svg"
fi
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
cat > "$A/gemini.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Gemini
Comment=Ask Google's AI assistant
Comment[es]=Pregúntele al asistente de Google
Exec=google-chrome --app=https://gemini.google.com/app
Icon=google-gemini
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
StartupNotify=false
EOF

log "Menu bar right side like macOS Sierra: ES/US, Wi-Fi, volume, battery %, 'Sat 25 Oct 3:42 PM', Search, Gemini (where Siri was)"
# Search (magnifier, opens Spotlight) and Gemini buttons at the far right, as Spotlight and Siri were on macOS 10.12
for f in "spotlight:$B/spotlight" "gemini:gemini.google.com"; do
  grep -qs "^Exec=.*${f#*:}" "$HOME"/.config/xfce4/panel/launcher-*/*.desktop \
    || { xfce4-panel --add=launcher "$A/${f%%:*}.desktop"; sleep 1; }
done
# Left side: Apple menu, then the global menu (below)
apple_menus() { for p in $(plugins applicationsmenu); do
  [ "$(xfconf-query -c xfce4-panel -p "$p/custom-menu-file" 2>/dev/null)" = "$APPLE_MENU" ] && echo "$p"; done; }
if [ -z "$(apple_menus)" ]; then
  before=$(plugins applicationsmenu); xfce4-panel --add=applicationsmenu; sleep 2
  for p in $(plugins applicationsmenu); do
    echo "$before" | grep -qx "$p" || X xfce4-panel "$p/custom-menu-file" string "$APPLE_MENU"
  done
fi
for p in $(apple_menus); do
  X xfce4-panel "$p/custom-menu" bool true
  X xfce4-panel "$p/button-icon" string apple-menu
  X xfce4-panel "$p/show-button-title" bool false
  X xfce4-panel "$p/show-menu-icons" bool true
  X xfce4-panel "$p/show-tooltips" bool false
  X xfce4-panel "$p/show-generic-names" bool false
done
# Panel text: WhiteSur makes it bold; macOS's menu bar is regular weight (the app name next to the logo stays bold)
mkdir -p "$HOME/.config/gtk-3.0"; touch "$HOME/.config/gtk-3.0/gtk.css"
sed -i -e '/mintosh panel/,/mintosh end/d' -e '/mac-to-mint panel/,/mac-to-mint end/d' "$HOME/.config/gtk-3.0/gtk.css"   # (old name too)
cat >> "$HOME/.config/gtk-3.0/gtk.css" <<'EOF'
/* mintosh panel */
.xfce4-panel.background, .xfce4-panel.background button, .xfce4-panel.background button.flat { font-weight: 500; }
/* room around the Apple logo, as on macOS */
.xfce4-panel.background button#applicationmenu-button,
.xfce4-panel.background button.flat#applicationmenu-button { padding: 0 14px 0 18px; }   /* beats WhiteSur's button rule */
/* mintosh end */
EOF
# The Gemini button keeps the icon of the .desktop copy the panel made when it was added; refresh it
[ -s "$I/google-gemini-panel.svg" ] && \
  sed -i -E 's/^Icon=(google-)?gemini$/Icon=google-gemini-panel/' "$HOME"/.config/xfce4/panel/launcher-*/*.desktop 2>/dev/null
sleep 2   # the panel ignores --add while it is still taking in the launchers above
# Global menu (from script 4): the active app's name in bold and its menus (File, Edit, View...) in the top bar,
# taken out of the app's window, as on a Mac. Works for Chrome, LibreOffice, Files and other GTK apps.
if [ -f /usr/share/xfce4/panel/plugins/appmenu.desktop ]; then
  X xsettings /Gtk/ShellShowsMenubar bool true
  X xsettings /Gtk/ShellShowsAppmenu bool true
  # The module reaches apps through GTK_MODULES, set at login by the package's systemd user unit. Don't also add it
  # through xsettings /Gtk/Modules or ~/.xsessionrc: loaded twice, it crashes Chrome on start (segfault).
  xfconf-query -c xsettings -p /Gtk/Modules -r 2>/dev/null || true
  sed -i '/appmenu-gtk-module/d' "$HOME/.xsessionrc" 2>/dev/null || true
  if [ -z "$(plugins appmenu)" ]; then
    xfce4-panel -r; sleep 5   # a running panel doesn't see plugins installed after it started
    xfce4-panel --add=appmenu; sleep 2
  fi
  for p in $(plugins appmenu); do
    X xfce4-panel "$p/bold-application-name" bool true   # "Google Chrome" in bold, then Archivo, Edición...
    X xfce4-panel "$p/compact-mode" bool false
  done
fi
# Keyboard indicator: add if missing, show text instead of a flag. Languages button: removed (Settings > Languages).
[ -n "$(plugins xkb)" ] || xfce4-panel --add=xkb
for p in $(plugins xkb); do
  X xfce4-panel "$p/display-type" uint 1; X xfce4-panel "$p/display-name" uint 0
  X xfce4-panel "$p/display-scale" uint 55     # text fills the bar height at 100 %
done
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
keep=(); declare -A bytype=() first=()
for id in $ids; do
  t=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null)
  # A Mac menu bar has no app shortcuts (they're in the dock): drop Mint's Languages, Firefox, Terminal, Files
  # launchers and the show-desktop button. Also the Windows-style window buttons (the dock shows open apps), the
  # Whisker app menu (replaced by the Apple menu + Launchpad) and the small fixed gaps between them.
  if [ "$t" = showdesktop ] || [ "$t" = tasklist ] || [ "$t" = whiskermenu ] || [ "$t" = windowck-plugin ] \
     || { [ "$t" = launcher ] && grep -qs "^Exec=$B/acerca-de" "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; } \
     || { [ "$t" = separator ] && [ "$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/expand" 2>/dev/null)" != true ]; } \
     || { [ "$t" = launcher ] && grep -qsE "^Exec=(mintlocale|firefox|xfce4-terminal|thunar)( |$)" \
          "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; }; then
    xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" -r -R; rm -rf "$HOME/.config/xfce4/panel/launcher-$id"
    continue
  fi
  if [ "$t" = launcher ] && grep -qs "^Exec=$B/spotlight" "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; then t=search; fi
  if [ "$t" = launcher ] && grep -qs "gemini.google.com" "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; then t=gemini; fi
  if [ "$t" = applicationsmenu ] && [ "$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/custom-menu-file" 2>/dev/null)" = "$APPLE_MENU" ]; then
    t=applemenu
  fi
  case "$t" in
    applemenu|appmenu) first[$t]="$id ";;
    xkb|systray|xapp-status-plugin|pulseaudio|power-manager-plugin|notification-plugin|clock|search|gemini) bytype[$t]+="$id ";;
    *) keep+=("$id");;
  esac
done
keep=(${first[applemenu]:-} ${first[appmenu]:-} "${keep[@]}")
for t in xkb systray xapp-status-plugin pulseaudio power-manager-plugin notification-plugin clock search gemini; do keep+=(${bytype[$t]:-}); done
if [ ${#keep[@]} -gt 0 ]; then
  args=(); for id in "${keep[@]}"; do args+=(-t int -s "$id"); done
  xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids --force-array "${args[@]}" || echo "   (could not reorder the panel)"
fi
# Launcher folders left behind by removed launchers (their ids get reused by other plugins)
live=" $(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | grep -E '^[0-9]+$' | tr '\n' ' ') "
for d in "$HOME"/.config/xfce4/panel/launcher-*; do
  [[ "$live" == *" ${d##*-} "* ]] && [ "$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${d##*-}" 2>/dev/null)" = launcher ] \
    || rm -rf "$d"
done

log "Dock (Plank) with the everyday apps"
PT="$(find "$T/WhiteSur-gtk-theme" -type d -path '*plank*' -name '*Light*' | head -1)"
if [ -n "$PT" ]; then mkdir -p "$HOME/.local/share/plank/themes/WhiteSur-Light" && cp -r "$PT"/. "$HOME/.local/share/plank/themes/WhiteSur-Light/"; fi

L="$HOME/.config/plank/dock1/launchers"; mkdir -p "$L"
items=()
for app in thunar launchpad google-chrome libreoffice-writer libreoffice-calc libreoffice-impress xreader; do
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
# Called Finder, as on a Mac (the menu bar shows "Finder" instead of "Gestor de archivos Thunar")
sed -E '/^(Name|GenericName)(\[[^]]*\])?=/d; s/^\[Desktop Entry\]$/&\nName=Finder/' /usr/share/applications/thunar.desktop \
  > "$A/thunar.desktop"
BM="$HOME/.config/gtk-3.0/bookmarks"; mkdir -p "${BM%/*}"; touch "$BM"
for d in DOCUMENTS DOWNLOAD PICTURES MUSIC VIDEOS; do
  p=$(xdg-user-dir "$d"); [ -d "$p" ] && [ "$p" != "$HOME" ] || continue
  u=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$p")
  grep -q "^$u\( \|$\)" "$BM" || echo "$u" >> "$BM"
done

log "Mission Control: three-finger swipe up or down (or F3) opens and closes a view of all open windows; thumb + three fingers: pinch = Launchpad, spread = desktop"
# rofi's window list as a grid of live window previews (nothing runs while it's closed; -window-thumbnail needs
# -show-icons or the previews stay blank). Touchegg (script 4) turns trackpad gestures into these commands.
cat > "$HOME/.local/share/rofi/themes/mission.rasi" <<'EOF'
* { font: "Inter 11"; background-color: transparent; text-color: #ffffff; }
/* only as tall as the rows of windows it shows, so most of the screen is "outside": clicking there closes it
   (rofi can't close on a click on empty space inside its own window) */
window { location: center; width: 86%; border-radius: 16px; background-color: #1c1c1ee8; }
mainbox { children: [ listview ]; padding: 24px; }
listview { fixed-height: false; columns: 3; lines: 2; flow: horizontal; fixed-columns: true; spacing: 28px; scrollbar: false; }
element { orientation: vertical; padding: 8px; spacing: 6px; border-radius: 12px; }
element selected.normal { background-color: #ffffff2e; }
element-icon { size: 240px; horizontal-align: 0.5; }
element-text { horizontal-align: 0.5; text-color: inherit; }
EOF
cat > "$B/mission-control" <<'EOF'
#!/usr/bin/env bash
# Mission Control-style view of all open windows; one click (or Enter) goes to that window
pkill -x rofi && exit 0
exec rofi -show window -show-icons -window-thumbnail -window-format '{t}' -theme mission \
  -me-select-entry '' -me-accept-entry MousePrimary
EOF
chmod +x "$B/mission-control"
cat > "$B/gesto" <<'EOF'
#!/usr/bin/env bash
# macOS thumb-and-three-finger gestures: pinch = Launchpad, spread = show the desktop (pinch again brings windows back)
desk() { wmctrl -m | grep -q '"showing the desktop" mode: ON'; }
case "$1" in
  pinch)  if desk; then wmctrl -k off; else exec "$HOME/.local/bin/launchpad"; fi ;;
  spread) if pkill -x rofi; then :; elif desk; then wmctrl -k off; else wmctrl -k on; fi ;;
esac
EOF
chmod +x "$B/gesto"
mkdir -p "$HOME/.config/touchegg"
cat > "$HOME/.config/touchegg/touchegg.conf" <<EOF
<touchégg>
  <settings>
    <property name="animation_delay">150</property>
    <property name="action_execute_threshold">20</property>
  </settings>
  <application name="All">
    <gesture type="SWIPE" fingers="3" direction="UP">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/mission-control</command><on>begin</on></action>
    </gesture>
    <gesture type="SWIPE" fingers="3" direction="DOWN">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/mission-control</command><on>begin</on></action>
    </gesture>
    <gesture type="PINCH" fingers="4" direction="IN">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/gesto pinch</command><on>begin</on></action>
    </gesture>
    <gesture type="PINCH" fingers="4" direction="OUT">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/gesto spread</command><on>begin</on></action>
    </gesture>
  </application>
</touchégg>
EOF
if command -v touchegg >/dev/null; then pkill -x touchegg; (setsid touchegg >/dev/null 2>&1 < /dev/null &); fi

log "Spotlight: ⌘Space (Super+Space) opens a centred search bar for apps and files (rofi: no memory used while closed)"
mkdir -p "$HOME/.local/share/rofi/themes"
# macOS Sonoma: 680 px bar a quarter of the way down, magnifier, large light text, results only once you type
cat > "$HOME/.local/share/rofi/themes/spotlight.rasi" <<'EOF'
* { font: "Inter 13"; bg: #ececece8; fg: #1d1d1f; dim: #8e8e93; sel: #0a64d6; selfg: #ffffff;
    background-color: transparent; text-color: @fg; }
window { location: north; anchor: north; y-offset: 24%; width: 680px; padding: 0;
         border: 1px; border-color: #00000026; border-radius: 12px; background-color: @bg; }
mainbox { children: [ inputbar, listview ]; spacing: 0; }
inputbar { children: [ icon-search, entry ]; spacing: 10px; padding: 12px 16px; }
icon-search { expand: false; filename: "system-search-symbolic"; size: 22px; vertical-align: 0.5; }
entry { font: "Inter Light 21"; placeholder-color: @dim; vertical-align: 0.5; }
listview { require-input: true; lines: 8; fixed-height: false; scrollbar: false; spacing: 0;
           padding: 6px 8px 8px; border: 1px 0 0 0; border-color: #0000001a; }
element { padding: 5px 10px; spacing: 10px; border-radius: 6px; }
element selected.normal { background-color: @sel; text-color: @selfg; }
element-icon { size: 22px; }
element-text { text-color: inherit; vertical-align: 0.5; highlight: bold; }   /* bold match, no underline */
EOF
cat > "$B/spotlight-files" <<'EOF'
#!/usr/bin/env bash
# rofi script mode: lists the user's documents, photos, music and videos; opens the chosen one.
# Listing takes ~1 s on this Mac, so Spotlight shows the list from the last time and refreshes it in the background.
if [ -n "${ROFI_INFO:-}" ]; then setsid xdg-open "$ROFI_INFO" >/dev/null 2>&1 & exit 0; fi
C="$HOME/.cache/spotlight-files"
if [ -z "${SPOTLIGHT_REFRESH:-}" ]; then
  [ -s "$C" ] || SPOTLIGHT_REFRESH=1 "$0" > "$C"
  cat "$C"
  (SPOTLIGHT_REFRESH=1 "$0" > "$C.new" && mv "$C.new" "$C") >/dev/null 2>&1 &
  exit 0
fi
for d in DESKTOP DOCUMENTS DOWNLOAD PICTURES MUSIC VIDEOS; do xdg-user-dir "$d"; done | sort -u | grep -vx "$HOME" |
while read -r dir; do [ -d "$dir" ] && find "$dir" -type f -not -path '*/.*' 2>/dev/null; done |
while read -r f; do
  case "${f,,}" in
    *.doc|*.docx|*.odt|*.rtf|*.pages) i=x-office-document ;;
    *.xls|*.xlsx|*.ods|*.csv|*.numbers) i=x-office-spreadsheet ;;
    *.ppt|*.pptx|*.pps|*.ppsx|*.odp|*.key) i=x-office-presentation ;;
    *.pdf) i=application-pdf ;;
    *.jpg|*.jpeg|*.png|*.gif|*.heic|*.tif|*.tiff|*.bmp|*.webp) i=image-x-generic ;;
    *.mp3|*.m4a|*.aac|*.wav|*.flac|*.ogg|*.aif|*.aiff) i=audio-x-generic ;;
    *.mp4|*.mov|*.m4v|*.avi|*.mkv|*.3gp|*.wmv) i=video-x-generic ;;
    *) i=text-x-generic ;;
  esac
  printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "${f##*/}" "$i" "$f"
done
EOF
cat > "$B/spotlight" <<'EOF'
#!/usr/bin/env bash
# Spotlight-style search (apps first, then files); pressing the shortcut again closes it
pkill -x rofi && exit 0
case "${LANG:-}" in es*) ph="Búsqueda de Spotlight";; *) ph="Spotlight Search";; esac
# Match app names only (not their commands: "libre" found the Menu Editor, menulibre), best matches first
exec rofi -show combi -combi-modes "drun,files:$HOME/.local/bin/spotlight-files" -combi-hide-mode-prefix \
  -drun-match-fields name,generic,keywords -sort -sorting-method fzf -me-select-entry '' -me-accept-entry MousePrimary \
  -show-icons -drun-display-format '{name}' -theme spotlight -theme-str "entry { placeholder: \"$ph\"; }"
EOF
chmod +x "$B/spotlight" "$B/spotlight-files"
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

log "One desktop, as a Mac starts with (Mint's four meant windows could seem to vanish to another one)"
X xfwm4 /general/workspace_count int 1

log "⌘⌥Esc (Ctrl+Alt+Esc once Toshy maps ⌘) = Force Quit, not Xfce's xkill skull cursor"
X xfce4-keyboard-shortcuts "/commands/custom/<Primary><Alt>Escape" string xfce4-taskmanager

log "Mac top-row keys: F3 = Mission Control, F4 = Launchpad"
X xfce4-keyboard-shortcuts /commands/custom/XF86LaunchA string "$B/mission-control"
X xfce4-keyboard-shortcuts /commands/custom/XF86LaunchB string "$B/launchpad"
# Mint opens its menu on a tap of the ⌘ (Super) key; a Mac does nothing, and with ⌘ shortcuts it would pop up
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/Super_L -r 2>/dev/null || true

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
  # UPower's figure, the one the menu bar shows (this Mac's kernel "capacity" reads ~10 points lower)
  cap=$(upower -i "$(upower -e | grep -m1 BAT)" 2>/dev/null | awk '/percentage/{gsub(/[%,].*/, "", $2); print $2}')
  [ -n "$cap" ] || cap=$(<"$BAT/capacity")
  st=$(<"$BAT/status")
  [ "$st" = Discharging ] || { warned=100; continue; }
  for lvl in 10 20; do
    [ "$cap" -le $lvl ] && [ $warned -gt $lvl ] || continue
    warned=$lvl
    case "${LANG:-}" in
      es*) t="Batería baja"; m="Queda $cap % de batería. Conecte el cargador pronto." ;;
      *)   t="Low Battery";  m="$cap% battery remaining. Plug in to a power outlet soon." ;;
    esac
    notify-send -u normal -t 10000 -i battery-caution -a Battery "$t" "$m"   # goes away by itself after 10 s
    break
  done
done
EOF
chmod +x "$B/aviso-bateria"
printf '[Desktop Entry]\nType=Application\nName=Low battery warning\nExec=%s\nNoDisplay=true\n' "$B/aviso-bateria" \
  > "$HOME/.config/autostart/aviso-bateria.desktop"
pgrep -f "$B/aviso-bateria" >/dev/null || (setsid "$B/aviso-bateria" >/dev/null 2>&1 &)

log "Chrome and Gemini follow the system language (Settings > Languages), checked at each login"
# Chrome keeps the website languages it was given when the profile was made (English here), so Spanish pages and
# Gemini came up in English with a Translate offer. Before Chrome starts, put the system language first.
cat > "$B/chrome-idioma" <<'EOF'
#!/usr/bin/env python3
"""Set Chrome's website languages from the system language. Only while Chrome is closed (it rewrites the file)."""
import json, os, subprocess
if subprocess.run(["pgrep", "-x", "chrome"], capture_output=True).returncode == 0:
    raise SystemExit(0)
lang = (os.environ.get("LANGUAGE") or os.environ.get("LANG") or "en_US").split(":")[0].split(".")[0]
first = lang.replace("_", "-")                      # es-CO
base = first.split("-")[0]                          # es
other = "en" if base != "en" else "es"
want = ",".join(dict.fromkeys([first, base, other]))
for prof in ("Default",):
    p = os.path.expanduser(f"~/.config/google-chrome/{prof}/Preferences")
    if not os.path.exists(p):
        continue
    d = json.load(open(p))
    intl = d.setdefault("intl", {})
    blocked = sorted({base, other} | set(d.get("translate_blocked_languages", [])))
    if (intl.get("accept_languages"), intl.get("selected_languages"), d.get("translate_blocked_languages")) \
            == (want, want, blocked):
        continue
    intl["accept_languages"] = intl["selected_languages"] = want
    # No "Translate this page?" pop-up for the two system languages; the Translate icon in the address bar still works
    d["translate_blocked_languages"] = blocked
    json.dump(d, open(p + ".tmp", "w"))
    os.replace(p + ".tmp", p)
EOF
chmod +x "$B/chrome-idioma"
printf '[Desktop Entry]\nType=Application\nName=Chrome language\nExec=%s\nNoDisplay=true\n' "$B/chrome-idioma" \
  > "$HOME/.config/autostart/chrome-idioma.desktop"
"$B/chrome-idioma" || true

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

# No panel restart here: restarting it can take the Wi-Fi, Bluetooth and update icons down with it
log "Done. Log out and back in to see everything applied."
