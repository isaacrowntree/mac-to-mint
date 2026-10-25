#!/usr/bin/env bash
# Run on the new Mint Xfce install as the normal user (NOT sudo), inside the desktop session:
#   bash 3-macos-look.sh
# macOS look (macOS 26/27 "Liquid Glass"): MacTahoe theme/icons/cursor in light and dark, see-through menu bar with
# the Apple menu and a global menu, glass dock, Spotlight, Launchpad, Mission Control with Spaces, Finder-like files,
# Mac screenshots, notifications and battery warnings. Safe to re-run. Best effort: each step reports, none is fatal.
# APPEARANCE=light|dark|auto (default auto: light by day, dark at night); change later with: appearance dark
# Then: sudo bash 4-macos-system.sh (boot + login screen, trackpad, glass blur, power) and bash 5-mac-shortcuts.sh.
set -uo pipefail
export TERM="${TERM:-xterm}"   # the theme installers call setterm, which fails without TERM (e.g. over ssh)
log() { printf '\n==> %s\n' "$*"; }
# Set an xfconf value; keep the type of an existing property (a wrong -t on an existing one fails)
X() {
  if xfconf-query -c "$1" -p "$2" >/dev/null 2>&1; then xfconf-query -c "$1" -p "$2" -s "$4"
  else xfconf-query -c "$1" -p "$2" --create -t "$3" -s "$4"; fi || echo "   (could not set $1 $2)"
}
# Restart the panel; if it doesn't (a dialog left open keeps it busy), stop it and start it again
panel_restart() {
  local old; old=$(pgrep -u "$(id -u)" -x xfce4-panel)
  xfce4-panel -r; sleep 5
  if [ -n "$old" ] && [ "$(pgrep -u "$(id -u)" -x xfce4-panel)" = "$old" ]; then
    kill "$old"; sleep 3; kill -0 "$old" 2>/dev/null && { kill -9 "$old"; sleep 3; }   # the session starts it again
    pgrep -u "$(id -u)" -x xfce4-panel >/dev/null || (setsid xfce4-panel >/dev/null 2>&1 < /dev/null &)
    sleep 4
  fi
}
plugins() { xfconf-query -c xfce4-panel -l -v | awk -v t="$1" '$2==t{print $1}'; }   # /plugins/plugin-N of a type
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$HOME/.cache/mintosh-src"; mkdir -p "$T"
I="$HOME/.local/share/icons/hicolor/scalable/apps"; A="$HOME/.local/share/applications"; B="$HOME/.local/bin"
mkdir -p "$I" "$A" "$B" "$HOME/.local/share/mintosh" "$HOME/.config/autostart"
DESK="$(xdg-user-dir DESKTOP)"

# Script 4 installs these too, but the look below needs them now: picom for the glass blur (without it at this point
# the blur is never set up), Wnck for Mission Control, rofi for Spotlight and Launchpad
need=""; for p in picom rofi gir1.2-wnck-3.0 wmctrl xdotool; do dpkg -s "$p" >/dev/null 2>&1 || need="$need $p"; done
if [ -n "$need" ]; then log "Install:$need (asks for your password)"; sudo apt-get install -y $need; fi

log "Download the MacTahoe theme, icons and cursors (vinceliuice's macOS Tahoe recreation) and macOS-style wallpapers"
for r in MacTahoe-gtk-theme MacTahoe-icon-theme WhiteSur-wallpapers; do
  [ -d "$T/$r" ] || git clone -q --depth 1 "https://github.com/vinceliuice/$r.git" "$T/$r"
done

log "Install them, light and dark (into your home folder, no sudo)"
if [ -d "$HOME/.themes/MacTahoe-Light" ] && [ -d "$HOME/.themes/MacTahoe-Dark" ]; then echo "   already installed"; else
  export USER="${USER:-$(id -un)}"   # its installer finds your home folder from this when there's no login (cron, ssh -T)
  (cd "$T/MacTahoe-gtk-theme" && ./install.sh -c light -c dark) || echo "   theme install failed - check its README flags"
  (cd "$T/MacTahoe-icon-theme" && ./install.sh)                   || echo "   icon theme install failed"
  (cd "$T/MacTahoe-icon-theme/cursors" && ./install.sh)           || echo "   cursor install failed"
fi

log "Helper programs (Spotlight, Launchpad, Mission Control, appearance, Apple menu actions, battery warnings...)"
install -m 755 "$HERE"/bin/* "$B"/

log "Fonts, cursor, window buttons"
X xsettings /Gtk/CursorThemeName string MacTahoe-cursors
X xsettings /Gtk/CursorThemeSize int 32
X xsettings /Gtk/FontName string "Inter 12"   # fonts-inter (script 1): open stand-in for SF Pro
X xfwm4 /general/title_font string "Inter Semi-Bold 12"
X xfwm4 /general/button_layout string "CHM|"     # close, minimize, maximize on the left like macOS

log "Windows like macOS: centred titles, soft shadows, double-click the title bar to zoom"
X xfwm4 /general/title_alignment string center
# Compositing: picom (script 4) when installed - it blurs what's behind the glass dock, menus and Spotlight -
# otherwise xfwm's own compositor (shadows, transparency, no blur)
if command -v picom >/dev/null; then
  X xfwm4 /general/use_compositing bool false
  mkdir -p "$HOME/.config/picom"
  # Real GPU: GLX with dual-Kawase blur. No GPU (virtual machines, llvmpipe): XRender with a lighter blur.
  backend=glx; blur='method = "dual_kawase"; strength = 5;'
  glxinfo -B 2>/dev/null | grep -qiE "llvmpipe|softpipe" && { backend=xrender; blur='method = "gaussian"; size = 9; deviation = 4.0;'; }
  cat > "$HOME/.config/picom/picom.conf" <<EOF
# mintosh: Liquid Glass - blur behind translucent windows (dock, menus, Spotlight, notifications), rounded corners
backend = "$backend";
vsync = true;
blur: { $blur };
blur-background = true;
blur-background-frame = false;
blur-background-exclude = [ "window_type = 'desktop'", "_GTK_FRAME_EXTENTS@:c", "class_g = 'Xfdesktop'",
                            "class_g = 'Plank'" ];   # its window is much taller than the dock (room to bounce)
corner-radius = 12;
rounded-corners-exclude = [ "window_type = 'dock'", "window_type = 'desktop'", "class_g = 'Plank'",
                            "class_g = 'Xfce4-panel'", "class_g = 'Rofi'", "_GTK_FRAME_EXTENTS@:c" ];
shadow = true;
shadow-radius = 22; shadow-opacity = 0.32; shadow-offset-x = -20; shadow-offset-y = -14;
shadow-exclude = [ "window_type = 'dock'", "window_type = 'desktop'", "class_g = 'Plank'", "class_g = 'Xfce4-panel'",
                   "class_g = 'Rofi'", "_GTK_FRAME_EXTENTS@:c", "window_type = 'notification'" ];
fading = true; fade-delta = 6; fade-in-step = 0.06; fade-out-step = 0.06;
EOF
  printf '[Desktop Entry]\nType=Application\nName=Glass effects (picom)\nExec=picom\nNoDisplay=true\n' \
    > "$HOME/.config/autostart/picom.desktop"
  pkill -u "$(id -u)" -x picom; sleep 1; (setsid picom >/dev/null 2>&1 < /dev/null &)   # (re)start on the new config
else
  X xfwm4 /general/use_compositing bool true
fi
X xfwm4 /general/show_frame_shadow bool true
X xfwm4 /general/show_popup_shadow bool true
X xfwm4 /general/show_dock_shadow bool false   # else a grey line runs across the screen at the top of Plank's (zoom) area
X xfwm4 /general/double_click_action string maximize

log "Apple menu (top left) like macOS: About, System Settings, App Store, Force Quit, Sleep, Restart, Shut Down, Lock, Log Out"
# Logo taken from the MacTahoe source at run time (not stored in this repo); appearance colours it for light/dark.
# Apps are opened from the dock, Launchpad (F4) and Spotlight (⌘Space), as on a Mac - not from this menu.
# The source draws the logo in the middle of a 48 px canvas; crop it (logo spans x 9-39, y 6-42) so at the bar's
# 18 px icon size it is ~17 px tall, the same share of the bar as on macOS
sed 's/width="48" height="48"/width="38" height="38" viewBox="5 5 38 38"/' \
  "$T/MacTahoe-gtk-theme/src/assets/gnome-shell/activities-black/activities-apple.svg" \
  > "$HOME/.local/share/mintosh/apple-logo.svg" || echo "   (Apple logo not found in the MacTahoe source)"
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
am about     "About This Computer" "Acerca de este equipo"      "$B/about-this-computer"                   help-about-symbolic
am settings  "System Settings…"    "Configuración del sistema…" xfce4-settings-manager           emblem-system-symbolic
am look      "Appearance…"         "Apariencia…"                "$B/appearance --choose"         weather-clear-symbolic
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
    <Filename>look.desktop</Filename>
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

log "Launchpad: F4, the dock icon or a pinch shows all apps full screen (rofi: no memory used while closed)"
printf '[Desktop Entry]\nType=Application\nName=Launchpad\nExec=%s\nIcon=view-app-grid\nNoDisplay=true\nStartupNotify=false\n' "$B/launchpad" > "$A/launchpad.desktop"
# Only real apps, like Launchpad: helpers that run in the background or by themselves (the glass effect, the dock),
# Xfce's run boxes and terminal-only programs stay out (a hidden copy in your apps folder; delete it to bring one back)
for f in picom plank xfce4-appfinder xfce4-run activity-log-manager thunar-bulk-rename vim nvim x11vnc compton; do
  src=/usr/share/applications/$f.desktop
  [ -f "$src" ] && sed -e '/^NoDisplay=/d' -e '/^\[Desktop Entry\]/a NoDisplay=true' "$src" > "$A/$f.desktop"
done
rm -f "$HOME/.cache/rofi-drun-desktop.cache"   # Launchpad and Spotlight keep a list of apps; make it again

log "macOS-style wallpapers (WhiteSur recreations): a light set and a dark set, rotating hourly"
for m in light dark; do
  W="$HOME/.local/share/backgrounds/mintosh/$m"; mkdir -p "$W"
  cp "$T"/WhiteSur-wallpapers/4k/*-"$m".jpg "$W"/ 2>/dev/null
done
for p in $(xfconf-query -c xfce4-desktop -l | grep -E "workspace[0-9]+/last-image$"); do
  b=${p%/last-image}
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

log "Only the menu bar: remove Mint's other panels (Mint 22.3 adds a launcher bar at the bottom; the dock replaces it)"
others=$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' | grep -vx 1)
if [ -n "$others" ]; then
  for n in $others; do
    for id in $(xfconf-query -c xfce4-panel -p "/panels/panel-$n/plugin-ids" 2>/dev/null | grep -E '^[0-9]+$'); do
      xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" -r -R; rm -rf "$HOME/.config/xfce4/panel/launcher-$id"
    done
    xfconf-query -c xfce4-panel -p "/panels/panel-$n" -r -R
  done
  xfconf-query -c xfce4-panel -p /panels --force-array -t int -s 1
fi
# restart it now (also on a re-run): while a second panel is still showing, "xfce4-panel --add" asks which panel
panel_restart

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
    || { timeout 20 xfce4-panel --add=launcher "$A/${f%%:*}.desktop"; sleep 1; }
done
# Left side: Apple menu, then the global menu (below)
apple_menus() { for p in $(plugins applicationsmenu); do
  [ "$(xfconf-query -c xfce4-panel -p "$p/custom-menu-file" 2>/dev/null)" = "$APPLE_MENU" ] && echo "$p"; done; }
if [ -z "$(apple_menus)" ]; then
  before=$(plugins applicationsmenu); timeout 20 xfce4-panel --add=applicationsmenu; sleep 2
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
    panel_restart   # a running panel doesn't see plugins installed after it started
    timeout 20 xfce4-panel --add=appmenu; sleep 2
  fi
  for p in $(plugins appmenu); do
    X xfce4-panel "$p/bold-application-name" bool true   # "Google Chrome" in bold, then Archivo, Edición...
    X xfce4-panel "$p/compact-mode" bool false
  done
fi
# Keyboard indicator: add if missing, show text instead of a flag. Languages button: removed (Settings > Languages).
[ -n "$(plugins xkb)" ] || timeout 20 xfce4-panel --add=xkb
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
  # desktop switcher (Mission Control's Spaces bar does that), the Whisker / Applications menus (replaced by the
  # Apple menu + Launchpad) and the small fixed gaps between them.
  if [ "$t" = showdesktop ] || [ "$t" = tasklist ] || [ "$t" = whiskermenu ] || [ "$t" = windowck-plugin ] \
     || [ "$t" = pager ] \
     || { [ "$t" = applicationsmenu ] \
          && [ "$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/custom-menu-file" 2>/dev/null)" != "$APPLE_MENU" ]; } \
     || { [ "$t" = launcher ] && grep -qs "^Exec=$B/about-this-computer" "$HOME/.config/xfce4/panel/launcher-$id"/*.desktop; } \
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
panel_restart   # a running panel keeps showing plugins removed from its settings until it restarts

log "Dock (Plank) with the everyday apps"

L="$HOME/.config/plank/dock1/launchers"; mkdir -p "$L"
items=()
for app in thunar launchpad google-chrome libreoffice-writer libreoffice-calc libreoffice-impress xreader; do
  f=$(ls /usr/share/applications/$app.desktop "$A/$app.desktop" 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "   (no launcher for $app)"; continue; }
  printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$f" > "$L/$app.dockitem"
  items+=("'$app.dockitem'")
done
# macOS sections: apps | Downloads, Trash. Plank has no separator item, so a launcher with a thin-line icon stands in.
printf '[Desktop Entry]\nType=Application\nName=\xe2\x80\x8b\nExec=true\nIcon=dock-separator\nNoDisplay=true\n' > "$A/dock-separator.desktop"
printf '[Desktop Entry]\nType=Application\nName=Downloads\nName[es]=Descargas\nExec=thunar "%s"\nIcon=folder-download\nNoDisplay=true\n' "$(xdg-user-dir DOWNLOAD)" > "$A/dock-downloads.desktop"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$A/dock-separator.desktop" > "$L/separator.dockitem"
printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$A/dock-downloads.desktop" > "$L/downloads.dockitem"
printf '[PlankDockItemPreferences]\nLauncher=docklet://trash\n' > "$L/trash.dockitem"
items+=("'separator.dockitem'" "'downloads.dockitem'" "'trash.dockitem'")
D=net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/
gsettings set "$D" dock-items "[$(IFS=,; echo "${items[*]}")]" 2>/dev/null || true
gsettings set "$D" icon-size 56 2>/dev/null || true
gsettings set "$D" zoom-enabled true 2>/dev/null || true
gsettings set "$D" current-workspace-only false 2>/dev/null || true

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

log "Mission Control (three-finger swipe up/down, F3, Ctrl+↑): Spaces bar on top, live window previews"
# bin/mission-control (Python + GTK, runs only while open). Desktops: three-finger swipe left/right, Ctrl+←/→,
# or click one in the Spaces bar; + adds one. Thumb + three fingers: pinch = Launchpad, spread = show desktop.
rm -f "$HOME/.local/share/rofi/themes/mission.rasi"   # the earlier rofi version
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
    <gesture type="SWIPE" fingers="3" direction="LEFT">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/gesture left</command><on>begin</on></action>
    </gesture>
    <gesture type="SWIPE" fingers="3" direction="RIGHT">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/gesture right</command><on>begin</on></action>
    </gesture>
    <gesture type="PINCH" fingers="4" direction="IN">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/gesture pinch</command><on>begin</on></action>
    </gesture>
    <gesture type="PINCH" fingers="4" direction="OUT">
      <action type="RUN_COMMAND"><repeat>false</repeat><command>$B/gesture spread</command><on>begin</on></action>
    </gesture>
  </application>
</touchégg>
EOF
if command -v touchegg >/dev/null; then pkill -x touchegg; (setsid touchegg >/dev/null 2>&1 < /dev/null &); fi

log "Spotlight: ⌘Space (Super+Space) opens a centred search bar for apps and files (rofi: no memory used while closed)"
# Toshy (script 5) turns ⌘Space into Super+Space on Mint and into Ctrl+Esc on other Xfce systems (Xubuntu, ...)
X xfce4-keyboard-shortcuts "/commands/custom/<Super>space" string "$B/spotlight"
X xfce4-keyboard-shortcuts "/commands/custom/<Primary>Escape" string "$B/spotlight"

log "Screenshots like macOS: ⌘⇧3 whole screen, ⌘⇧4 an area, saved to the Desktop"
# <Super> = the ⌘ key itself; <Primary> = ⌘ once Toshy (script 5) turns ⌘ shortcuts into Ctrl ones
for m in "<Shift><Super>" "<Primary><Shift>"; do
  X xfce4-keyboard-shortcuts "/commands/custom/${m}3" string "$B/screenshot"
  X xfce4-keyboard-shortcuts "/commands/custom/${m}4" string "$B/screenshot area"
done

log "Keyboard: US English${KBD:+, plus ${KBD%%,*} (switch with Alt+Shift)}"
# English only by default. A second keyboard layout is opt-in: KBD=es bash 3-macos-look.sh  (es, fr, de, latam, ...)
X keyboard-layout /Default/XkbDisable bool false
if [ -n "${KBD:-}" ]; then
  X keyboard-layout /Default/XkbLayout string "$KBD,us"
  X keyboard-layout /Default/XkbVariant string ","
  X keyboard-layout /Default/XkbOptions/Group string "grp:alt_shift_toggle"
else
  X keyboard-layout /Default/XkbLayout string "us"
  X keyboard-layout /Default/XkbVariant string ""
fi

log "Desktops (Spaces): one to start with, as on a Mac; add more from Mission Control's + button"
X xfwm4 /general/workspace_count int 1
X xfwm4 /general/wrap_workspaces bool false
# Ctrl+←/→ switch desktops and Ctrl+↑ opens Mission Control, as on macOS. Toshy (script 5) turns the physical Ctrl
# into Super in apps (Super+←/→; Super+PageUp/PageDown on Ubuntu-based systems) and sends Ctrl+Alt+Home/End in
# terminals. Plain Ctrl+←/→ is left alone: with Toshy that is what ⌥←/→ (jump a word) becomes.
for k in "<Primary><Alt>End:left" "<Primary><Alt>Home:right" "<Super>Left:left" "<Super>Right:right" \
         "<Super>Page_Down:left" "<Super>Page_Up:right"; do
  X xfce4-keyboard-shortcuts "/xfwm4/custom/${k%%:*}" string "${k##*:}_workspace_key"
done
for k in "<Primary>Up" "<Super>Up"; do X xfce4-keyboard-shortcuts "/commands/custom/$k" string "$B/mission-control"; done

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

log "Notifications: glass, top right, gone after 5 s, like macOS banners"
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
printf '[Desktop Entry]\nType=Application\nName=Low battery warning\nExec=%s\nNoDisplay=true\n' "$B/battery-warning" \
  > "$HOME/.config/autostart/battery-warning.desktop"
pgrep -f "$B/battery-warning" >/dev/null || (setsid "$B/battery-warning" >/dev/null 2>&1 &)

log "Chrome and Gemini follow the system language (Settings > Languages), checked at each login"
# Chrome keeps the website languages it was given when the profile was made (English here), so Spanish pages and
# Gemini came up in English with a Translate offer. Before Chrome starts, put the system language first.
printf '[Desktop Entry]\nType=Application\nName=Chrome language\nExec=%s\nNoDisplay=true\n' "$B/chrome-language" \
  > "$HOME/.config/autostart/chrome-language.desktop"
"$B/chrome-language" || true

if [ -n "${KBD:-}" ]; then   # only for two-language setups
log "How-to note on the desktop"
cat > "$DESK/Change language.txt" <<EOF
Display language:  Menu > Settings > Languages, pick the language, click "Apply System-Wide",
                   then log out and back in.
Keyboard:          Alt + Shift switches between ${KBD%%,*} and US English keys (shown in the top bar).
EOF
fi

# No panel restart here: restarting it can take the Wi-Fi, Bluetooth and update icons down with it
# Helpers used to have Spanish names; remove old copies so a re-run on an older install doesn't run two of each
for old in aviso-bateria chrome-idioma acerca-de gesto; do
  rm -f "$B/$old" "$HOME/.config/autostart/$old.desktop"
done
pkill -f "^bash $B/aviso-bateria$" 2>/dev/null || true

log "Appearance: ${APPEARANCE:-auto} (light, dark or auto - change any time with: appearance dark)"
printf '[Desktop Entry]\nType=Application\nName=Appearance\nExec=sh -c "%s; exec %s --watch"\nNoDisplay=true\n' \
  "$B/appearance" "$B/appearance" > "$HOME/.config/autostart/appearance.desktop"
printf '[Desktop Entry]\nType=Application\nName=Appearance: Light\nExec=%s light\nIcon=weather-clear-symbolic\nCategories=Settings;\n' "$B/appearance" > "$A/appearance-light.desktop"
printf '[Desktop Entry]\nType=Application\nName=Appearance: Dark\nExec=%s dark\nIcon=weather-clear-night-symbolic\nCategories=Settings;\n' "$B/appearance" > "$A/appearance-dark.desktop"
printf '[Desktop Entry]\nType=Application\nName=Appearance: Auto\nExec=%s auto\nIcon=preferences-desktop-theme-symbolic\nCategories=Settings;\n' "$B/appearance" > "$A/appearance-auto.desktop"
FORCE=1 "$B/appearance" "${APPEARANCE:-auto}"
# The window manager and panel reloads above can take picom down with them; bring it back
if command -v picom >/dev/null; then
  sleep 2; pgrep -u "$(id -u)" -x picom >/dev/null || (setsid picom >/dev/null 2>&1 < /dev/null &)
fi

log "Done. Log out and back in to see everything applied."
