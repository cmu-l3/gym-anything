# Finder on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/finder_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.x)

> **See also:** `12_macos_environments.md` for the general macOS env
> guide; `specific_env_notes/safari/notes.md` for the preinstalled-app
> baseline; `specific_env_notes/google_earth_macos/notes.md` for a
> DMG-install env. Finder shares the "preinstalled, install script just
> verifies the bundle" shape with Safari, but has its own quirks.

---

## Install Story: Even More Trivial than Safari

Finder is the **macOS shell** — preinstalled at
`/System/Library/CoreServices/Finder.app` (note: NOT `/Applications/`,
NOT `/System/Applications/`; deeper in the OS bundle hierarchy than the
"Apple system apps" the 12_macos_environments.md guide calls out).
Finder is launchd-managed: if you `killall Finder`, launchd respawns it
within ~1s. `install_finder.sh` just verifies the bundle exists and
prints the version — no DMG, no Rosetta, no brew, no pkg.

Reset cost on a warm sandbox: ~10-15s. Faster than Safari's ~15-20s
because there's literally nothing to install.

---

## Process Detection: `pgrep -x Finder` Is Trivially Positive

Because Finder is the shell and launchd respawns it, `pgrep -x Finder`
is essentially always positive on a healthy image. **Don't use it as a
verifier's primary signal** — it gives you no information about whether
the env is in the right state.

Instead, combine with:

1. **Window count via AppleEvents** (works over SSH, see next section):
   ```bash
   osascript -e 'tell application "Finder" to count windows'
   ```
2. **Filesystem state** — Finder writes `.DS_Store` files into folders
   it visits, but more importantly, the agent's intended output (created
   directories, moved files, applied tags) lives on the filesystem.
   Read it directly with Python `os.listdir`, `xattr`, etc.
3. **Finder preferences** (`defaults read com.apple.finder`) for
   view-mode, sidebar-content, and similar configuration state.

---

## AppleEvents to Finder Work Over SSH

The 12_macos_environments.md "AppleScript / Accessibility over SSH: TCC
Trap" section warns that `tell application "System Events" to ...` (AX
walks) fail silently over SSH due to the responsibility chain rooted at
`sshd-keygen-wrapper`. Apple's TCC framework gates the "Accessibility"
permission against that chain.

**However**, basic AppleEvents to known apps (the "Automation"
permission) are a separate TCC category and *do* work over SSH for
read-only queries against Finder. Confirmed live during the
`launch_finder` smoke verifier on 2026-05-18:

```bash
osascript -e 'tell application "Finder" to count windows'
# → "1"   (window was opened by pre_task via `open ~/Downloads`)
```

This is consistent with `safari_env/scripts/setup_safari.sh` using
`osascript -e 'tell application "Safari" to quit'` to flush the
History.db WAL — basic AppleEvents to first-party apps go through. The
finder_env smoke verifier relies on this.

**Caveat**: AppleEvents that *modify* state (especially `tell
application "Finder" to make new folder`, `move`, `duplicate`) may
trigger different TCC permission checks. Not yet probed end-to-end; the
finder_env tasks use shell `mkdir`/`mv` rather than AppleScript Finder
operations. If a future task genuinely needs Finder-via-AppleScript for
file ops, probe first against `~/Documents/` (sandbox-controlled) before
relying on it.

---

## `defaults write com.apple.finder` + `killall Finder`

Finder preferences live in `com.apple.finder`. Unlike Safari, where some
prefs (IncludeDevelopMenu) don't propagate at all and others need to be
written to the sandbox container path, Finder reads from the standard
`~/Library/Preferences/com.apple.finder.plist` and a `killall Finder`
forces it to reload the new values on respawn.

`setup_finder.sh` writes:

| Key | Type | Purpose |
|---|---|---|
| `AppleShowAllExtensions` | bool | Show .pdf/.txt/.zip suffixes |
| `AppleShowAllFiles` | bool | Hidden files (default: false) |
| `ShowPathbar` | bool | Path bar at bottom of window |
| `ShowStatusBar` | bool | Status bar at bottom |
| `FXPreferredViewStyle` | string | View mode (clmv/icnv/Nlsv/glyv) |
| `FXDefaultSearchScope` | string | Default search scope (SCcf/SCev/SCsp) |
| `NewWindowTarget` | string | `PfLo` = a specific path... |
| `NewWindowTargetPath` | string | ...this URL (file://$HOME/Downloads/) |
| `WarnOnEmptyTrash` | bool | No nag when emptying trash |
| `FXEnableExtensionChangeWarning` | bool | No nag when renaming .txt → .md |

After all writes, `setup_finder.sh` does `killall cfprefsd; killall
Finder; <poll for respawn>`. launchd respawns Finder within ~1s; the
poll loop catches it before the next hook runs.

### Finding 1: `FXPreferredViewStyle` Doesn't Override Per-Folder View State (Workaround Available)

Setting `FXPreferredViewStyle = "clmv"` (column view) globally does NOT
force ~/Downloads to open in column view. Finder has a separate
per-folder view-state store that overrides the global default. The
relevant per-folder key lives inside the folder's own `.DS_Store` file.
On a fresh use.computer sandbox, ~/Downloads opens in list view
(`Nlsv`) regardless of the global pref.

**Workaround (confirmed working 2026-05-18 — audit B1 fix)**: after
`open <dir>` in `setup_task.sh`, send an AppleEvent to Finder to set
the current view of the front window:

```bash
/usr/bin/open "$HOME/Downloads"
sleep 2
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1
```

AppleEvents to Finder work over SSH (Automation TCC, not Accessibility
TCC) — see Finding "AppleEvents to Finder Work Over SSH" above. The
view-mode setter writes to the folder's `.DS_Store` and persists for
subsequent opens.

Other view-mode strings: `icon view`, `list view`, `column view`,
`group view` (AppleScript-friendly names — different from
`FXPreferredViewStyle`'s 4-char codes).

**Practical implication**: keep `FXPreferredViewStyle = "clmv"` in
`setup_<app>.sh` as the default for fresh folders, AND apply the
AppleEvent in `setup_task.sh` for any specific folder where the
saved-view-state needs to be overridden.

### Finding 2: `open <dir>` Doesn't Refresh an Already-Open Finder Window

When ~/Downloads is already open in a Finder window and you change its
contents via shell (`mkdir`, `mv`, `rm`), the Finder window does **not**
re-read the directory automatically. Subsequent screenshots will show
the stale view.

Surfaced in `organize_downloads_by_type` happy_path on 2026-05-18: after
running `mkdir Documents Images Archives Other` and 8× `mv` calls via
SSH, the screenshot still showed the 8 source files. Re-running
`open /Users/lume/Downloads` forced Finder to bring the existing window
forward AND re-read the directory listing.

**Practical recipe** for tasks that mutate the filesystem outside Finder
and then need a fresh screenshot:
```bash
ssh.exec("open /Users/lume/Downloads")
sleep 2
# Or, for surgical refresh without bringing the window forward:
ssh.exec("osascript -e 'tell application \"Finder\" to update front window'")
```
(Not yet probed which AppleEvent works most reliably for refresh —
defaulting to `open` for now.)

### Finding 3: `display.get_info()` Returns 0×0 on a Cold Sandbox

The use.computer SDK's `MacOSSandbox.display.get_info()` returns
`{width: 0, height: 0, scale: 1.0}` on a fresh sandbox until the
display has been touched (a screenshot, a mouse move, anything).
`finder_session.py` works around this by reading the screenshot's
actual dimensions (`Image.open(...).size`) and patching the session
state after boot.

**Better fix** (not yet pushed): have `MacOSSandbox.__init__` warm the
display by taking and discarding a 1-byte screenshot, or have the SDK
return the configured resolution from the sandbox spec rather than
querying the live display state. Reported here for future use.computer
integration work.

### Finding 4: `Enter` ≠ `Return` for Finder Rename Commit

Surfaced in the interactive_pilot on 2026-05-18 (see
`benchmarks/cua_world-macos/environments/finder_env/evidence_docs/organize_downloads_by_type/interactive_pilot/`).

When creating folders via `Cmd+Shift+N` + typing the name, the
**`Return`** key sometimes fails to commit the rename — Finder displays
the new name in the UI but the underlying filesystem entry stays as
`untitled folder`. This is consistent with the safari address-bar
finding documented in `12_macos_environments.md`: in macOS form-submit
contexts, `Enter` (kVK_ANSI_KeypadEnter) and `Return` (kVK_Return) are
different key codes and apps gate "commit" on the former.

**Rule for Finder UI driving**:
- Use `Enter` to commit a rename, accept a value in a dialog, etc.
- `Return` works inside text fields for newlines but NOT for form
  submission.

Empirically, the failure mode for `Return`-after-`type` in a Finder
rename is **race-conditioned with subsequent operations**: a single
`Cmd+Shift+N` + `type "X"` + `Return` works in isolation, but in a
tight batch the last iteration's `Return` can land while Finder is
still settling the previous rename, leaving it half-applied. `Enter`
does not exhibit this race.

```bash
# RELIABLE pattern for batch folder creation:
for name in Documents Images Archives Other; do
  python3 .../finder_session.py key cmd+shift+n
  sleep 1.5
  python3 .../finder_session.py type "$name"
  sleep 1
  python3 .../finder_session.py key Enter         # ← Enter, NOT Return
  sleep 2
done
```

### Finding 5: TCC "Files and Folders" Dialog Blocks Terminal Access to ~/Downloads (and friends)

Surfaced in the interactive_pilot on 2026-05-18 when Terminal (opened
via Dock click) tried to `mv` files inside `~/Downloads`. macOS pops a
modal dialog:

> **"Terminal" would like to access files in your Downloads folder.**
> [Don't Allow]   [Allow]

Until the user clicks Allow, subsequent file operations against the
protected location silently fail. macOS protects: ~/Downloads,
~/Documents, ~/Desktop, ~/Pictures, ~/Movies, ~/Music, iCloud Drive,
removable volumes, and a few network shares.

**Implications for tasks**:

1. **Tasks that use Terminal via the Dock to manipulate ~/Downloads,
   ~/Documents, etc., must expect this dialog on first touch.** The
   agent (and any UI-driving simulator) needs to find and click `Allow`
   before continuing.

2. **The grant persists per-app-per-folder for the sandbox's life.**
   Once Terminal is granted ~/Downloads access in a session, subsequent
   moves succeed. But because use.computer sandboxes are torn down on
   destroy (no checkpoint caching), the prompt re-appears on every
   fresh sandbox.

3. **Pre-granting via shell commands does NOT work.** `tccutil` and
   `sudo sqlite3` writes to `~/Library/Application Support/com.apple.TCC/TCC.db`
   either fail (System Integrity Protection on macOS) or get reverted
   by tccd on the next consent check. The dialog must be clicked.

4. **Hooks running over SSH bypass TCC for the SSH chain** (because
   the SSH chain doesn't go through Terminal.app). So `mkdir` and `mv`
   in `setup_task.sh` and `export_result.sh` work without prompting.
   This is why the SSH-driven `happy_path/` flow never sees the dialog,
   but the interactive_pilot does.

**Practical recipe for finding the Allow button**:
```bash
# After the dialog appears, ask visual_grounding (note coords are
# typically returned in a confused scale — verify against the
# screenshot before clicking):
python3 .../finder_session.py ground "Where is the blue Allow button in the macOS permission dialog?" /tmp/dialog.png

# Empirical observation for a 1920x1080 display with the dialog
# centered: Allow button at roughly (1010, 340) display pixels.
python3 .../finder_session.py click 1010 340
```

### Finding 6: `visual_grounding` Coordinate Scale Is Inconsistent

Surfaced repeatedly during the interactive_pilot. The
`visual_grounding` MCP tool returns coords with a "1280x720 scale"
note in its output, but the actual numbers sometimes correspond to:
- 1280x720 scale (correct, matches the note)
- 1920x1080 actual display pixels (mislabeled)
- 1000-normalized (occasionally)

**Working strategy**: treat visual_grounding output as a hint, not
ground truth. Always cross-check by:
1. Looking at the screenshot manually.
2. Computing pixel coords from observed UI layout.
3. If coords differ between visual_grounding and manual estimate by
   more than 10%, trust manual.

This isn't a finder_env-specific issue but applies to every macOS env
that uses visual_grounding for click targeting. Worth fixing upstream
in the MCP server's prompt template so the model is forced to be
consistent about the coordinate space.

---

## State Files for Verifier Strategy

Prefer filesystem-based verifiers over UI inspection (Finder doesn't
have nearly as rich a state-file surface as Safari). Useful paths:

| State | Path |
|-------|------|
| Folder structure | walk the directory tree |
| Per-folder view state | `<dir>/.DS_Store` (binary store) |
| Recent items | `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl3` (binary) |
| Sidebar items | `~/Library/Preferences/com.apple.sidebarlists.plist` (binary plist) |
| Favorites (sidebar Favorites section) | `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl3` (binary) |
| Tags / color labels per file | `xattr -p com.apple.metadata:_kMDItemUserTags <file>` (binary plist) |
| Finder Comments | `xattr -p com.apple.metadata:kMDItemFinderComment <file>` (XML plist) |
| User defaults | `defaults read com.apple.finder` |

For "did the agent organize Downloads?" tasks, simply walk
`~/Downloads/` with `os.listdir` and check the layout.

For "did the agent tag a file with Red?" tasks, parse the xattr binary
plist:
```python
import plistlib, subprocess
raw_hex = subprocess.run(
    ["xattr", "-px", "com.apple.metadata:_kMDItemUserTags", file],
    capture_output=True, text=True).stdout
raw = bytes.fromhex(raw_hex.replace(" ", "").replace("\n", ""))
tags = plistlib.loads(raw)  # → list of "Red\n6" style strings
```
(The number after `\n` is Finder's internal color index: 1=Gray, 2=Green,
3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange.)

---

## Task Inventory

Current tasks in `finder_env/tasks/`:

| Task | Difficulty | Coverage |
|---|---|---|
| `launch_finder` | easy (smoke) | Process + window verification end-to-end |
| `organize_downloads_by_type` | hard | Folder creation + file moves, with strict wrong-target gate |

Future task ideas (not built):
- `tag_invoice_files` — apply colored tags via right-click → Tags menu.
  Verifier reads `xattr com.apple.metadata:_kMDItemUserTags`.
- `rename_screenshots_to_iso_date` — bulk rename pattern-matched files.
- `create_smart_folder` — File > New Smart Folder with a saved query.
  Verifier parses `~/Library/Saved Searches/<name>.savedSearch` plist.
- `compress_project_into_zip` — Finder's File > Compress menu produces
  Archive.zip; agent must rename it. Verifier checks ZIP integrity +
  contents.

---

## Known Gotchas

- **Don't echo target folder assignments in `setup_task.sh`.** The 8
  file names ARE in task.json's description (acceptable — agent reads
  the description), but the categorization rule should be derived from
  the extension, not learned by reading setup output (Anti-Pattern #10).
- **`set -eu` + `find -delete`**: macOS `find` doesn't support
  `-delete` reliably across versions. Use `find ... -exec rm -rf {} +`
  for portability (used in `organize_downloads_by_type/setup_task.sh`).
- **`touch -t YYYYMMDDHHMM` is BSD-style on macOS**, not GNU. The
  format takes `[[CC]YY]MMDDhhmm[.SS]` — using `date -v-Xd` to compute
  past dates works without explicit `-c` or `-r` flags (BSD `date -v`
  is the macOS-equivalent of GNU `date --date "-X days ago"`).
- **Finder respawns even after `killall -9 Finder`**. launchd is firm.
  Don't try to prevent the respawn for tasks that need Finder "quit" —
  it's not possible without disabling launchd. For tasks that need a
  clean window state, just `osascript -e 'tell application "Finder" to
  close every window'` instead.

---

## Quick-Reference Commands

```bash
# Open a folder window
open ~/Downloads

# Count open Finder windows (works over SSH; AppleEvent, not AX)
osascript -e 'tell application "Finder" to count windows'

# Force refresh of front window
osascript -e 'tell application "Finder" to update front window'
# or
open ~/Downloads   # idempotent — brings existing window forward + re-reads

# Read a Finder pref
defaults read com.apple.finder FXPreferredViewStyle

# Inspect tags on a file
xattr -p com.apple.metadata:_kMDItemUserTags /path/to/file 2>/dev/null \
  || echo "no tags"

# Reset Downloads to empty (safe for task setup; preserves dotfiles)
find ~/Downloads -mindepth 1 -maxdepth 1 -exec rm -rf {} +
```
