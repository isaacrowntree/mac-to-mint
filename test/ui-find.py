#!/usr/bin/env python3
"""Print the on-screen boxes of the named things in a window, from the accessibility tree, as JSON:
    ui-find.py "Mission Control"   ->   [{"role": "push button", "name": "Desktop 1", "box": [x, y, w, h]}, ...]
Run in the user's session (test/mintosh-test.py does this), so the tests can click buttons wherever they are."""
import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

out = []


def walk(node, depth=0):
    if node is None or depth > 40:
        return
    try:
        name, role = node.get_name(), node.get_role_name()
        if name and role in ("push button", "image", "icon", "label", "toggle button"):
            r = node.get_extents(Atspi.CoordType.SCREEN)
            if r.width > 0 and r.height > 0:
                out.append({"role": role, "name": name, "box": [r.x, r.y, r.width, r.height]})
        for i in range(node.get_child_count()):
            walk(node.get_child_at_index(i), depth + 1)
    except Exception:
        pass


desk = Atspi.get_desktop(0)
for a in range(desk.get_child_count()):
    app = desk.get_child_at_index(a)
    for f in range(app.get_child_count() if app else 0):
        frame = app.get_child_at_index(f)
        if frame and frame.get_name() == sys.argv[1]:
            walk(frame)
print(json.dumps(out))
