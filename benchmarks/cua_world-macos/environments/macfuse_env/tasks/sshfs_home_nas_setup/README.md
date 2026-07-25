# `sshfs_home_nas_setup` — Persistent SSHFS Mount for a Home NAS

Environment: `macfuse_env@0.1` (macOS, use.computer dev fleet)

## Domain context

SSHFS lets you mount a remote directory over SSH and have it appear as a
local folder. It's a staple of the homelab / Raspberry Pi crowd: instead of
copying files back and forth with `scp`, you mount `pi@server:/home/pi/shared`
once and treat it like any other Finder location.

On macOS, SSHFS is delivered as a macFUSE-backed filesystem. The standard
distribution channel — since the original osxfuse project stopped publishing
sshfs binaries — is the third-party Homebrew tap [`gromgit/fuse`][gromgit].
Once installed, the user typically wants the mount to come up automatically
at every login, which on macOS means a **LaunchAgent** (`launchd` plist) in
`~/Library/LaunchAgents/`.

A real-world configuration of "my Mac transparently shows my Pi's NAS folder"
therefore involves five distinct artifacts that all have to be correct
together:

1. The base toolchain — Homebrew, the gromgit tap, the `sshfs` binary.
2. A mount point — an empty directory the filesystem will be glued onto.
3. SSH connectivity config — a `Host homeserver` block in `~/.ssh/config`
   so the mount script can refer to the NAS by short name.
4. A mount script — invokes `sshfs` with the right macFUSE-specific options
   (`volname`, `defer_permissions`, `reconnect`).
5. A LaunchAgent plist — runs the mount script at login and restarts it if
   it dies.

The agent's job is to construct all five artifacts so that the next login
would mount the NAS automatically. Actual *mounting* won't succeed inside
this sandbox (the macFUSE kext can't load on the Apple Silicon VM — SIP +
kext consent gate), but every setup artifact above can be inspected
authoritatively on disk and that is what the verifier scores.

[gromgit]: https://github.com/gromgit/homebrew-fuse

## Why this is very_hard

Difficulty rating: `very_hard`.

- **Discovery burden**: high. The agent must know that sshfs is not in
  core Homebrew anymore, that `gromgit/fuse` is the de-facto tap, that
  macOS uses LaunchAgents (not systemd) for login-time daemons, and that
  the macFUSE option set differs from Linux sshfs (e.g.
  `defer_permissions` is macOS-only).
- **Path burden**: high. Five separate filesystem artifacts at different
  conventional paths (`~/.ssh/config`, `~/Documents/`, `~/Library/LaunchAgents/`).
  Each has its own grammar (SSH config keywords vs plist XML vs shell script).
- **Cross-file correctness**: the LaunchAgent's `ProgramArguments` must point
  at the mount script the agent wrote; the mount script must reference the
  SSH host alias the agent configured; the SSH host alias must reference a
  user (`pi`), hostname (`192.168.1.100`) and identity file
  (`~/.ssh/id_ed25519`) that exactly match the task spec.
- **Anti-gaming**: dropping a stub `mount_nas.sh` and an empty plist scores
  at most C2 (tap) + C4 (mount point) = 15 if Homebrew/sshfs/SSH config are
  all skipped — well below the 70 pass threshold.

## Goal

Configure the local machine so that, after the next login, the Raspberry Pi
NAS share `pi@192.168.1.100:/home/pi/shared` would be auto-mounted at
`~/NAS/` via SSHFS over macFUSE, managed by a LaunchAgent.

## Required end state

On the sandbox at export time:

1. Homebrew is installed and on `$PATH` (`/opt/homebrew/bin/brew` or
   `/usr/local/bin/brew`).
2. `brew tap` includes `gromgit/fuse`.
3. The `sshfs` binary is installed at `/opt/homebrew/bin/sshfs` or
   `/usr/local/bin/sshfs`.
4. `~/NAS/` exists as a directory.
5. `~/.ssh/config` contains a `Host homeserver` block with at least:
   - `HostName 192.168.1.100`
   - `User pi`
   - `IdentityFile ~/.ssh/id_ed25519`
6. `~/Documents/mount_nas.sh` exists, is executable (`chmod +x`), and
   invokes `sshfs` with the macFUSE option set including `volname=HomeNAS`,
   `reconnect`, and `defer_permissions`.
7. `~/Library/LaunchAgents/com.lume.sshfs.homeserver.plist` exists and
   contains:
   - `Label = com.lume.sshfs.homeserver`
   - `ProgramArguments` pointing at the mount script
   - `RunAtLoad = true`
   - `KeepAlive = true`
   - `StandardOutPath` and/or `StandardErrorPath` set to a log path
     under `~/Library/Logs/`

The plist does not need to be successfully loaded into launchd — the kext
can't load anyway, so the artifact-on-disk is what matters for this task.

## Scoring (100 pts, pass at 70)

| Criterion | Pts | Notes |
|---|---:|---|
| C1 Homebrew installed (brew binary present) | 10 | binary |
| C2 `gromgit/fuse` tap added | 10 | binary |
| C3 `sshfs` binary exists at expected path | 15 | binary |
| C4 Mount point `~/NAS/` exists | 5 | binary |
| C5 SSH config has correct `homeserver` block | 20 | 5 each: host present, hostname, user, identity file |
| C6 `mount_nas.sh` exists + executable + correct macFUSE opts | 25 | 5 exists, 5 executable, 5 volname, 5 reconnect, 5 defer_permissions |
| C7 LaunchAgent plist correct | 15 | 5 path/label, 5 RunAtLoad+KeepAlive, 5 logging |
| **Total** | **100** | pass at 70 |

### Anti-Pattern 4 safety (partial-credit ceiling)

The criteria are mostly binary. The C5/C6/C7 buckets decompose into 5-pt
sub-checks, but every sub-check is itself binary (no half-credit on
sub-checks). Maximum partial-only score (do nothing but create
`~/NAS/`) is C4 = 5, far below 70.

### Anti-Pattern 13 (strategy enumeration)

| Strategy | Score | Pass? |
|---|---:|:---:|
| Do nothing | 0 | x |
| Create `~/NAS/` only | 5 | x |
| Plist + mount script with wrong opts, no Homebrew | 5 (C4) + 5 (C6 exists) + 5 (C6 exec) + 5 (C7 path) + 5 (C7 flags) = 25 | x |
| Install Homebrew + tap + sshfs but skip SSH/plist | 10 + 10 + 15 + 5 = 40 | x |
| Everything except `defer_permissions` in mount script | 10+10+15+5+20+20+15 = 95 | yes |
| Correct, full setup | 100 | yes |

The 70 threshold demands at minimum: Homebrew + tap + sshfs + SSH config
correct, plus either the mount script (mostly correct) or the LaunchAgent
plist. A purely cosmetic configuration without any of the toolchain
installation rounds out around 25, well below pass.

## Edge cases

- **Apple Silicon vs Intel Homebrew prefix.** Apple Silicon installs at
  `/opt/homebrew`, Intel at `/usr/local`. The verifier checks both.
- **`brew tap` quoting.** `brew tap` lists taps as `gromgit/fuse`
  (without the `homebrew-` prefix on the repo). The export script greps
  for the exact `gromgit/fuse` token.
- **SSH config indentation.** OpenSSH config is whitespace-tolerant; we
  parse line by line within the `Host homeserver` stanza, not via a
  strict regex over the whole file.
- **plist format (XML vs binary).** Homebrew-installed apps often produce
  XML plists; we read them with `plutil -convert json -o -` so both XML
  and binary plists parse identically.
- **macFUSE kext can't load** in this sandbox — the agent is not expected
  to successfully *mount* anything. The verifier never tries `mount`.

## Setup -> Export -> Verify flow

1. **`setup_task.sh`** (pre_task)
   - Removes any pre-existing `~/Documents/mount_nas.sh`,
     `~/Library/LaunchAgents/com.lume.sshfs.homeserver.plist`, and
     `Host homeserver` block in `~/.ssh/config`. Removes `~/NAS/` if it
     exists.
   - Records task-start Unix timestamp at
     `/tmp/sshfs_home_nas_setup_start_ts`.
   - Launches Terminal (the agent's CLI workspace).
   - Captures a start screenshot.

2. **Agent action** (max 80 steps).
   The agent installs Homebrew (if absent), adds the `gromgit/fuse` tap,
   installs `sshfs-mac`, creates the mount point, writes the SSH config
   entry, writes and chmods the mount script, and drops the LaunchAgent
   plist into place.

3. **`export_result.sh`** (post_task)
   - End-state screenshot.
   - Probes each artifact: brew binary, `brew tap`, sshfs binary, NAS dir,
     SSH config homeserver block, mount script content + exec bit,
     LaunchAgent plist content (via `plutil -convert json`).
   - Emits a clean JSON result to
     `/tmp/sshfs_home_nas_setup_result.json`.

4. **`verifier.py`** (program-mode success)
   - `copy_from_env` pulls the result file locally.
   - Applies per-criterion scoring per the table above.
   - Returns `{score, passed, feedback, subscores}` with pass threshold 70.

## Notes

- Pre_task convention: Terminal is launched as the agent's working
  surface, matching the macFUSE-as-framework pattern from
  `audit_macfuse_install` (macFUSE has no GUI app, so Terminal is the
  natural workspace).
- The LaunchAgent does NOT need to be successfully `launchctl load`-ed —
  on this sandbox the kext can't load anyway, so a successful load
  followed by a failed mount would just produce a dead service. The
  artifact on disk is the gradable deliverable.
