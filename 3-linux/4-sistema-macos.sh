#!/usr/bin/env bash
# Run on the Mint install after 3-apariencia-macos.sh (it uses the WhiteSur files that script downloads):
#   sudo bash 4-sistema-macos.sh
# Mac-like boot (black screen, Apple logo, progress bar, no GRUB menu), Mac-like login screen (blurred wallpaper,
# round account picture, WhiteSur theme), Mac trackpad behaviour, battery saving, and the tools scripts 3/5 use.
# Account picture: 3-linux/mac-assets/avatar.png (0-enviar-desde-mac.sh makes it from a macOS default picture).
# Safe to re-run. Log out (trackpad, login screen) or reboot (boot screen) to see the changes.
set -uo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
U="${SUDO_USER:?run with sudo from the user account}"; UH=$(getent passwd "$U" | cut -d: -f6)
log() { printf '\n==> %s\n' "$*"; }
APPLE=$(grep -qi apple /sys/class/dmi/id/sys_vendor 2>/dev/null && echo 1 || echo 0)
LOGO="$UH/.cache/whitesur-src/WhiteSur-gtk-theme/src/assets/gnome-shell/activities/activities-apple.svg"

log "Tools: Spotlight search (rofi), screenshots, notifications, image tools, battery saver (TLP)"
apt-get install -y rofi xfce4-screenshooter libnotify-bin imagemagick librsvg2-bin plymouth-themes tlp \
  zenity xfce4-appmenu-plugin appmenu-gtk3-module appmenu-gtk2-module appmenu-registrar touchegg

if [ "$APPLE" = 1 ]; then
  log "Battery saver: keep TLP away from the SATA link and Wi-Fi power saving (they freeze Apple SSDs / drop Wi-Fi)"
  cat > /etc/tlp.d/90-apple.conf <<'EOF'
# Apple SSDs drop the SATA link with link power management on (see ahci.mobile_lpm_policy=1 in GRUB)
SATA_LINKPWR_ON_AC="max_performance"
SATA_LINKPWR_ON_BAT="max_performance"
AHCI_RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_BAT=on
# Wi-Fi power saving is off in NetworkManager too (99-wifi-powersave-off.conf)
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=off
EOF
fi
systemctl enable --now tlp

log "Boot screen like a Mac: black, white Apple logo, thin progress bar"
PT=/usr/share/plymouth/themes/macos
if [ -f "$LOGO" ]; then
  mkdir -p "$PT"
  sed 's/fill:#[0-9a-fA-F]\{3,6\}/fill:#ffffff/' "$LOGO" | rsvg-convert -w 112 -h 112 -o "$PT/logo.png"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="5"><rect width="200" height="5" rx="2.5" fill="#%s"/></svg>' 555555 \
    | rsvg-convert -o "$PT/track.png"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="5"><rect width="200" height="5" rx="2.5" fill="#%s"/></svg>' ffffff \
    | rsvg-convert -o "$PT/fill.png"
  cat > "$PT/macos.plymouth" <<EOF
[Plymouth Theme]
Name=macOS
Description=Black screen, Apple logo and a progress bar
ModuleName=script

[script]
ImageDir=$PT
ScriptFile=$PT/macos.script
EOF
  cat > "$PT/macos.script" <<'EOF'
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);
logo = Image("logo.png");
track = Image("track.png");
fill = Image("fill.png");
cx = Window.GetX() + Window.GetWidth() / 2;
cy = Window.GetY() + Window.GetHeight() / 2;
logo_s = Sprite(logo);
logo_s.SetPosition(cx - logo.GetWidth() / 2, cy - logo.GetHeight() / 2 - 40, 1);
bx = cx - track.GetWidth() / 2;
by = cy + logo.GetHeight() / 2 + 20;
track_s = Sprite(track);
track_s.SetPosition(bx, by, 1);
fill_s = Sprite();
fill_s.SetPosition(bx, by, 2);
fun progress_cb(duration, progress) {
  w = Math.Int(fill.GetWidth() * progress);
  if (w < 3) w = 3;
  fill_s.SetImage(fill.Scale(w, fill.GetHeight()));
}
Plymouth.SetBootProgressFunction(progress_cb);
EOF
  update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$PT/macos.plymouth" 200
  update-alternatives --set default.plymouth "$PT/macos.plymouth"
  update-initramfs -u
else
  echo "   Apple logo not found - run 3-apariencia-macos.sh first"
fi

log "No GRUB menu at start-up (hold Shift or press Esc while starting to see it)"
printf 'GRUB_TIMEOUT_STYLE=hidden\nGRUB_TIMEOUT=0\n' > /etc/default/grub.d/99-macos-boot.cfg   # read after Mint's own 50_*.cfg
update-grub

log "Login screen like macOS"
# The greeter runs as another user, so the theme, icons and cursor must be installed system-wide
cp -a "$UH/.themes/WhiteSur-Light" /usr/share/themes/ 2>/dev/null || echo "   (WhiteSur theme not found)"
for d in "$UH"/.local/share/icons/WhiteSur* "$UH"/.icons/WhiteSur*; do [ -d "$d" ] && cp -a "$d" /usr/share/icons/; done
S=/usr/share/backgrounds/macos; mkdir -p "$S"
WP="$S/Sonoma-light.jpg"; [ -f "$WP" ] || WP="$UH/.local/share/backgrounds/macos/Sonoma-light.jpg"
convert "$WP" -resize 1920x1080^ -gravity center -extent 1920x1080 -blur 0x40 "$S/login-blur.jpg" \
  || echo "   (could not blur the wallpaper)"
C=/etc/lightdm/slick-greeter.conf
[ -f "$C" ] || printf '[Greeter]\n' > "$C"
setg() { sed -i "/^$1=/d" "$C"; sed -i "/^\[Greeter\]/a $1=$2" "$C"; }
[ -f "$S/login-blur.jpg" ] && setg background "$S/login-blur.jpg"
setg draw-user-backgrounds false
setg draw-grid false
setg show-hostname false
setg show-a11y false
setg theme-name WhiteSur-Light
setg icon-theme-name WhiteSur-light
setg cursor-theme-name WhiteSur-cursors
setg cursor-theme-size 32
setg font-name "Inter 12"
setg clock-format "%a %-d %b  %-l:%M %p"

# Mint's slick-greeter (above, kept as a fallback) can't be centred and its password dots come out grey on grey.
# lightdm-gtk-greeter can be placed anywhere and styled with CSS: round picture, name and a translucent
# pill-shaped password field with white dots, in the middle of the blurred wallpaper, like macOS.
apt-get install -y lightdm-gtk-greeter
LT=/usr/share/themes/macOS-Login/gtk-3.0; mkdir -p "$LT"
cat > "$LT/gtk.css" <<'EOF'
/* Plain GTK base, not WhiteSur: its entry rules beat these and left the password dots dark grey */
@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained.css");
* { font-family: "Inter"; }
#panel_window, #panel_window menubar, #panel_window menubar > menuitem {
  background: transparent; border: none; box-shadow: none; color: #ffffff; }
#panel_window menubar > menuitem label { color: #ffffff; font-weight: 500; }
#clock_menuitem label { color: rgba(255, 255, 255, 0.95); font-size: 26px; font-weight: 600; }   /* macOS's big clock (the greeter takes no markup: one size) */
#login_window, #login_window > *, #content_frame, #buttonbox_frame, #greeter_infobar {
  background: transparent; border: none; box-shadow: none; }
/* her name, under the picture: plain white text, not a drop-down button */
#user_combobox, #user_combobox *, combobox#user_combobox box.linked > button.combo, combobox#user_combobox button.combo:hover {
  background: none; background-color: transparent; background-image: none; border: none; box-shadow: none; outline: none; }
#user_combobox label, #user_combobox cellview, #user_combobox button.combo cellview {
  color: #ffffff; font-size: 17px; font-weight: 600; text-shadow: 0 1px 2px rgba(0, 0, 0, 0.35); }
#user_combobox arrow, #user_combobox button.combo arrow { -gtk-icon-source: none; min-width: 0; min-height: 0; opacity: 0; }
#login_window entry, entry#password_entry, #password_entry { background-color: rgba(255, 255, 255, 0.28); background-image: none; color: #ffffff; caret-color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.35); border-radius: 16px; min-height: 30px; padding: 0 14px;
  box-shadow: none; font-size: 15px; }
#login_window entry:focus, entry#password_entry:focus, #password_entry:focus { border-color: rgba(255, 255, 255, 0.6); box-shadow: none; }
#login_window entry selection, #password_entry selection { background-color: rgba(255, 255, 255, 0.4); }
#login_button, #cancel_button { opacity: 0; min-height: 0; padding: 0; margin: 0; }
#message_label, #greeter_infobar label { color: #ffffff; }
EOF
# macOS Sonoma layout: large date and time at the top centre, a small round picture, the name and a password pill
# at the bottom centre. The greeter always puts its picture left of the fields, so the picture is drawn onto the
# background instead, its bottom ~14 px above the name (the login box starts at 76 % of the height and its name
# sits ~34 px below that; checked at 1366x768 in a lightdm --test-mode preview). Made at the screen's own size.
SCR=$(cat /sys/class/drm/card*-*/modes 2>/dev/null | head -1); SCR=${SCR:-1366x768}
W=${SCR%x*}; H=${SCR#*x}; LBG="$S/login-blur.jpg"
if [ -f "/var/lib/AccountsService/icons/$U" ] && [ -f "$S/login-blur.jpg" ]; then
  convert "$S/login-blur.jpg" -resize "${SCR}^" -gravity center -extent "$SCR" \
    \( "/var/lib/AccountsService/icons/$U" -resize 96x96 \) -gravity northwest \
    -geometry "+$(( W / 2 - 48 ))+$(( H * 76 / 100 - 76 ))" -composite "$S/login-mac.jpg" && LBG="$S/login-mac.jpg"
fi
cat > /etc/lightdm/lightdm-gtk-greeter.conf <<EOF
[greeter]
background=$LBG
user-background=false
theme-name=macOS-Login
icon-theme-name=WhiteSur-light
cursor-theme-name=WhiteSur-cursors
cursor-theme-size=32
font-name=Inter 12
hide-user-image=true
position=50%,center 76%,start
panel-position=top
indicators=~spacer;~clock;~spacer;~layout;~power
clock-format=%A %-d %B   %-l:%M
xft-antialias=true
xft-hintstyle=hintslight
xft-rgba=rgb
EOF
# Read after Mint's /usr/share/lightdm/lightdm.conf.d/90-slick-greeter.conf; delete this file to go back
mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\ngreeter-session=lightdm-gtk-greeter\n' > /etc/lightdm/lightdm.conf.d/95-macos-greeter.conf

AV=mac-assets/avatar.png
if [ -f "$AV" ]; then
  log "Round account picture (login screen and app menu)"
  convert "$AV" -resize 256x256^ -gravity center -extent 256x256 \
    \( +clone -alpha transparent -fill white -draw "circle 128,128 128,1" \) -compose copy_opacity -composite \
    "png:/var/lib/AccountsService/icons/$U"
  F="/var/lib/AccountsService/users/$U"
  [ -f "$F" ] || printf '[User]\n' > "$F"
  sed -i '/^Icon=/d' "$F"; sed -i "/^\[User\]/a Icon=/var/lib/AccountsService/icons/$U" "$F"
  install -o "$U" -g "$U" -m 644 "/var/lib/AccountsService/icons/$U" "$UH/.face"
else
  echo "   (no $AV - account picture unchanged)"
fi

log "Trackpad like a Mac: natural scrolling, tap to click, two-finger click = right click"
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/90-mac-touchpad.conf <<'EOF'
Section "InputClass"
    Identifier "Mac-like touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "NaturalScrolling" "true"
    Option "Tapping" "on"
    Option "ClickMethod" "clickfinger"
    Option "DisableWhileTyping" "on"
EndSection
EOF

log "Done. Log out and back in (trackpad, login screen), restart to see the boot screen."
