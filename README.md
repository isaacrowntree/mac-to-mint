# mac-to-mint

Turn an old Mac (stuck on an unsupported macOS) into a Linux Mint Xfce machine that looks and feels like macOS,
keeping the owner's files. Built for a 2013 MacBook Air (MacBookAir6,1, macOS 10.12) owned by a Spanish-speaking,
non-technical user; the steps and scripts are meant to be reused for other old Macs.

No personal data lives in this repo. Backups go in `$BACKUP_DIR` on the helper Mac (e.g. `~/backups/<machine>`).

## Steps

### 1. Back up the old Mac (from a helper Mac)
1. On the old Mac: System Preferences > Sharing > **Remote Login** on.
2. `ssh-keygen -t ed25519 -f ~/.ssh/mac-to-mint && ssh-copy-id -i ~/.ssh/mac-to-mint user@ip`
3. `BACKUP_DIR=~/backups/<machine> bash 1-backup/backup-over-ssh.sh user@ip [/Volumes/<extra partition> ...]`
4. Verify: compare file counts on both sides, and spot-check checksums of random files.
   Expect a few hundred missing files from caches under `Library/Containers` - fine.
5. Note anything only the Mac has: Chrome signed in and **Sync on**? (else export passwords), Mail accounts,
   Photos libraries (also on extra partitions), printers (`lpstat -p`), personal files saved in odd places.

### 2. Convert and organise (on the helper Mac)
```
python3 -I 2-organize/convert.py   $BACKUP_DIR/home $BACKUP_DIR/convertidos   # Mail, Contacts, Calendar, Notes, Safari, Photos
python3 -I 2-organize/inventory.py $BACKUP_DIR $BACKUP_DIR/report               # sizes, kinds, duplicates, junk
# edit the SOURCE RULES in organize.py for this machine, then:
python3 -I 2-organize/organize.py  $BACKUP_DIR $BACKUP_DIR/organizado --dry-run
python3 -I 2-organize/organize.py  $BACKUP_DIR $BACKUP_DIR/organizado
```
The raw backup is never modified; `organizado/` is built with APFS clones (no extra space) and `_registro/`
logs every file kept, every duplicate skipped (with the copy kept) and every junk file dropped.

### 3. Install Mint
- Download the Mint Xfce ISO and check its SHA-256. Write it with **balenaEtcher** (it verifies the write;
  `dd` from a script is blocked by macOS privacy controls). A bad stick shows up later as random
  "Input/output error"s in the live session - re-flash or use another stick.
- Boot holding **Option**, pick **EFI Boot**. Add model boot options if needed (see Hardware notes) by pressing
  `e` on the boot entry and appending them to the `linux` line.
- Partitioning (manual, "Something else"): EFI 512 MB, `/` ext4 ~60 GB, `/home` ext4 rest. A separate `/home`
  survives a reinstall. (Splitting an existing install: shrink `/` from the live USB with `e2fsck -f`,
  `resize2fs`, `parted resizepart`, then `mkpart`, `mkfs.ext4`, copy `/home`, add it to `/etc/fstab` by UUID.)
- Install in English with the right keyboard layout; tick third-party drivers.

### 4. Set up (on the new install)
```
sudo apt install openssh-server                                       # on the new install
BACKUP_DIR=~/backups/<machine> bash 3-linux/0-enviar-desde-mac.sh user@ip   # from the helper Mac
cd ~/respaldo-mac/3-linux
sudo bash 1-configurar-sistema.sh     # hardware fixes, languages, Chrome, LibreOffice, fonts, printers... then reboot
bash 2-restaurar-datos.sh             # organizado/ -> Desktop, Documents, Pictures, Music, Videos
bash 3-apariencia-macos.sh            # macOS look (run inside the desktop session)
sudo bash 4-sistema-macos.sh          # boot + login screen, trackpad, battery saving (after script 3)
bash 5-atajos-mac.sh                  # Mac keyboard shortcuts (Toshy); then log out and back in
```
Then: Timeshift (system only, daily), sign in to Chrome, import Safari bookmarks if needed, delete
`~/respaldo-mac`, remove the helper key from `~/.ssh/authorized_keys`, and turn SSH off:
`sudo systemctl disable --now ssh.socket ssh` (Mint 22 listens through `ssh.socket` as well).

To come back later (re-run scripts 3-5 after changes): `bash tools/servir-acceso.sh` on the helper Mac prints a
`wget ... | bash` line to run on the Mint machine (temporary key + password-free sudo + SSH on). Then
`bash 3-linux/0-enviar-desde-mac.sh user@ip` (no BACKUP_DIR: sends only the scripts), run them, and
`bash tools/cerrar-acceso.sh user@ip` to undo the access.
Keep a second copy of `organizado/` + `convertidos/` before deleting the raw backup.

## What the scripts set up
- **System:** English default + a second language (`LANG2`, default `es_CO`), switchable in Settings > Languages;
  keyboard layouts switch with Alt+Shift (ES/US in the top bar). Chrome as default browser, LibreOffice saving
  .docx/.xlsx/.pptx by default, MS core fonts + Carlito/Caladea, Inter (SF Pro stand-in), Epson/Canon drivers,
  automatic updates, password login (autologin off so the keyring unlocks itself).
- **macOS look:** WhiteSur theme, `WhiteSur-light` icons (plain `WhiteSur` icons are white and vanish in a light
  menu), cursor, Inter font, window buttons on the left, centred titles, shadows, double-click to zoom, Plank dock
  (Finder, Launchpad, apps | Downloads, Trash), rotating macOS-style wallpapers, volume/brightness pop-ups,
  rounded top-right notifications, only files on the desktop, Thunar renamed Finder with Finder-like settings.
- **Menu bar:** Apple menu (Xfce's Applications Menu on a custom `.menu` file: About This Computer, System
  Settings, App Store, Force Quit, Sleep, Restart, Shut Down, Lock Screen, Log Out, with separators), then the
  global menu (`xfce4-appmenu-plugin`: active app's name in bold + its File/Edit/View menus, out of the window;
  works for Chrome, LibreOffice and GTK apps). Right side as on macOS: ES/US, tray icons, Wi-Fi, volume, battery %,
  "dom 25 oct 3:42 PM", Search, Gemini. Regular-weight text (WhiteSur makes it bold). Mint's Firefox/Terminal/Files
  launchers, show-desktop, window buttons and Languages button are removed.
- **Spotlight (⌘Space) and Launchpad (F4, dock):** rofi, not Ulauncher: it starts on demand and exits, so it uses no
  memory while closed (Ulauncher stays resident, ~100 MB+, too much for 4 GB). Spotlight: Sonoma-style bar, results
  appear once you type, apps then her files. Launchpad: full-screen grid on the blurred wallpaper; one click opens.
- **Keys:** Toshy gives ⌘C/⌘V/⌘Q/⌘W/⌘Tab; ⌘⇧3 / ⌘⇧4 save screenshots to the Desktop. Tapping ⌘ alone does nothing.
- **Boot and login:** black screen with a white Apple logo and progress bar (Plymouth script theme), GRUB menu hidden
  (Shift/Esc shows it); slick-greeter with a blurred wallpaper, WhiteSur theme and a round macOS account picture
  (made on the helper Mac from `/Library/User Pictures`, never committed).
- **Trackpad:** natural scrolling, tap to click, two-finger click = right click.
- **Battery:** dims on battery, lid = sleep, sleeps at 5 %, "Low Battery" warnings at 20 % and 10 % (UPower's
  figure, as in the menu bar; the kernel's `capacity` reads lower on this Mac), TLP.
- **Chrome language:** at each login Chrome's website languages are set from the system language (es-CO first when
  the system is Spanish) and the Translate pop-up is off for her two languages. Chrome must be closed for this.
- **Gemini:** Google's assistant as its own app window (Chrome `--app`), with a button at the far right of the menu
  bar where Siri was on macOS 10.12 (sparkle on a white circle so it shows on any wallpaper). There's no
  Gemini desktop app for Linux. Chrome's built-in "Gemini in Chrome" and its dictation into web text boxes
  ("Talk to type", Chrome 156) are rolling out by country; Linux availability is unclear, so check Chrome itself.
  The Apple logo and Gemini icon are downloaded at run time (WhiteSur source, gstatic), not stored here.

## Hardware notes (MacBookAir6,1, 2013) - most apply to 2013-2015 MacBooks
| Problem | Fix (in `1-configurar-sistema.sh`, gated on the hardware) |
|---|---|
| SSD invisible to the installer; `ata1: failed to IDENTIFY` (Marvell 88SS9183, `1b4b:9183`) | boot with `intel_iommu=off` |
| Desktop freezes after ~1 h, hundreds of `ata1: hard resetting link`, I/O errors | SATA link power saving off: `ahci.mobile_lpm_policy=1` |
| No Wi-Fi in the installer (Broadcom BCM4360) | `bcmwl-kernel-source` (on the Mint ISO); Driver Manager in the live session |
| No camera (FaceTime HD, `14e4:1570`) | `facetimehd` driver + firmware via DKMS |
| Runs hot | `mbpfan` |
| Top-row keys | work by default (`hid_apple fnmode=3`); pop-ups need enabling (script 3) |

**TLP undoes the SATA fix** unless told not to: its defaults turn SATA link power management back on on battery.
Script 4 writes `/etc/tlp.d/90-apple.conf` (`SATA_LINKPWR_ON_BAT=max_performance`, AHCI runtime PM off, Wi-Fi
power saving off) on Apple hardware.

`libata.force=noncq,1.5Gbps` is **not** needed - with the two options above the SSD runs at 6 Gb/s with NCQ.

## Lessons
- Run scripts that change the desktop (panel, dock) inside the session, not over SSH: an SSH-started panel or
  dock loses the session environment (no transparency, plank refuses to start). Logging out and in fixes it.
- `pkill -f "<pattern>"` inside `ssh host '...<pattern>...'` kills its own shell. Kill by PID or exact name.
- WhiteSur's installer needs `TERM` set (it calls `setterm`) and writes the Whisker menu opacity to a file
  Xfce 4.18+ ignores; set `menu-opacity` < 100 through xfconf or the menu gets black corners.
- Don't restart the panel (`xfce4-panel -r`) more than needed: it can take nm-applet, blueman and the update icon
  down with it. Relaunch them from their `/etc/xdg/autostart` entries, or log out and in.
- Files the panel watches (custom menus) must be replaced atomically, or it shows "Could not load the applications
  menu" while the file is half written.
- Test changes on the real machine with screenshots: `import -window root` + `convert -crop`, crop on the target so
  only the part being checked leaves the machine.
