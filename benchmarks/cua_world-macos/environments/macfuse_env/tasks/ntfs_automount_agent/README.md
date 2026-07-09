# `ntfs_automount_agent` — NTFS Auto-Mount System with macFUSE + ntfs-3g

Environment: `macfuse_env@0.1` (macOS, use.computer dev fleet)

## Domain context

A Mac power user (name: `lume`) keeps a small library of Windows-formatted
(NTFS) external drives — old portable USB drives that hold a home movie
archive, photo backups, and tax-record scans. Plugging them into a Mac is
painful by default: macOS mounts NTFS read-only via `mount_ntfs`, so the
user can read the family photos but cannot move files to or from the drive
without exporting through an intermediary.

The standard fix on macOS is the macFUSE + ntfs-3g pair:

- **macFUSE** is the FUSE filesystem framework for macOS — it gives userspace
  filesystem drivers a kext-mediated path to mount real volumes. macFUSE is
  pre-installed at `/Library/Filesystems/macfuse.fs/` in this sandbox.
- **ntfs-3g** is the userspace NTFS driver that talks to macFUSE. The original
  Tuxera-maintained Homebrew formula `ntfs-3g` was disabled in 2021 (its
  kext-loading model broke on Catalina+). The community-maintained fork that
  works on modern macOS is `gromgit/fuse/ntfs-3g-mac`, distributed as a
  pre-built binary bottle via the `gromgit/fuse` tap.

The user wants a one-time-setup, zero-touch experience: every NTFS drive
they plug in should mount read-write under a predictable name, with a clean
unmount script available for when they're done. They also want this to fire
**automatically** when a drive appears — not on every reboot, not on a
polling timer, but exactly when the macOS volume topology changes. The
right launchd hook for that is `WatchPaths` on `/Volumes`, which fires
whenever any subdirectory under `/Volumes` is added or removed.

## What the agent must build

1. **Homebrew** present on the machine (re-use the system install if there is
   one; otherwise run the official non-interactive installer).
2. **`gromgit/fuse` tap + `ntfs-3g-mac` formula** installed (`brew tap
   gromgit/fuse` then `brew install gromgit/fuse/ntfs-3g-mac`). This drops a
   working `mount_ntfs` / `ntfs-3g` binary into Homebrew's `sbin`/`bin`.
3. **`~/Documents/ntfs-automount.sh`** — executable shell script that:
   - Takes a single positional argument, a disk identifier such as `disk2s1`.
   - Calls `diskutil info /dev/$1` to learn the filesystem type and volume
     name.
   - Decides whether the disk is NTFS by grepping for `Windows_NTFS` or
     `NTFS` in the diskutil output.
   - If NTFS: creates `/Volumes/NTFS_<VolumeName>` if it doesn't already
     exist, then mounts the drive read-write using
     `sudo ntfs-3g /dev/$1 /Volumes/NTFS_<VolumeName> -olocal,allow_other,auto_xattr`
     (preferred) or `sudo /usr/local/sbin/mount_ntfs -o rw,auto,nobrowse,nodev
     /dev/$1 /Volumes/NTFS_<VolumeName>` as a fallback.
   - Logs every action with a timestamp to `~/Documents/ntfs-automount.log`.
   - Gracefully handles the not-NTFS and mount-failed cases (logs a message,
     exits non-zero).
4. **`~/Documents/ntfs-unmount.sh`** — executable companion script that lists
   all mounted volumes named `NTFS_*` and runs `diskutil unmount` on each.
5. **`~/Library/LaunchAgents/com.lume.ntfs-automount.plist`** — LaunchAgent
   plist with:
   - `Label` = `com.lume.ntfs-automount`
   - `ProgramArguments` = `["/bin/bash", "-c", "/Users/lume/Documents/ntfs-automount.sh"]`
   - `WatchPaths` = `["/Volumes"]` (fires on every `/Volumes` add/remove)
   - `RunAtLoad` = `false`
   - `StandardOutPath` = `/Users/lume/Documents/ntfs-automount.log`
   - `StandardErrorPath` = `/Users/lume/Documents/ntfs-automount.err`
6. The plist loaded via `launchctl load ~/Library/LaunchAgents/com.lume.ntfs-automount.plist`.

## Why the kext / live-mount path is not required

The use.computer base-macos sandbox has SIP enabled and kext user consent
enabled — see `specific_env_notes/macfuse_macos/notes.md`. The macFUSE kext
**cannot load** on this image (kext load on Apple Silicon needs Recovery
Mode, which the sandbox doesn't expose). Live NTFS mounts therefore cannot
be exercised. The verifier inspects the installed Homebrew artifacts +
the on-disk scripts + the on-disk plist, NOT a live mount. This is the
same "audit what's installed, not what's running" pattern used by
`audit_macfuse_install`.

## Why this is hard

Difficulty rating: `hard`.

- **Discovery burden**: low — the task description names the exact Homebrew
  tap, the exact formula, the exact paths for all three artifacts, and the
  exact LaunchAgent keys. The agent does not have to figure out *what* to
  build, only *how*.
- **Skill burden**: high — the agent must (a) install Homebrew
  non-interactively from a shell that has no terminal-attached prompt, (b)
  add a tap and install a non-standard formula, (c) write a shell script
  with conditional logic, error handling, and timestamped logging, (d)
  author a valid LaunchAgent plist (XML or via `defaults write` / `plutil`),
  (e) load it under launchd. Each step uses a different macOS subsystem.
- **Anti-gaming**: writing the three text artifacts without installing
  Homebrew or ntfs-3g would otherwise score 75 (above the 70 pass
  threshold). The verifier closes this leak with Gate 2 (see Scoring).

## Scoring (100 pts, pass at 70)

| Criterion | Pts | Partial | Notes |
|---|---:|---:|---|
| C1 Homebrew installed | 10 | — | binary at /opt/homebrew/bin/brew, /usr/local/bin/brew, or linuxbrew prefix |
| C2 ntfs-3g binary present | 15 | — | mount_ntfs or ntfs-3g under any Homebrew prefix |
| C3 ntfs-automount.sh exists + executable + has `diskutil` | 20 | 5 | partial = exists but not exec OR no diskutil |
| C4 ntfs-automount.sh NTFS detection (`Windows_NTFS` or `NTFS`) | 15 | — | binary |
| C5 ntfs-automount.sh mount command (`ntfs-3g` or `mount_ntfs`) | 15 | — | binary |
| C6 ntfs-unmount.sh exists + executable | 5 | — | binary |
| C7 LaunchAgent plist with Label + WatchPaths=[/Volumes] | 20 | — | binary |
| **Total** | **100** | | pass at **70** |

Anti-Pattern 4 safety: sum of all partial-only credit = 5 (only C3 has a
partial). 5 ≪ 70 pass threshold. ✓

## Strategy enumeration (Anti-Pattern 13)

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | C7 | Score | Pass? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | ✗ |
| Files only, no brew (Gate 2 capped) | 0 | 0 | 20 | 15 | 15 | 5 | 20 | **50** | ✗ |
| Install brew only | 10 | 0 | 0 | 0 | 0 | 0 | 0 | **10** | ✗ |
| Install brew + ntfs-3g, no scripts | 10 | 15 | 0 | 0 | 0 | 0 | 0 | **25** | ✗ |
| Install brew + ntfs-3g, scripts but no plist | 10 | 15 | 20 | 15 | 15 | 5 | 0 | **80** | ✓ |
| Correct (everything) | 10 | 15 | 20 | 15 | 15 | 5 | 20 | **100** | ✓ |
| Brew but no ntfs-3g (skipped install), all else right | 10 | 0 | 20 | 15 | 15 | 5 | 20 | **85** | ✓ |

The "files only, no brew" row is the key adversarial check. Without Gate 2
that row would naturally score 75 and pass — clearly wrong (no tools = no
NTFS mounting capability, just hopeful-looking text files). Gate 2 caps the
no-tool-install case at 50, strictly below the 70 pass threshold.

The "brew but no ntfs-3g" row passes at 85. That is **intentional**: the
agent that installed Homebrew and wrote a correct mount-helper script that
references ntfs-3g/mount_ntfs by name has demonstrated they understand the
shape of the system, even if the binary install failed. Worth 85/100 as a
near-correct solution; not a 100, because the binary really isn't there.

## Gates

- **Gate 1 (no work)**: no brew, no ntfs-3g, no scripts, no plist → score 0.
- **Gate 2 (no tool install)**: both `brew_present=False` AND
  `ntfs3g_present=False` → cap total at 50. Closes the "wrote text files
  but didn't run brew" shortcut.

## Setup → Export → Verify flow

1. **`setup_task.sh`** (pre_task)
   - Removes any pre-existing scripts, plist, and log files.
   - `launchctl unload` the plist if it is loaded from a previous run.
   - Creates `~/Documents` and `~/Library/LaunchAgents` if missing.
   - Records `task_start` Unix timestamp at
     `/tmp/ntfs_automount_agent_task_start_timestamp`.
   - Launches Terminal so the agent has a CLI surface.
   - Captures a start-state screenshot.
   - Does NOT echo any expected paths, identifiers, or plist keys.

2. **Agent action** (max 70 steps)
   - Install Homebrew (re-use the system install if present at
     `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`; otherwise run the
     official non-interactive installer with `NONINTERACTIVE=1`).
   - `brew tap gromgit/fuse && brew install gromgit/fuse/ntfs-3g-mac`.
   - Write `~/Documents/ntfs-automount.sh`, make executable.
   - Write `~/Documents/ntfs-unmount.sh`, make executable.
   - Write `~/Library/LaunchAgents/com.lume.ntfs-automount.plist` (XML or
     via `defaults write` / `plutil -convert xml1`).
   - `launchctl load` the plist.

3. **`export_result.sh`** (post_task)
   - Captures end-state screenshot.
   - Probes Homebrew presence at the canonical prefixes.
   - Probes ntfs-3g/mount_ntfs presence under every Homebrew sbin/bin.
   - Reads both scripts, checks existence/executability and runs grep for
     the required substrings (`diskutil`, NTFS detection, mount command).
   - Converts the LaunchAgent plist to JSON via `plutil -convert json -o -`
     and extracts `Label` + `WatchPaths` for verifier inspection.
   - Emits `/tmp/ntfs_automount_agent_result.json`.

4. **`verifier.py`** (program-mode success)
   - `copy_from_env` pulls the result file to a local temp path.
   - Applies the seven criteria + the two gates above.
   - Returns `{score, passed, feedback, subscores}`.

## Edge cases the agent must handle

- **Disk identifier not NTFS**: the script must log "not NTFS" and exit
  non-zero without attempting a mount.
- **Mount point already exists**: do not blindly `mkdir -p` and overwrite —
  test, log, reuse the existing point.
- **`sudo` required**: `mount_ntfs` and `ntfs-3g` need root to attach.
  The `lume` account has passwordless sudo in this sandbox — the script
  may invoke `sudo` directly.
- **Homebrew install on a fresh system**: the official installer is
  interactive by default. Use `NONINTERACTIVE=1 /bin/bash -c "$(curl
  -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  if no system brew is present.
- **plist format**: macOS accepts either XML or binary plists; both load
  identically. The verifier reads via `plutil -convert json` which handles
  both. The agent should not assume a specific physical format.

## Notes

- Pre_task convention (`12_macos_environments.md`): pre_task launches the
  natural-surface app. For a sysadmin / shell scripting task that is
  Terminal, mirroring `audit_macfuse_install`.
- No AX over SSH — the verifier is entirely file-and-binary-inspection,
  no menu walks. Avoids the TCC trap described in `12_macos_environments.md`.
- Live FUSE mount is NOT exercised by the verifier (kext can't load in
  sandbox). The artifact the user actually wants — a working auto-mount
  system that runs when their drive appears — is verified by inspecting
  the components that compose that system.
