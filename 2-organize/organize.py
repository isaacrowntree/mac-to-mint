"""Build a reorganised, de-duplicated copy of a Mac backup: <out_dir>/{Desktop,Documents,Pictures,Music,Videos}.

Usage: python3 -I organize.py <backup_root> <out_dir> [--dry-run]
Never modifies the backup: files are APFS-cloned (cp -c) into out_dir. Logs everything in out_dir/_registro/:
copiados.tsv (kept), duplicados-omitidos.tsv (skipped duplicate -> kept copy), basura-omitida.tsv (junk).

How it works: each source file is added as a candidate (priority, source, destination). Identical files (sha256)
keep only the lowest-priority-number copy, preferring names without " 2"/" copia"/"(1)" suffixes.
The SOURCE RULES section is per machine - run inventory.py first, then edit it. The rules below are the ones
from the first machine (a MacBook Air plus an extra "Datos" partition holding an older Mac mini's files) and are
kept as a worked example. Always do a --dry-run first.
"""
import collections
import email
import email.header
import hashlib
import os
import plistlib
import re
import subprocess
import sys
import unicodedata
import zipfile

B, OUT = sys.argv[1], sys.argv[2]
DRY = "--dry-run" in sys.argv
NFC = lambda s: unicodedata.normalize("NFC", s)  # noqa: E731
H = os.path.join(B, "home")
MM = os.path.join(B, "Datos", "datos mac mini")  # example: older Mac's files on an extra partition
CONV = os.path.join(B, "convertidos")  # convert.py output

JUNK_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini", ".localized", "Icon\r", "PkgInfo", "Recents.plist"}
JUNK_EXT = set("ipa itc tagset itl itdb lij lisj plist db graphdb graphdb-wal graphdb-shm skindex data cmap "
               "dmg pkg exe msi m4r textclipping ini lock".split())
PHOTO = set("jpg jpeg png gif heic tif tiff bmp webp".split())
VIDEO = set("mp4 mov m4v avi mkv wmv 3gp mpg mpeg".split())
AUDIO = set("mp3 m4a aac wav flac wma ogg aiff aif".split())
PHOTO_DIR = re.compile(r"foto|img|imag|paisaj|caras|picture", re.I)
BOOK_DIR = re.compile(r"^(books?|libros)", re.I)  # top-level Documents folders that hold books
DUP_SUFFIX = re.compile(r"( \d+| copia| copy|\s*\(\d+\))(\.[^.]+)?$", re.I)


def ext(name):
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def is_junk(rel):
    name = os.path.basename(rel)
    parts = rel.split(os.sep)
    if name in JUNK_NAMES or name.startswith("._") or name.startswith("~$"):
        return True
    if name.startswith(".") and ext(name) not in ("xlsx", "docx", "doc", "xls", "pdf"):
        return True  # hidden files, except real documents that merely have a dot-name (".xlsx.xlsx")
    if any(p.endswith(".files") for p in parts[:-1]):
        return True  # ArcSoft webcam thumbnail folders
    if ext(name) in JUNK_EXT:
        return True
    if any(p.endswith(".app") for p in parts):
        return True
    if any(p.startswith("Accede a tu cuenta con tu Cuenta de Google") for p in parts):
        return True  # saved Gmail login page
    return False


candidates = []  # (priority, src_path, dest_rel)
dropped = []     # (reason, src_path)


def add(prio, src, dest):
    candidates.append((prio, src, NFC(dest)))


def walk(root):
    for r, ds, fs in os.walk(root):
        ds[:] = [d for d in ds if not d.endswith(".photoslibrary")]  # libraries handled explicitly
        for f in fs:
            p = os.path.join(r, f)
            yield p, os.path.relpath(p, root)


# ======================= SOURCE RULES (per machine) =======================
# --- Desktop (prio 0; its "Downloads" subfolder is a stale copy -> lowest)
for p, rel in walk(os.path.join(H, "Desktop")):
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    if rel.split(os.sep)[0] == "Downloads":
        add(90, p, os.path.join("Documents", "Descargas del Mac", rel.split(os.sep, 1)[1])); continue
    if ext(rel) in VIDEO:
        add(0, p, os.path.join("Videos", rel)); continue
    add(0, p, os.path.join("Desktop", rel))

# --- Air Documents (prio 10)
for p, rel in walk(os.path.join(H, "Documents")):
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    top = rel.split(os.sep)[0]
    e = ext(rel)
    if BOOK_DIR.match(top.strip()):
        add(10, p, os.path.join("Documents", "Libros", rel))
    elif e in AUDIO:
        add(10, p, os.path.join("Music", "Audiolibros", rel))
    elif top == "videos" or (e in VIDEO and not PHOTO_DIR.search(top)):
        add(10, p, os.path.join("Videos", rel.split(os.sep, 1)[1] if top == "videos" else rel))
    elif os.sep in rel and PHOTO_DIR.search(top):
        add(10, p, os.path.join("Pictures", rel))
    else:
        add(10, p, os.path.join("Documents", rel))

# --- Air Photos library originals (already extracted) + Photo Booth (prio 20)
for p, rel in walk(os.path.join(CONV, "fotos-de-la-fototeca")):
    add(20, p, os.path.join("Pictures", "Fototeca Mac", rel))
for p, rel in walk(os.path.join(H, "Pictures", "Fototeca de Photo Booth", "Pictures")):  # localized: "Photo Booth Library" in English
    if not is_junk(rel):
        add(20, p, os.path.join("Pictures", "Photo Booth", rel))

# --- iBooks PDFs (prio 25); EPUB folders are re-zipped below
IB = os.path.join(H, "Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books")
for p, rel in walk(IB):
    if os.sep not in rel and ext(rel) == "pdf":
        add(25, p, os.path.join("Documents", "Libros", "iBooks", rel))

# --- Datos loose files (prio 30)
for p, rel in walk(os.path.join(B, "Datos")):
    if rel.split(os.sep)[0] == "datos mac mini":
        continue
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    add(30, p, os.path.join("Documents", "Datos 2022-2024", rel.strip()))

# --- Mac mini
for p, rel in walk(os.path.join(MM, "imagenes")):
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    add(40, p, os.path.join("Pictures", "Mac mini", rel))
for p, rel in walk(os.path.join(MM, "escritorio")):
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    if ext(rel) == "pdf":
        add(40, p, os.path.join("Documents", "Libros", "Mac mini", os.path.basename(rel)))
    else:
        add(40, p, os.path.join("Pictures", "Mac mini", "escritorio", rel))
for p, rel in walk(os.path.join(MM, "musica")):
    if is_junk(rel) or rel.split(os.sep)[0] == "Audio Music Apps":
        dropped.append(("junk", p)); continue
    if rel.split(os.sep)[0] == "Capture":  # webcam snapshots saved under musica
        add(45, p, os.path.join("Pictures", "Mac mini", "Capturas webcam", os.path.basename(rel))); continue
    if ext(rel) == "m4b" or rel.lower().startswith("audiolibros"):
        add(45, p, os.path.join("Music", "Audiolibros", rel.split(os.sep, 1)[-1]))
    else:
        add(45, p, os.path.join("Music", rel))
for p, rel in walk(os.path.join(H, "Music/iTunes/iTunes Media/Music")):
    if not is_junk(rel):
        add(46, p, os.path.join("Music", "iTunes", rel))
for p, rel in walk(os.path.join(MM, "videos")):
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    add(48, p, os.path.join("Videos", "Mac mini", rel) if ext(rel) in VIDEO else os.path.join("Pictures", "Mac mini", "videos", rel))
for prio, sub in ((50, "documentoss"), (60, "documentos")):
    for p, rel in walk(os.path.join(MM, sub)):
        if is_junk(rel):
            dropped.append(("junk", p)); continue
        e = ext(rel)
        if e in VIDEO:
            add(prio, p, os.path.join("Videos", "Mac mini", rel))
        elif e in AUDIO or e == "m4b":
            add(prio, p, os.path.join("Music", "Audiolibros", os.path.basename(rel)))
        else:
            add(prio, p, os.path.join("Documents", "Mac mini", rel))
masters = os.path.join(MM, "imagenes", "fototeca.photoslibrary", "Masters")
for p, rel in walk(masters):
    if not is_junk(rel):
        add(70, p, os.path.join("Pictures", "Fototeca Mac mini", rel))

# --- Air Downloads (lowest)
for p, rel in walk(os.path.join(H, "Downloads")):
    if is_junk(rel):
        dropped.append(("junk", p)); continue
    add(90, p, os.path.join("Documents", "Descargas del Mac", rel))

# --- extras: personal files found outside the home folder (e.g. saved into /Applications) go here
# add(10, os.path.join(B, "extras", "<file>"), os.path.join("Documents", "<file>"))
# ===================== end SOURCE RULES =====================


# ---------- de-duplicate by content
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


by_size = collections.defaultdict(list)
for c in candidates:
    try:
        sz = os.path.getsize(c[1])
    except OSError:
        dropped.append(("unreadable", c[1])); continue
    if sz == 0:
        dropped.append(("empty", c[1])); continue
    by_size[sz].append(c)

keep, dup_log = [], []
for sz, group in by_size.items():
    buckets = collections.defaultdict(list)
    for c in group:
        buckets[sha(c[1]) if len(group) > 1 else c[1]].append(c)
    for items in buckets.values():
        items.sort(key=lambda c: (c[0], bool(DUP_SUFFIX.search(os.path.basename(c[1]))), len(c[2])))
        keep.append(items[0])
        for d in items[1:]:
            dup_log.append((d[1], items[0][2]))

# ---------- resolve destination name clashes (different content, same name)
used = set()
plan = []
final = {}  # planned dest -> actual dest after tidying/clash resolution
for prio, src, dest in sorted(keep, key=lambda c: (c[0], c[2])):
    d = re.sub(r"\s+/", "/", dest).strip()
    head, _, tail = d.rpartition("/")
    if tail.startswith("."):
        d = f"{head}/sin nombre{tail[tail.find('.', 1):] if tail.find('.', 1) > 0 else ''}"
    base, dot, e = d.rpartition(".") if "." in os.path.basename(d) else (d, "", "")
    n = 2
    while d.lower() in used:
        d = f"{base} ({n}).{e}" if dot and base else f"{base} ({n})"
        n += 1
    used.add(d.lower())
    plan.append((src, d))
    final[dest] = d

reg = os.path.join(OUT, "_registro")
os.makedirs(reg, exist_ok=True)
with open(os.path.join(reg, "copiados.tsv"), "w") as f:
    f.writelines(f"{d}\t{s}\n" for s, d in plan)
with open(os.path.join(reg, "duplicados-omitidos.tsv"), "w") as f:
    f.write("omitido (original en el respaldo)\tse conservó como\n")
    f.writelines(f"{s}\t{final[k]}\n" for s, k in dup_log)
with open(os.path.join(reg, "basura-omitida.tsv"), "w") as f:
    f.writelines(f"{r}\t{s}\n" for r, s in dropped)

total = sum(os.path.getsize(s) for s, _ in plan)
dupb = sum(os.path.getsize(s) for s, _ in dup_log)
tops = collections.Counter(d.split("/")[0] for _, d in plan)
print(f"keep {len(plan)} files ({total/1e9:.1f} GB) | duplicates skipped {len(dup_log)} ({dupb/1e9:.1f} GB) | junk {len(dropped)}")
print("by top folder:", dict(tops))
if DRY:
    sys.exit()

# ---------- copy (APFS clone: instant, no extra space)
for src, dest in plan:
    dst = os.path.join(OUT, dest)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["cp", "-cp", src, dst], check=True)


# ---------- Mac-locked extras
def mk(*p):
    d = os.path.join(OUT, *p)
    os.makedirs(d, exist_ok=True)
    return d


# EPUB stored by iBooks as a folder -> real .epub file
for d in os.listdir(IB):
    full = os.path.join(IB, d)
    if not (d.endswith(".epub") and os.path.isdir(full)):
        continue
    title = d[:-5]
    for r, _, fs in os.walk(full):
        for f in fs:
            if f.endswith(".opf"):
                m = re.search(r"<dc:title[^>]*>(.*?)</dc:title>", open(os.path.join(r, f), encoding="utf-8", errors="replace").read(), re.S)
                if m:
                    title = re.sub(r'[/\\:*?"<>|]', "_", m.group(1).strip())[:80]
    out = os.path.join(mk("Documents", "Libros", "iBooks"), NFC(title) + ".epub")
    with zipfile.ZipFile(out, "w") as z:
        z.write(os.path.join(full, "mimetype"), "mimetype", compress_type=zipfile.ZIP_STORED)
        for r, _, fs in os.walk(full):
            for f in fs:
                p = os.path.join(r, f)
                rel = os.path.relpath(p, full)
                if rel != "mimetype" and not f.startswith("."):
                    z.write(p, rel, compress_type=zipfile.ZIP_DEFLATED)
    print("epub:", title)

# Safari .webarchive -> .html (text and layout; embedded images are dropped)
n = 0
for s, d in plan:
    if d.endswith(".webarchive"):
        try:
            wa = plistlib.load(open(s, "rb"))
            html = wa["WebMainResource"]["WebResourceData"]
            open(os.path.join(OUT, d[:-11] + ".html"), "wb").write(html)
            n += 1
        except Exception as e:  # keep the original if it can't be converted
            print("webarchive failed:", d, e)
print("webarchive->html:", n)

# Local-only emails (Drafts, Outbox, recovered) -> .eml
MAILV4 = os.path.join(H, "Library", "Mail", "V4")
md = mk("Documents", "Del Mac", "Correos guardados")
n = 0
for acct in os.listdir(MAILV4):
    for box in ("Drafts.mbox", "Outbox.mbox", "Mensajes recuperados (Google).mbox"):
        root = os.path.join(MAILV4, acct, box)
        for r, _, fs in os.walk(root):
            for f in fs:
                if not f.endswith(".emlx"):
                    continue
                with open(os.path.join(r, f), "rb") as fh:
                    first = fh.readline()
                    msg = fh.read(int(first.strip()))
                subj = email.message_from_bytes(msg).get("Subject", "") or "sin asunto"
                subj = str(email.header.make_header(email.header.decode_header(subj)))
                name = re.sub(r'[/\\:*?"<>|\r\n]', "_", subj)[:70].strip() or "sin asunto"
                n += 1
                open(os.path.join(md, f"{box.split('.')[0]} - {n:02d} - {name}.eml"), "wb").write(msg)
print("emails:", n)

# Notes + Safari bookmarks
cv = CONV
subprocess.run(["cp", "-cp", os.path.join(cv, "marcadores-safari.html"), mk("Documents", "Del Mac")], check=True)
subprocess.run(["cp", "-cpR", os.path.join(cv, "notas") + "/", mk("Documents", "Del Mac", "Notas")], check=True)
print("done")
