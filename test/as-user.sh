#!/usr/bin/env bash
# Inside the test machine, as root: run a command as the test user inside their running Xfce session
# (same DISPLAY and D-Bus as the desktop, so xfconf, the panel and the dock see it):
#   bash test/as-user.sh 'bash 3-linux/3-macos-look.sh'
set -euo pipefail
U="${TEST_USER:-alex}"
P=$(pgrep -u "$U" -x xfce4-session | head -1)
[ -n "$P" ] || { echo "no Xfce session for $U - run test/desktop.sh first"; exit 1; }
ENVV=$(tr '\0' '\n' < "/proc/$P/environ" | grep -E '^(DISPLAY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|XDG_DATA_DIRS|XDG_CONFIG_DIRS|PATH|LANG|HOME|GTK_MODULES)=')
cd "/home/$U"
exec runuser -u "$U" -- env -i $ENVV USER="$U" LOGNAME="$U" bash -c "$*"
