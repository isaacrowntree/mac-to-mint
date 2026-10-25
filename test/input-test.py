#!/usr/bin/env python3
"""Press the Mac shortcuts and do the trackpad gestures with a virtual Apple keyboard and trackpad, then check what
happened. Run inside the test machine as root, after test/desktop.sh and the mintosh scripts (3, 4, 5):
    python3 -I test/input-test.py [test-name ...]
The devices are made with /dev/uinput, so they go through the same path as real ones: kernel -> libinput -> Toshy /
Touchegg / Xorg. Each test prints PASS or FAIL.
"""
import os
import subprocess
import sys
import time

from evdev import AbsInfo, UInput, ecodes as e

USER = os.environ.get("TEST_USER", "alex")
ENV = dict(os.environ, DISPLAY=":0")


HERE = os.path.dirname(os.path.abspath(__file__))


def sh(cmd, user=True, check=False):
    # as the user, inside their session (D-Bus too: xfconf and the accessibility tree need it)
    full = ["bash", f"{HERE}/as-user.sh", cmd] if user else ["bash", "-c", cmd]
    r = subprocess.run(full, capture_output=True, text=True, env=ENV)
    return r.stdout.strip()


def uid():
    return int(subprocess.run(["id", "-u", USER], capture_output=True, text=True).stdout)


# ---------- virtual Apple keyboard ----------
kbd = UInput({e.EV_KEY: list(range(1, 249))}, name="Apple Inc. Apple Internal Keyboard / Trackpad",
             vendor=0x05AC, product=0x0262, version=0x111, bustype=e.BUS_USB)


def keys(*names, hold=0.08):
    codes = [getattr(e, n) for n in names]
    for c in codes:
        kbd.write(e.EV_KEY, c, 1); kbd.syn(); time.sleep(0.02)
    time.sleep(hold)
    for c in reversed(codes):
        kbd.write(e.EV_KEY, c, 0); kbd.syn(); time.sleep(0.02)
    time.sleep(0.6)


# ---------- virtual trackpad (bcm5974-like: 5 slots, ~100x70 mm) ----------
W, H, RES = 4000, 2800, 40
tp = UInput({
    e.EV_KEY: [e.BTN_LEFT, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP, e.BTN_TOOL_TRIPLETAP, e.BTN_TOOL_QUADTAP,
               e.BTN_TOOL_QUINTTAP, e.BTN_TOUCH],
    e.EV_ABS: [(e.ABS_X, AbsInfo(0, 0, W, 0, 0, RES)), (e.ABS_Y, AbsInfo(0, 0, H, 0, 0, RES)),
               (e.ABS_MT_SLOT, AbsInfo(0, 0, 4, 0, 0, 0)),
               (e.ABS_MT_POSITION_X, AbsInfo(0, 0, W, 0, 0, RES)), (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, H, 0, 0, RES)),
               (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0))],
}, name="bcm5974", vendor=0x05AC, product=0x0262, version=0x111, bustype=e.BUS_USB,
    input_props=[e.INPUT_PROP_POINTER, e.INPUT_PROP_BUTTONPAD])
TOOL = {2: e.BTN_TOOL_DOUBLETAP, 3: e.BTN_TOOL_TRIPLETAP, 4: e.BTN_TOOL_QUADTAP}
tid = [100]


def frame(points, first=False, last=False):
    for slot, (x, y) in enumerate(points):
        tp.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
        if first:
            tid[0] += 1
            tp.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tid[0])
        if last:
            tp.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
        else:
            tp.write(e.EV_ABS, e.ABS_MT_POSITION_X, int(x)); tp.write(e.EV_ABS, e.ABS_MT_POSITION_Y, int(y))
    if not last:
        tp.write(e.EV_ABS, e.ABS_X, int(points[0][0])); tp.write(e.EV_ABS, e.ABS_Y, int(points[0][1]))
    if first or last:
        tp.write(e.EV_KEY, e.BTN_TOUCH, 0 if last else 1)
        tp.write(e.EV_KEY, TOOL[len(points)], 0 if last else 1)
    tp.syn()
    time.sleep(0.012)


def swipe(n, dx, dy, steps=24):
    """n fingers, moving dx/dy (in mm) together."""
    pts = [(1400 + i * 450, 1600) for i in range(n)]
    frame(pts, first=True)
    for s in range(1, steps + 1):
        frame([(x + dx * RES * s / steps, y + dy * RES * s / steps) for x, y in pts])
    frame(pts, last=True)
    time.sleep(1.2)


def pinch(n, inward=True, steps=24):
    cx, cy, r0, r1 = 2000, 1400, 900, 300
    if not inward:
        r0, r1 = r1, r0
    import math
    ang = [2 * math.pi * i / n for i in range(n)]
    frame([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)) for a in ang], first=True)
    for s in range(1, steps + 1):
        r = r0 + (r1 - r0) * s / steps
        frame([(cx + r * math.cos(a), cy + r * math.sin(a)) for a in ang])
    frame([(cx, cy)] * n, last=True)
    time.sleep(1.2)


# ---------- virtual mouse (absolute, like a VM's USB tablet) to click on things wherever they are ----------
SW, SH = 1366, 768
ptr = UInput({e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT],
              e.EV_ABS: [(e.ABS_X, AbsInfo(0, 0, 32767, 0, 0, 0)), (e.ABS_Y, AbsInfo(0, 0, 32767, 0, 0, 0))]},
             name="mintosh test mouse", vendor=0x0627, product=0x0001, bustype=e.BUS_USB)


def point(x, y):
    ptr.write(e.EV_ABS, e.ABS_X, int(x * 32767 / (SW - 1))); ptr.write(e.EV_ABS, e.ABS_Y, int(y * 32767 / (SH - 1)))
    ptr.syn(); time.sleep(0.02)


def button(down):
    ptr.write(e.EV_KEY, e.BTN_LEFT, 1 if down else 0); ptr.syn(); time.sleep(0.05)


def click(x, y):
    point(x, y); time.sleep(0.15); button(True); button(False); time.sleep(0.8)


def drag(x0, y0, x1, y1, steps=30):
    point(x0, y0); time.sleep(0.15); button(True)
    for s in range(1, steps + 1):
        point(x0 + (x1 - x0) * s / steps, y0 + (y1 - y0) * s / steps); time.sleep(0.02)
    time.sleep(0.3); button(False); time.sleep(1)


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


# ---------- helpers ----------
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
    keys("KEY_LEFTMETA", "KEY_SPACE"); time.sleep(1.2)
    ok = running("rofi.*combi")
    keys("KEY_ESC")
    check("⌘Space opens Spotlight", ok)


def t_screenshot():
    desk = sh("xdg-user-dir DESKTOP")
    before = set(os.listdir(desk))
    keys("KEY_LEFTMETA", "KEY_LEFTSHIFT", "KEY_3"); time.sleep(2.5)
    new = set(os.listdir(desk)) - before
    check("⌘⇧3 saves a screenshot to the Desktop", any(f.lower().endswith(".png") for f in new), ", ".join(new))
    for f in new:
        os.remove(os.path.join(desk, f))


def t_copy_paste():
    path = f"/home/{USER}/mintosh-test.txt"
    open(path, "w").write("hello from mintosh\n")
    os.chown(path, uid(), uid())
    sh(f"setsid xed {path} >/dev/null 2>&1 &"); time.sleep(4)
    sh("xdotool search --sync --name mintosh-test windowactivate 2>/dev/null"); time.sleep(0.8)
    sh("printf '' | xclip -selection clipboard")
    keys("KEY_LEFTMETA", "KEY_A"); keys("KEY_LEFTMETA", "KEY_C"); time.sleep(0.5)
    clip = sh("xclip -o -selection clipboard 2>/dev/null")
    check("⌘A ⌘C copy text", "hello from mintosh" in clip, repr(clip[:40]))
    keys("KEY_LEFTMETA", "KEY_Q"); time.sleep(1.5)
    check("⌘Q quits the app", not running("xed .*mintosh-test"))
    os.remove(path)


def t_cmd_tab():
    sh("setsid xed >/dev/null 2>&1 &"); time.sleep(3)
    sh("setsid xfce4-terminal >/dev/null 2>&1 &"); time.sleep(3)
    a = active()
    keys("KEY_LEFTMETA", "KEY_TAB"); time.sleep(1)
    b = active()
    check("⌘Tab switches app", a != b and b != "", f"{a!r} -> {b!r}")
    sh("pkill -x xed; pkill -x xfce4-terminal")


def t_f3_f4():
    keys("KEY_SCALE"); time.sleep(2.5)   # Mac F3 (Mission Control) sends KEY_SCALE
    ok = running("mission-control")
    keys("KEY_ESC"); time.sleep(0.8)
    check("F3 opens Mission Control", ok)
    keys("KEY_DASHBOARD"); time.sleep(1.5)   # Mac F4 (Launchpad) sends KEY_DASHBOARD
    ok = running("rofi.*drun")
    keys("KEY_ESC")
    check("F4 opens Launchpad", ok)


def t_spaces_keys():
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 2"); time.sleep(1)
    sh("wmctrl -s 0"); time.sleep(0.5)
    keys("KEY_LEFTCTRL", "KEY_RIGHT"); time.sleep(0.8)
    d1 = desktop()
    keys("KEY_LEFTCTRL", "KEY_LEFT"); time.sleep(0.8)
    d2 = desktop()
    check("Ctrl+→ / Ctrl+← switch desktops", (d1, d2) == ("1", "0"), f"after →: {d1}, after ←: {d2}")


def t_gestures():
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 2"); sh("wmctrl -s 0"); time.sleep(0.8)
    swipe(3, 0, -30)
    ok = running("mission-control")
    check("three fingers up opens Mission Control", ok)
    swipe(3, 0, 30)
    check("three fingers down closes it", not running("mission-control"))
    swipe(3, -35, 0)
    d = desktop()
    check("three fingers left goes to the next desktop", d == "1", f"desktop {d}")
    swipe(3, 35, 0)
    d = desktop()
    check("three fingers right comes back", d == "0", f"desktop {d}")
    pinch(4, inward=True)
    ok = running("rofi.*drun")
    check("thumb + three fingers pinch opens Launchpad", ok)
    sh("pkill -x rofi"); time.sleep(0.5)
    pinch(4, inward=False)
    shown = "ON" in sh("wmctrl -m")
    check("thumb + three fingers spread shows the desktop", shown)
    sh("wmctrl -k off")


def t_launchpad():
    def lp_open():  # from closed, so one failed step doesn't spill into the next
        sh("pkill -x rofi"); time.sleep(0.5)
        keys("KEY_DASHBOARD"); time.sleep(1.5)
        return running("rofi.*drun")

    def type_text(s):
        for ch in s:
            keys("KEY_SPACE" if ch == " " else f"KEY_{ch.upper()}", hold=0.02)

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

    lp_open(); type_text("text editor"); keys("KEY_ENTER"); time.sleep(3)
    check("type a name + Return opens it", running("xed") and not running("rofi.*drun"))
    sh("pkill -x xed")

    lp_open(); type_text("settings manager"); keys("KEY_ENTER"); time.sleep(2)
    check("settings panels are not in Launchpad", not running("xfce4-settings-manager"))
    sh("import -window root /tmp/launchpad-nomatch.png")   # should show no "Failed to execute" error
    lp_open(); keys("KEY_ESC"); time.sleep(0.8)
    check("Esc closes it", not running("rofi.*drun"), sh("pgrep -a rofi | cut -c1-80"))

    lp_open(); keys("KEY_DASHBOARD"); time.sleep(1.2)
    check("F4 again closes it", not running("rofi.*drun"), sh("pgrep -a rofi | cut -c1-80"))
    lp_open(); click(sw - 30, shh - 20); time.sleep(0.8)
    check("a click on empty space closes it", not running("rofi.*drun"), sh("pgrep -a rofi | cut -c1-80"))
    lp_open(); pinch(4, inward=False)
    check("spreading the fingers closes it", not running("rofi.*drun"))
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
            keys("KEY_SCALE"); time.sleep(2.5)
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
    mc_open(); keys("KEY_ESC")
    check("Esc closes it", not running("bin/mission-control"))
    mc_open(); keys("KEY_SCALE"); time.sleep(1)
    check("F3 again closes it", not running("bin/mission-control"))
    sh("pkill -x xed; pkill -x xfce4-terminal")


TESTS = {"spotlight": t_spotlight, "screenshot": t_screenshot, "copy": t_copy_paste, "cmdtab": t_cmd_tab,
         "fkeys": t_f3_f4, "spaces": t_spaces_keys, "gestures": t_gestures, "launchpad": t_launchpad,
         "missioncontrol": t_mission_control}

if __name__ == "__main__":
    time.sleep(2)  # let libinput, Toshy and Touchegg pick up the new devices
    subprocess.run(["runuser", "-u", USER, "--", "bash", "-c",
                    f"XDG_RUNTIME_DIR=/run/user/{uid()} systemctl --user restart toshy-config 2>/dev/null"])
    time.sleep(4)
    for name in (sys.argv[1:] or TESTS):
        try:
            TESTS[name]()
        except Exception as ex:  # keep going
            check(name, False, repr(ex))
    sh("xfconf-query -c xfwm4 -p /general/workspace_count -s 1")
    print(f"\n{sum(ok for _, ok in results)}/{len(results)} passed")
    kbd.close(); tp.close(); ptr.close()
