#!/usr/bin/env bash
# Back up an old Mac over SSH by streaming tar (works with the old tools on 10.x: rsync 2.6.9, no python3).
# tar, not rsync: this Mac's openrsync can't create filenames with invalid UTF-8 bytes ("Illegal byte sequence").
#
# On the old Mac: System Preferences > Sharing > Remote Login on, then authorize a key:
#   ssh-keygen -t ed25519 -f ~/.ssh/mintosh && ssh-copy-id -i ~/.ssh/mintosh user@ip
# Usage:
#   BACKUP_DIR=~/backups/<machine> bash 1-backup/backup-over-ssh.sh user@ip [/Volumes/Extra ...]
# Copies the user's home (minus caches/logs/trash) to $BACKUP_DIR/home, each extra volume to $BACKUP_DIR/<name>,
# plus /Users/Shared, user fonts and a list of installed apps to $BACKUP_DIR/extras. The old Mac is only read.
set -uo pipefail
DEST="${1:?usage: $0 user@ip [/Volumes/Extra ...]}"; shift
B="${BACKUP_DIR:?set BACKUP_DIR}"
KEY="${KEY:-$HOME/.ssh/mintosh}"
SSH() { ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "$DEST" "$@" 2> >(grep -v -e post-quantum -e "store now" >&2); }
L="$B/backup.log"
mkdir -p "$B/home" "$B/extras"
echo "START $(date)" > "$L"

echo "== home" | tee -a "$L"
SSH 'cd ~ && tar -cf - --exclude Library/Caches --exclude Library/Logs --exclude .Trash .' 2>>"$L" | tar -xf - -C "$B/home" 2>>"$L"
echo "home done $(date)" | tee -a "$L"

for vol in "$@"; do
  name=$(basename "$vol"); mkdir -p "$B/$name"
  echo "== $vol" | tee -a "$L"
  SSH "cd '$vol' && tar -cf - --exclude .Spotlight-V100 --exclude .fseventsd --exclude .Trashes --exclude .TemporaryItems --exclude .DocumentRevisions-V100 ." 2>>"$L" | tar -xf - -C "$B/$name" 2>>"$L"
  echo "$name done $(date)" | tee -a "$L"
done

echo "== extras" | tee -a "$L"
SSH 'tar -cf - -C /Users Shared' 2>>"$L" | tar -xf - -C "$B/extras" 2>>"$L"
SSH 'tar -cf - -C /Library Fonts' 2>>"$L" | tar -xf - -C "$B/extras" 2>>"$L"
# system_profiler can hang on old Macs; the plain listing is enough
SSH 'ls /Applications; echo ---; ls /Applications/Utilities' > "$B/extras/installed-apps.txt" 2>>"$L"
echo "ALL DONE $(date)" | tee -a "$L"

echo
echo "Verify before wiping the Mac: compare file counts, e.g."
echo "  ssh ... 'cd ~ && find . -type f -not -path \"./Library/Caches/*\" | wc -l'   vs   find \"$B/home\" -type f | wc -l"
echo "Personal documents saved loose in /Applications or elsewhere are not included - check installed-apps.txt."
