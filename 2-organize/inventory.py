"""Read-only inventory of the personal files across a backup: sizes, kinds, duplicates, junk.

Usage: python3 -I inventory.py <backup_root> <report_dir>
Edit SOURCES for each machine (name -> path relative to backup_root; a file path is also fine).
Use the report (inventory.json, dupes.tsv) to write the organize.py rules.
"""
import collections
import hashlib
import json
import os
import sys
import unicodedata

B, OUT = sys.argv[1], sys.argv[2]
SOURCES = {  # per machine: add extra volumes/partitions (backup-over-ssh.sh puts each in backup_root/<name>)
    "Documents": "home/Documents",
    "Desktop": "home/Desktop",
    "Downloads": "home/Downloads",
    "Movies": "home/Movies",
    "iTunes": "home/Music/iTunes/iTunes Media/Music",
    "PhotosLib": "converted/photos-library-originals",  # convert.py output
    "PhotoBooth": "home/Pictures/Photo Booth Library/Pictures",  # localized name differs, e.g. "Fototeca de Photo Booth"
    "iBooks": "home/Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books",
}
KIND = {
    "photo": "jpg jpeg png gif heic tif tiff bmp webp raw cr2 nef".split(),
    "video": "mp4 mov m4v avi mkv wmv 3gp mpg mpeg".split(),
    "music": "mp3 m4a aac wav flac wma ogg aiff aif".split(),
    "office": "doc docx xls xlsx ppt pptx pps ppsx odt ods odp rtf txt pages numbers key".split(),
    "pdf": ["pdf"],
    "ebook": "epub mobi azw".split(),
    "installer": "dmg pkg app exe msi zip rar 7z".split(),
}
EXT2KIND = {e: k for k, es in KIND.items() for e in es}
JUNK_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini", ".localized", "Icon\r"}


def kind(name):
    if name in JUNK_NAMES or name.startswith("._") or name.startswith("~$"):
        return "junk"
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    return EXT2KIND.get(ext, "other")


files = []  # (source, relpath, size, kind)
for src, rel in SOURCES.items():
    root = os.path.join(B, rel)
    if os.path.isfile(root):
        files.append((src, os.path.basename(root), os.path.getsize(root), kind(os.path.basename(root)), root))
        continue
    for r, ds, fs in os.walk(root):
        for f in fs:
            p = os.path.join(r, f)
            try:
                sz = os.path.getsize(p)
            except OSError:
                continue
            files.append((src, os.path.relpath(p, root), sz, kind(f), p))

# hash only files that share a size with another file
by_size = collections.defaultdict(list)
for i, f in enumerate(files):
    if f[3] != "junk" and f[2] > 0:
        by_size[f[2]].append(i)
digest = {}
for sz, idx in by_size.items():
    if len(idx) < 2:
        continue
    for i in idx:
        h = hashlib.sha256()
        with open(files[i][4], "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        digest[i] = h.hexdigest()
groups = collections.defaultdict(list)
for i, d in digest.items():
    groups[d].append(i)
dups = {d: g for d, g in groups.items() if len(g) > 1}

# --- report
rep = {}
per_src = collections.defaultdict(lambda: collections.Counter())
per_src_bytes = collections.defaultdict(lambda: collections.Counter())
for s, _, sz, k, _ in files:
    per_src[s][k] += 1
    per_src_bytes[s][k] += sz
rep["per_source"] = {s: {k: [per_src[s][k], round(per_src_bytes[s][k] / 1e6, 1)] for k in per_src[s]} for s in per_src}

wasted = sum(files[g[0]][2] * (len(g) - 1) for g in dups.values())
rep["dupes"] = {"groups": len(dups), "extra_copies": sum(len(g) - 1 for g in dups.values()), "wasted_MB": round(wasted / 1e6, 1)}
pair = collections.Counter()
for g in dups.values():
    srcs = sorted({files[i][0] for i in g})
    pair[" + ".join(srcs)] += 1
rep["dupe_groups_by_sources"] = pair.most_common(20)
# folder-level overlap: for each top-2-level folder, share of its files that also exist elsewhere
dup_idx = {i for g in dups.values() for i in g}
fold = collections.defaultdict(lambda: [0, 0, 0])
for i, (s, rel, sz, k, _) in enumerate(files):
    if k == "junk":
        continue
    parts = rel.split(os.sep)
    key = s + "/" + "/".join(parts[:2] if len(parts) > 2 else parts[:1])
    fold[key][0] += 1
    fold[key][2] += sz
    if i in dup_idx:
        fold[key][1] += 1
rep["folders"] = sorted(
    ([k, v[0], v[1], round(v[2] / 1e6)] for k, v in fold.items() if v[0] >= 5 or v[2] > 50e6),
    key=lambda x: -x[3])[:80]
big = sorted(dups.values(), key=lambda g: -files[g[0]][2])[:25]
rep["biggest_dupes"] = [[round(files[g[0]][2] / 1e6, 1)] + [files[i][0] + "/" + unicodedata.normalize("NFC", files[i][1]) for i in g] for g in big]
rep["junk"] = collections.Counter(os.path.basename(f[1]) if f[3] == "junk" else None for f in files if f[3] == "junk").most_common(8)
rep["installers"] = [f[0] + "/" + f[1] + f" ({round(f[2] / 1e6)}MB)" for f in files if f[3] == "installer"][:40]
rep["other_ext"] = collections.Counter((f[1].rsplit(".", 1)[-1].lower() if "." in f[1] else "(none)") for f in files if f[3] == "other").most_common(25)
rep["totals"] = {"files": len(files), "GB": round(sum(f[2] for f in files) / 1e9, 2)}

os.makedirs(OUT, exist_ok=True)
json.dump(rep, open(os.path.join(OUT, "inventory.json"), "w"), ensure_ascii=False, indent=1)
with open(os.path.join(OUT, "dupes.tsv"), "w") as fh:
    for d, g in dups.items():
        for i in g:
            fh.write(f"{d[:12]}\t{files[i][2]}\t{files[i][0]}/{unicodedata.normalize('NFC', files[i][1])}\n")
print(json.dumps({k: rep[k] for k in ("totals", "dupes", "per_source", "dupe_groups_by_sources", "junk", "other_ext")}, ensure_ascii=False, indent=1))
