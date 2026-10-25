#!/usr/bin/env python3
"""Check mintosh's own parts in the test machine: the shortcuts point at its helpers and work, Launchpad and Mission
Control behave, and each trackpad gesture runs the right thing. Run inside the test machine as root, after
test/desktop.sh and scripts 3 and 4:
    python3 -I test/mintosh-test.py [test-name ...]
Keys and clicks go in through X (xdotool), the same way the window manager sees them. Toshy (⌘ shortcuts) and
Touchegg (gesture recognition) are well-tested upstream projects and aren't tested here: the shortcut tests press
the keys Toshy sends on Mint (⌘Space -> Super+Space, ⌘⇧3 -> Ctrl+Shift+3, Ctrl+→ -> Super+→), and the gesture test
runs the commands mintosh gives Touchegg. Each check prints PASS or FAIL.
"""
import os
import re
import subprocess
import sys
import time

USER = os.environ.get("TEST_USER", "alex")
HERE = os.path.dirname(os.path.abspath(__file__))
SW, SH = 1366, 768


def sh(cmd):
    # as the user, inside their session (D-Bus too: xfconf and the accessibility tree need it)
    r = subprocess.run(["bash", f"{HERE}/as-user.sh", cmd], capture_output=True, text=True)
    return r.stdout.strip()


def keys(*combo):
    """xdotool key names, e.g. keys("super+space"), keys("Escape")."""
    sh("xdotool key --clearmodifiers " + " ".join(combo)); time.sleep(0.6)


def type_text(s):
    sh(f"xdotool type --delay 40 '{s}'")


def click(x, y):
    sh(f"xdotool mousemove {int(x)} {int(y)} sleep 0.15 click 1"); time.sleep(0.8)


def drag(x0, y0, x1, y1, steps=30):
    moves = " ".join(f"mousemove {int(x0 + (x1 - x0) * s / steps)} {int(y0 + (y1 - y0) * s / steps)} sleep 0.02"
                     for s in range(1, steps + 1))
    sh(f"xdotool mousemove {int(x0)} {int(y0)} sleep 0.15 mousedown 1 {moves} sleep 0.3 mouseup 1"); time.sleep(1)


def ui(window):
    """Named buttons, labels and images in a window, from the accessibility tree: {name: (cx, cy)}."""
    import json
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        items = json.loads(sh(f"python3 -I {here}/ui-find.py '{window}'") or "[]")
    except ValueError:
        return {}
    return {i["name"]: (i["box"][0] + i["box"][2] // 2, i["box"][1] + i["box"][3] // 2) for i in items}


def on_desktop(title):
    """Which desktop a window is on (wmctrl -l column 2), or None."""
    for line in sh("wmctrl -l").splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4 and title in parts[3]:
            return parts[1]
    return None


def running(name):
    """A real process of that name (not a shell whose command line merely mentions it)."""
    r = subprocess.run(["pgrep", "-af", name], capture_output=True, text=True)
    return any(not l.split(None, 1)[1].startswith(("bash ", "runuser ", "env ", "timeout "))
               for l in r.stdout.splitlines() if " " in l)


def active():
    return sh("xdotool getactivewindow getwindowname 2>/dev/null")


def desktop():
    return sh("wmctrl -d | awk '$2==\"*\"{print $1}'")


results = []


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {name}{('  - ' + detail) if detail else ''}", flush=True)


def t_spotlight():
    keys("super+space"); time.sleep(1.2)
    ok = running("rofi.*combi")
    keys("Escape")
    check("⌘Space (Super+Space) opens Spotlight", ok)


def t_screenshot():
    desk = sh("xdg-user-dir DESKTOP")
    before = set(os.listdir(desk))
    keys("ctrl+shift+3"); time.sleep(2.5)
    new = set(os.listdir(desk)) - before
    check("⌘⇧3 (Ctrl+Shift+3) saves a screenshot to the Desktop, no dialog",
          any(re.match(r"Screenshot .* at .*\.png$", f) for f in new), ", ".join(new))
    for f in new:
        os.remove(os.path.join(desk, f))


def t_f3_f4():
    keys("XF86LaunchA"); time.sleep(2.5)   # the Mac F3 key (Mission Control)
    ok = running("bin/mission-control")
    keys("Escape"); time.sleep(0.8)
    check("F3 opens Mission Control", ok)
    keys("XF86LaunchB"); time.sleep(1.5)   # the Mac F4 key (Launchpad)
    ok = running("rofi.*drun")
    keys("Escape")
    check("F4 opens Launchpad", ok)


def t_spaces_keys():
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 2"); time.sleep(1)
    sh("wmctrl -s 0"); time.sleep(0.5)
    keys("super+Right"); time.sleep(0.8)
    d1 = desktop()
    keys("super+Left"); time.sleep(0.8)
    d2 = desktop()
    check("Ctrl+→ / Ctrl+← (Super+→/←) switch desktops", (d1, d2) == ("1", "0"), f"after →: {d1}, after ←: {d2}")
    keys("super+Up"); time.sleep(2.5)
    check("Ctrl+↑ (Super+↑) opens Mission Control", running("bin/mission-control"))
    keys("Escape"); time.sleep(0.8)


def t_gestures():
    conf = sh("cat ~/.config/touchegg/touchegg.conf")
    cmd = {}
    for m in re.finditer(r'<gesture type="(\w+)" fingers="(\d)" direction="(\w+)">.*?<command>(.*?)</command>', conf, re.S):
        cmd[(m[1], m[2], m[3])] = m[4]
    def do(*g):
        sh(f"setsid {cmd.get(g, 'false')} >/dev/null 2>&1 &"); time.sleep(2)
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 2"); sh("wmctrl -s 0"); time.sleep(0.8)
    do("SWIPE", "3", "UP")
    check("three fingers up opens Mission Control", running("bin/mission-control"))
    do("SWIPE", "3", "DOWN")
    check("three fingers down closes it", not running("bin/mission-control"))
    do("SWIPE", "3", "LEFT")
    d = desktop()
    check("three fingers left goes to the next desktop", d == "1", f"desktop {d}")
    do("SWIPE", "3", "RIGHT")
    d = desktop()
    check("three fingers right comes back", d == "0", f"desktop {d}")
    do("PINCH", "4", "IN")
    check("thumb + three fingers pinch opens Launchpad", running("rofi.*drun"))
    do("PINCH", "4", "OUT")
    check("spreading the fingers closes Launchpad", not running("rofi.*drun"))
    do("PINCH", "4", "OUT")
    check("spreading again shows the desktop", "ON" in sh("wmctrl -m"))
    do("PINCH", "4", "IN")
    check("pinching brings the windows back", "ON" not in sh("wmctrl -m"))
    sh("wmctrl -k off")


def t_launchpad():
    def lp_open():  # from closed, so one failed step doesn't spill into the next
        sh("pkill -x rofi"); time.sleep(0.5)
        keys("XF86LaunchB"); time.sleep(1.5)
        return running("rofi.*drun")

    sh("pkill -f gnome-calculator; pkill -x xed"); sw, shh = SW, SH
    lp_open(); time.sleep(1)
    geo = sh("xdotool search --name '^Launchpad$' getwindowgeometry 2>/dev/null | awk '/Geometry/{print $2}' | tail -1")
    check("Launchpad covers the whole screen", geo == f"{sw}x{shh}", geo)
    bg = sh(f"identify -format '%wx%h' ~/.cache/launchpad-bg-{sw}x{shh}.jpg 2>/dev/null")
    check("Launchpad background is the blurred wallpaper at screen size", bg == f"{sw}x{shh}", bg)
    sh("import -window root /tmp/launchpad.png")  # for a look afterwards

    # Typing filters; one click on the app opens it (not a double click)
    type_text("calculator"); time.sleep(0.8)
    sh("import -window root /tmp/launchpad-search.png")
    # first cell of the grid: the box is 86% x 88% of the screen, centred; inside, 22px / 2% padding, then the
    # search field (~33px) and 34px of space; 7 columns 20px apart
    bw, bh = sw * 0.86, shh * 0.88
    bx, by = (sw - bw) / 2, (shh - bh) / 2
    cw = (bw * 0.96 - 6 * 20) / 7
    click(bx + bw * 0.02 + cw / 2, by + 22 + 33 + 34 + 50); time.sleep(3)
    check("one click on an app opens it", running("gnome-calculator") and not running("rofi.*drun"))
    sh("pkill -f gnome-calculator")

    lp_open(); type_text("text editor"); keys("Return"); time.sleep(3)
    check("type a name + Return opens it", running("xed") and not running("rofi.*drun"))
    sh("pkill -x xed")

    lp_open(); type_text("settings manager"); keys("Return"); time.sleep(2)
    check("settings panels are not in Launchpad", not running("xfce4-settings-manager"))
    sh("import -window root /tmp/launchpad-nomatch.png")   # should show no "Failed to execute" error
    lp_open(); keys("Escape"); time.sleep(0.8)
    check("Esc closes it", not running("rofi.*drun"), sh("pgrep -a rofi | cut -c1-80"))

    lp_open(); keys("XF86LaunchB"); time.sleep(1.2)
    check("F4 again closes it", not running("rofi.*drun"), sh("pgrep -a rofi | cut -c1-80"))
    lp_open(); click(sw - 30, shh - 20); time.sleep(0.8)
    check("a click on empty space closes it", not running("rofi.*drun"), sh("pgrep -a rofi | cut -c1-80"))
    sh("pkill -x rofi")


def t_mission_control():
    sh("pkill -f bin/mission-control; pkill -x xed; pkill -x xfce4-terminal")
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 1"); time.sleep(0.5)
    sh("setsid xed >/dev/null 2>&1 &"); time.sleep(3)
    sh("setsid xfce4-terminal >/dev/null 2>&1 &"); time.sleep(3)
    def title(cls):  # the visible window's title (xdotool also finds hidden helper windows)
        for line in sh("wmctrl -lx").splitlines():
            parts = line.split(None, 4)
            if len(parts) == 5 and parts[2].split(".")[0] == cls:
                return parts[4]
        return ""
    ed, term = title("xed"), title("xfce4-terminal")

    def mc_open():
        if not running("bin/mission-control"):
            keys("XF86LaunchA"); time.sleep(2.5)
        return ui("Mission Control")

    u = mc_open()
    sh("import -window root /tmp/mission-control.png")
    check("Mission Control shows a preview of each window", bool(ed) and ed in u and term in u, ", ".join(u))
    check("previews are labelled with the app's name", "Text Editor" in u and any(n.endswith("Terminal") for n in u))
    check("the Spaces bar shows the desktops", "Desktop 1" in u, ", ".join(n for n in u if "Desktop" in n))

    if "+" in u:
        click(*u["+"]); time.sleep(1); u = ui("Mission Control")
    n = sh("xfconf-query -c xfwm4 -p /general/workspace_count")
    check("+ adds a desktop", n == "2" and "Desktop 2" in u, f"count {n}")

    if ed in u and "Desktop 2" in u:
        drag(*u[ed], *u["Desktop 2"]); time.sleep(1)
    check("dragging a window onto a desktop moves it there", on_desktop(ed) == "1", f"on desktop {on_desktop(ed)}")

    u = ui("Mission Control")
    if "Desktop 2" in u:
        click(*u["Desktop 2"]); time.sleep(1)
    check("clicking a desktop goes there and closes", desktop() == "1" and not running("bin/mission-control"),
          f"desktop {desktop()}")

    u = mc_open()
    if "✕" in u:
        click(*u["✕"]); time.sleep(1.2)
    n = sh("xfconf-query -c xfwm4 -p /general/workspace_count")
    check("✕ removes the last desktop; its windows come back", n == "1" and on_desktop(ed) == "0",
          f"count {n}, editor on {on_desktop(ed)}")

    sh("xdotool search --class xed windowactivate"); time.sleep(0.8)
    u = mc_open()
    if term in u:
        click(*u[term]); time.sleep(1)
    check("clicking a preview brings that window to the front", active() == term and not running("bin/mission-control"),
          active())

    mc_open(); click(SW // 2, SH - 15)
    check("a click on empty space closes it", not running("bin/mission-control"))
    mc_open(); keys("Escape")
    check("Esc closes it", not running("bin/mission-control"))
    mc_open(); keys("XF86LaunchA"); time.sleep(1)
    check("F3 again closes it", not running("bin/mission-control"))
    sh("pkill -x xed; pkill -x xfce4-terminal")


TESTS = {"spotlight": t_spotlight, "screenshot": t_screenshot, "fkeys": t_f3_f4, "spaces": t_spaces_keys,
         "gestures": t_gestures, "launchpad": t_launchpad, "missioncontrol": t_mission_control}

if __name__ == "__main__":
    for name in (sys.argv[1:] or TESTS):
        try:
            TESTS[name]()
        except Exception as ex:  # keep going
            check(name, False, repr(ex))
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 1")
    print(f"\n{sum(ok for _, ok in results)}/{len(results)} passed")
