#!/usr/bin/env bash
# Inside the test machine, as root: start a 1366x768 (MacBook Air 11") Xfce desktop for user alex on display :0,
# on a dummy video card with libinput, so virtual keyboards/trackpads (test/input-test.py) work like real ones.
# Watch it over VNC: open vnc://mintosh-test.orb.local:5900 in Finder (no password; reachable only from this Mac).
set -euo pipefail
U="${TEST_USER:-alex}"
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/mintosh-test.conf <<'X'
Section "Device"
    Identifier "dummy"
    Driver "dummy"
    VideoRam 256000
EndSection
Section "Monitor"
    Identifier "monitor"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Modeline "1366x768" 85.25 1366 1440 1576 1784 768 771 781 798 -hsync +vsync
EndSection
Section "Screen"
    Identifier "screen"
    Device "dummy"
    Monitor "monitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1366x768"
    EndSubSection
EndSection
Section "ServerFlags"
    Option "AutoAddDevices" "true"
EndSection
X
pkill -x Xorg 2>/dev/null || true; sleep 1
setsid Xorg :0 -config /etc/X11/mintosh-test.conf -nolisten tcp vt7 >/var/log/mintosh-xorg.log 2>&1 < /dev/null &
for _ in $(seq 30); do [ -S /tmp/.X11-unix/X0 ] && break; sleep 0.5; done
xhost +SI:localuser:"$U" >/dev/null 2>&1 || DISPLAY=:0 xhost +SI:localuser:"$U" >/dev/null
UID_=$(id -u "$U"); mkdir -p /run/user/$UID_ && chown "$U": /run/user/$UID_
runuser -u "$U" -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$UID_ XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE \
  setsid dbus-run-session startxfce4 >/tmp/mintosh-session.log 2>&1 < /dev/null &
pkill -x x11vnc 2>/dev/null || true
setsid x11vnc -display :0 -forever -shared -nopw -quiet -auth guess >/var/log/mintosh-vnc.log 2>&1 < /dev/null &
sleep 8
echo "Desktop up on :0 for $U; VNC on port 5900"
