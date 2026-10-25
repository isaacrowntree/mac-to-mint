"""Convert Mac-only data from a Mac home-folder backup into Linux-friendly formats.

Usage: python3 -I convert.py <backup_home> <out_dir>
  contacts -> .vcf, Safari bookmarks -> .html, Calendar -> .ics, Notes -> .txt, Mail -> .mbox, Photos originals.
Reads only; writes into out_dir. Each section is independent and reports counts.
Tested against macOS 10.12 Sierra databases; newer macOS versions may need the SQL adjusted.
SKIP_CALENDARS (env, comma-separated titles): subscribed calendars to leave out, e.g. public holidays.
"""
import email.utils
import glob
import gzip
import html
import os
import plistlib
import re
import shutil
import sqlite3
import sys
import tempfile
import zlib

HOME, OUT = sys.argv[1], sys.argv[2]
LIB = os.path.join(HOME, "Library")
SKIP_CALENDARS = {t.strip() for t in os.environ.get("SKIP_CALENDARS", "").split(",") if t.strip()}
os.makedirs(OUT, exist_ok=True)


def open_copy(db):
    """Copy a SQLite db with its -wal/-shm to a temp dir and open it, so WAL data is included."""
    tmp = tempfile.mkdtemp()
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(db + suffix):
            shutil.copy2(db + suffix, os.path.join(tmp, os.path.basename(db) + suffix))
    return sqlite3.connect(os.path.join(tmp, os.path.basename(db)))


def section(name, fn):
    try:
        print(f"[{name}] {fn()}")
    except Exception as e:  # keep going; report the failure
        print(f"[{name}] FAILED: {e!r}")


def contacts():
    db = os.path.join(LIB, "Application Support/AddressBook/AddressBook-v22.abcddb")
    dbs = [db] + glob.glob(os.path.join(LIB, "Application Support/AddressBook/Sources/*/AddressBook-v22.abcddb"))
    cards = []
    for path in dbs:
        if not os.path.exists(path):
            continue
        c = open_copy(path)
        people = c.execute(
            "select Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION, ZNOTE from ZABCDRECORD "
            "where ZFIRSTNAME is not null or ZLASTNAME is not null or ZORGANIZATION is not null").fetchall()
        for pk, first, last, org, _ in people:
            phones = [r[0] for r in c.execute("select ZFULLNUMBER from ZABCDPHONENUMBER where ZOWNER=?", (pk,)) if r[0]]
            mails = [r[0] for r in c.execute("select ZADDRESS from ZABCDEMAILADDRESS where ZOWNER=?", (pk,)) if r[0]]
            first, last, org = first or "", last or "", org or ""
            fn = (f"{first} {last}".strip()) or org
            lines = ["BEGIN:VCARD", "VERSION:3.0", f"N:{last};{first};;;", f"FN:{fn}"]
            if org:
                lines.append(f"ORG:{org}")
            lines += [f"TEL;TYPE=CELL:{p}" for p in phones] + [f"EMAIL;TYPE=INTERNET:{m}" for m in mails]
            lines.append("END:VCARD")
            cards.append("\r\n".join(lines))
    with open(os.path.join(OUT, "contacts.vcf"), "w", encoding="utf-8") as f:
        f.write("\r\n".join(cards) + "\r\n")
    return f"{len(cards)} contacts -> contacts.vcf"


def safari_bookmarks():
    with open(os.path.join(LIB, "Safari/Bookmarks.plist"), "rb") as f:
        root = plistlib.load(f)
    count = 0

    def walk(node, depth):
        nonlocal count
        pad = "    " * depth
        out = []
        if node.get("WebBookmarkType") == "WebBookmarkTypeLeaf":
            url = node.get("URLString", "")
            title = node.get("URIDictionary", {}).get("title") or url
            count += 1
            out.append(f'{pad}<DT><A HREF="{html.escape(url)}">{html.escape(title)}</A>')
        elif node.get("WebBookmarkType") == "WebBookmarkTypeList":
            title = node.get("Title", "")
            if title and title != "com.apple.ReadingList" or depth == 0:
                kids = [l for k in node.get("Children", []) for l in walk(k, depth + 1)]
                if depth == 0:
                    return kids
                out += [f"{pad}<DT><H3>{html.escape(title)}</H3>", f"{pad}<DL><p>"] + kids + [f"{pad}</DL><p>"]
        return out

    body = walk(root, 0)
    doc = ["<!DOCTYPE NETSCAPE-Bookmark-file-1>",
           '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
           "<TITLE>Bookmarks</TITLE><H1>Marcadores de Safari</H1>", "<DL><p>"] + body + ["</DL><p>"]
    with open(os.path.join(OUT, "safari-bookmarks.html"), "w", encoding="utf-8") as f:
        f.write("\n".join(doc))
    return f"{count} bookmarks -> safari-bookmarks.html"


def calendars():
    keep = []
    for cal in glob.glob(os.path.join(LIB, "Calendars/*.calendar")):
        try:
            with open(os.path.join(cal, "Info.plist"), "rb") as f:
                title = plistlib.load(f).get("Title", "")
        except Exception:
            title = ""
        if title in SKIP_CALENDARS:  # public subscriptions: re-add on the new machine instead
            continue
        for ics in glob.glob(os.path.join(cal, "**/*.ics"), recursive=True):
            txt = open(ics, encoding="utf-8", errors="replace").read()
            keep += re.findall(r"BEGIN:(?:VEVENT|VTODO).*?END:(?:VEVENT|VTODO)", txt, re.S)
    data = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//macbook-air-backup//ES\r\n" + "\r\n".join(keep) + "\r\nEND:VCALENDAR\r\n"
    open(os.path.join(OUT, "calendar.ics"), "w", encoding="utf-8").write(data)
    return f"{len(keep)} events/reminders -> calendar.ics"


def notes():
    c = open_copy(os.path.join(LIB, "Group Containers/group.com.apple.notes/NoteStore.sqlite"))
    rows = c.execute(
        "select o.ZTITLE1, d.ZDATA from ZICCLOUDSYNCINGOBJECT o join ZICNOTEDATA d on d.ZNOTE=o.Z_PK "
        "where o.ZTITLE1 is not null").fetchall()
    d = os.path.join(OUT, "notes")
    os.makedirs(d, exist_ok=True)
    for i, (title, blob) in enumerate(rows, 1):
        raw = gzip.decompress(blob) if blob[:2] == b"\x1f\x8b" else zlib.decompress(blob)
        # Note body is protobuf; the text is the longest UTF-8 run. Good enough for plain notes.
        runs = re.findall(rb"[\x09\x0a\x0d\x20-\x7e\xc2-\xf4][\x09\x0a\x0d\x20-\x7e\x80-\xbf\xc2-\xf4]{8,}", raw)
        text = max(runs, key=len).decode("utf-8", "replace") if runs else ""
        safe = re.sub(r'[/\\:*?"<>|]', "_", title)[:60] or f"nota-{i}"
        open(os.path.join(d, f"{safe}.txt"), "w", encoding="utf-8").write(text)
    return f"{len(rows)} notes -> notes/"


def mail():
    d = os.path.join(OUT, "mail-archive")
    os.makedirs(d, exist_ok=True)
    total = 0
    for mbox in glob.glob(os.path.join(LIB, "Mail/V4/*/*.mbox")):
        # os.walk, not glob: folder names like "[Gmail].mbox" are glob patterns
        files = sorted(os.path.join(r, f) for r, _, fs in os.walk(mbox) for f in fs if f.endswith(".emlx"))
        if not files:
            continue
        name = os.path.basename(mbox)[:-5].replace("/", "_")
        with open(os.path.join(d, name + ".mbox"), "wb") as out:
            for p in files:
                with open(p, "rb") as f:
                    first = f.readline()
                    try:
                        n = int(first.strip())
                        msg = f.read(n)
                    except ValueError:
                        msg = first + f.read()
                m = re.search(rb"^Date: (.+)$", msg, re.M)
                try:
                    when = email.utils.parsedate_to_datetime(m.group(1).decode(errors="replace")).strftime("%a %b %d %H:%M:%S %Y")
                except Exception:
                    when = "Thu Jan  1 00:00:00 1970"
                msg = re.sub(rb"(?m)^(>*From )", rb">\1", msg.replace(b"\r\n", b"\n"))
                out.write(b"From MAILER-DAEMON " + when.encode() + b"\n" + msg.rstrip(b"\n") + b"\n\n")
                total += 1
    return f"{total} messages -> mail-archive/*.mbox"


def photos():
    src = glob.glob(os.path.join(HOME, "Pictures/*.photoslibrary/Masters"))
    if not src:
        return "no Masters folder"
    d = os.path.join(OUT, "photos-library-originals")
    n = 0
    for root, _, files in os.walk(src[0]):
        for fn in files:
            if fn.startswith("."):
                continue
            rel = os.path.relpath(root, src[0])  # Masters/YYYY/MM/DD/... keeps dates
            dst = os.path.join(d, rel)
            os.makedirs(dst, exist_ok=True)
            shutil.copy2(os.path.join(root, fn), os.path.join(dst, fn))
            n += 1
    return f"{n} photos -> photos-library-originals/"


for name, fn in [("contacts", contacts), ("safari", safari_bookmarks), ("calendar", calendars),
                 ("notes", notes), ("mail", mail), ("photos", photos)]:
    section(name, fn)
