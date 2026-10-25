#!/usr/bin/env bash
# Run on the new Mint install as the normal user (NOT sudo):
#   bash 2-restore-files.sh
# Expects the reorganised, de-duplicated copy next to this folder: ../organized/{Desktop,Documents,Pictures,Music,Videos}
# (made by 2-organize/organize.py). Copies it into the user's folders; existing files are never overwritten.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$HERE")/organized"
[ -d "$SRC/Documents" ] || { echo "Missing $SRC"; exit 1; }
log() { printf '\n==> %s\n' "$*"; }

for pair in "Desktop DESKTOP" "Documents DOCUMENTS" "Pictures PICTURES" "Music MUSIC" "Videos VIDEOS"; do
  set -- $pair
  dest="$(xdg-user-dir "$2")"
  log "$1 -> $dest"
  rsync -a --ignore-existing "$SRC/$1/" "$dest/"
done

log "Make sure accented names are in Linux form (NFC)"
for d in DESKTOP DOCUMENTS PICTURES MUSIC VIDEOS; do
  convmv -r -f utf8 -t utf8 --nfc --notest "$(xdg-user-dir $d)" >/dev/null 2>&1 || true
done

log "Summary"
for d in DESKTOP DOCUMENTS PICTURES MUSIC VIDEOS; do
  p="$(xdg-user-dir $d)"; printf '%8s files  %6s  %s\n' "$(find "$p" -type f | wc -l)" "$(du -sh "$p" | cut -f1)" "$p"
done
echo
echo "Next by hand: open Chrome and sign in to the Google account (bookmarks/passwords sync back)."
echo "Old Safari bookmarks: Chrome > Bookmarks > Import > Documents/From the Mac/safari-bookmarks.html (if converted)"
