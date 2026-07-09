# `gocryptfs_personal_vault` — Encrypted Personal Vault with Auto-Mount LaunchAgent

Environment: `macfuse_env@0.1` (macOS, use.computer dev fleet)

## Domain context

A privacy-conscious individual wants to keep their personal journal, medical
records, and financial notes encrypted on disk. The plaintext should only be
accessible when they explicitly mount the vault; the encrypted side should be
safe to back up to iCloud Drive or Time Machine without leaking content.

[gocryptfs](https://nuetzlich.net/gocryptfs/) is the canonical macOS-friendly
solution: a transparent filesystem-encryption layer that uses macFUSE to
present a plaintext mountpoint while persisting AES-GCM ciphertext on disk.
The macOS port lives in the third-party `gromgit/fuse` Homebrew tap because
the upstream Homebrew core dropped FUSE-dependent packages.

The agent's job spans an entire **setup-and-automate** workflow:

1. Install Homebrew (if missing).
2. Tap `gromgit/fuse` and install `gocryptfs-mac`.
3. Initialize an encrypted vault at `~/Documents/vault.enc/` with a known
   passphrase using non-interactive `echo | gocryptfs -init -nosyslog`.
4. Prepare the plaintext mountpoint at `~/Documents/vault.plain/`.
5. Write a mount-helper script (`mount_vault.sh`), an unmount-helper
   (`umount_vault.sh`), and a LaunchAgent plist
   (`~/Library/LaunchAgents/com.lume.gocryptfs.vault.plist`) that runs the
   mount helper at login.
6. Load the LaunchAgent so it is registered with `launchctl`.

This mirrors a realistic personal-Mac hardening recipe — install a FUSE
package, initialize an encrypted directory, wire it into the user's login
session via launchd. None of it requires a live FUSE mount (the macFUSE kext
cannot load in this sandbox; see `specific_env_notes/macfuse_macos/notes.md`),
so every verification step inspects on-disk artifacts rather than driving a
mounted filesystem.

## Why this is hard

Difficulty rating: `very_hard`.

- **Many interdependent subtasks**. The agent must install a Homebrew tap,
  install a package from it, initialize a filesystem container with a
  passphrase, write two bash scripts with correct permission bits, write a
  syntactically valid plist with five required keys (Label,
  ProgramArguments, RunAtLoad, StandardOutPath, StandardErrorPath), and
  register the plist with launchd. Any one stage skipped fails its
  criterion.
- **Format-sensitive output**. The plist must parse with `plutil -convert
  json`. `RunAtLoad` must be a boolean true. `Label` must match the file's
  bundle identifier. The mount script must contain a literal `gocryptfs`
  invocation, not just a comment about it.
- **Non-obvious idioms**. The `gocryptfs -init` command is interactive by
  default; the agent must know (or discover) the `echo | gocryptfs -init
  -nosyslog` pattern. The Homebrew tap `gromgit/fuse` is third-party and
  not discoverable from generic `brew search`. The LaunchAgent path
  `~/Library/LaunchAgents/` and the `launchctl load` registration step are
  macOS-specific.
- **Output artifact integrity**. The verifier doesn't just check file
  existence — it inspects the plist keys, the executable bits on the
  scripts, the presence of `gocryptfs.conf` inside the initialized
  encrypted directory (proof that `gocryptfs -init` actually ran rather
  than the directory just being `mkdir`'d), and the `launchctl list`
  registration.
- **Description is intentionally high-level**. Per the `very_hard` task
  contract, the task description does not spell out the exact commands the
  agent must run — it states the goal and the file paths, leaving the
  invocation details (which tap to add, how to do non-interactive init,
  what permission bit to set) to the agent.

## Ground-truth artifacts the agent must produce

| Artifact | What it must look like |
|---|---|
| Homebrew binary | `brew` resolvable on PATH (`/opt/homebrew/bin/brew` on Apple Silicon, `/usr/local/bin/brew` on Intel). |
| gocryptfs binary | Executable named `gocryptfs` on PATH or under `/opt/homebrew/bin/`, `/usr/local/bin/`. |
| `~/Documents/vault.enc/` | Directory containing `gocryptfs.conf` (a JSON file produced by `gocryptfs -init`) plus the per-directory IV file `gocryptfs.diriv`. |
| `~/Documents/vault.plain/` | Empty directory (mount point). |
| `~/Documents/mount_vault.sh` | Executable bash script that calls `gocryptfs` against `vault.enc` and `vault.plain`. |
| `~/Documents/umount_vault.sh` | Executable bash script that calls `umount` (or `diskutil unmount`) on `vault.plain`. |
| `~/Library/LaunchAgents/com.lume.gocryptfs.vault.plist` | Plist with `Label=com.lume.gocryptfs.vault`, `RunAtLoad=true`, `ProgramArguments` invoking the mount script, and `StandardOutPath` / `StandardErrorPath` pointing into `~/Library/Logs/`. |
| `launchctl list` | Includes `com.lume.gocryptfs.vault` (proves the agent ran `launchctl load`). |

## Scoring (100 pts, pass at 70)

| Criterion | Pts | Description |
|---|---:|---|
| C1 Homebrew installed | 5 | `brew` resolves on PATH. |
| C2 gocryptfs binary exists | 15 | `gocryptfs` executable found under one of the Homebrew bin directories. |
| C3 vault.enc initialized | 20 | `~/Documents/vault.enc/` exists AND contains `gocryptfs.conf` (the gocryptfs config file is the indicator of a real `-init` rather than a `mkdir`). |
| C4 vault.plain mountpoint | 5 | `~/Documents/vault.plain/` exists as a directory. |
| C5 mount_vault.sh complete | 20 | File exists, executable bit set, contains the substring `gocryptfs`. |
| C6 umount_vault.sh complete | 5 | File exists, executable bit set, contains `umount` or `diskutil unmount`. |
| C7 LaunchAgent plist correct | 20 | Plist parses; `Label==com.lume.gocryptfs.vault`; `RunAtLoad==true`; `StandardOutPath` / `StandardErrorPath` both set (5 pts each for parse+label, RunAtLoad, log paths, ProgramArguments referencing the mount script). |
| C8 LaunchAgent loaded | 10 | `launchctl list` contains `com.lume.gocryptfs.vault`. |
| **Total** | **100** | pass at 70 |

### Anti-Pattern 4 safety check (partial-without-work)

The smallest "do almost nothing" path is C4 (5 pts, just an `mkdir
~/Documents/vault.plain`) + C6 (5 pts, a trivial three-line umount script).
That sums to **10 / 100**, well below the 70 pass threshold. The agent
cannot pass without doing the heavy lifting (install Homebrew + gocryptfs,
run `gocryptfs -init`, write the LaunchAgent plist, register with launchd).

### Anti-Pattern 13 strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | Score | Pass? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | ✗ |
| Trivial mkdir + stub umount | 0 | 0 | 0 | 5 | 0 | 5 | 0 | 0 | **10** | ✗ |
| Brew + tap install only | 5 | 15 | 0 | 0 | 0 | 0 | 0 | 0 | **20** | ✗ |
| Brew + init + dirs (no scripts/plist) | 5 | 15 | 20 | 5 | 0 | 0 | 0 | 0 | **45** | ✗ |
| Brew + init + scripts (no LaunchAgent) | 5 | 15 | 20 | 5 | 20 | 5 | 0 | 0 | **70** | ✓ (just at threshold) |
| Brew + init + plist but forgot to `launchctl load` | 5 | 15 | 20 | 5 | 20 | 5 | 20 | 0 | **90** | ✓ |
| Full correct | 5 | 15 | 20 | 5 | 20 | 5 | 20 | 10 | **100** | ✓ |

The "no LaunchAgent" path just clears 70 — an agent that does the
install/init/script work but skips the launchd integration scrapes by. This
is intentional: the LaunchAgent is the polish step. The agent who builds the
plist but forgets `launchctl load` still scores 90, which is fair — they did
99 % of the work.

### Wrong-target rejection

There is no plausible "wrong target" the agent could plausibly mistake for
this. The verifier doesn't enforce a strict wrong-target gate because every
criterion is path-keyed (`~/Documents/vault.enc/gocryptfs.conf`,
`com.lume.gocryptfs.vault`, etc.) — a wrong target produces 0 across the
board automatically.

## Hardness levers

- **Multi-stakeholder framing**: a privacy-conscious user who wants
  encrypted-at-rest storage that can still sync to iCloud Drive. Real
  occupation, real motivation.
- **Multi-stage execution**: 8 sequential subtasks with hard dependencies
  (no init without install; no LaunchAgent without scripts).
- **Output artifact integrity**: the LaunchAgent plist must parse and have
  specific key/value shapes — not just exist.
- **Description-vs-spec gap**: the description states the goal and required
  paths but not the exact commands, forcing the agent to know or discover
  the gocryptfs-mac tap, the non-interactive init flag, the plist XML
  schema, and the `launchctl load` step.

## Setup → Export → Verify flow

1. **`setup_task.sh`** (pre_task)
   - Wipes any prior `~/Documents/vault.enc`, `~/Documents/vault.plain`,
     `~/Documents/mount_vault.sh`, `~/Documents/umount_vault.sh`.
   - If the LaunchAgent plist exists, `launchctl unload` it (best-effort)
     and remove the plist.
   - Records task-start Unix timestamp at
     `/tmp/gocryptfs_personal_vault_task_start_timestamp`.
   - Launches Terminal so the agent has a CLI workspace, polls
     `lsappinfo` for window registration (per `12_macos_environments.md`).
   - Captures a start-state screenshot for the trajectory archive.

2. **Agent action** (max 80 steps, 900 s)
   - Install Homebrew if not already present (the base-macos image ships
     it, but the PATH must be sourced).
   - `brew tap gromgit/fuse` and `brew install gromgit/fuse/gocryptfs-mac`.
   - `echo "PersonalVault2024!" | gocryptfs -init -nosyslog
     ~/Documents/vault.enc`.
   - `mkdir -p ~/Documents/vault.plain`.
   - Write `mount_vault.sh`, `umount_vault.sh` (both `chmod +x`).
   - Write `~/Library/LaunchAgents/com.lume.gocryptfs.vault.plist`.
   - `launchctl load
     ~/Library/LaunchAgents/com.lume.gocryptfs.vault.plist`.

3. **`export_result.sh`** (post_task)
   - Probes every artifact and writes
     `/tmp/gocryptfs_personal_vault_result.json` with structured fields the
     verifier consumes via `copy_from_env`.

4. **`verifier.py`** (program-mode success)
   - `copy_from_env(/tmp/gocryptfs_personal_vault_result.json, local_tmp)`
   - Scores per criterion, returns `{score, passed, feedback, subscores}`.

## Notes

- Per `12_macos_environments.md`'s pre_task convention, the pre_task hook
  launches **Terminal** (the natural CLI surface for an install + script
  authoring + launchctl task). macFUSE has no GUI app to focus.
- The vault passphrase is hardcoded to `PersonalVault2024!` so the verifier
  doesn't need to know the agent's password; both the init and the mount
  script use the same literal value.
- The plist's `KeepAlive` must NOT be `true` because gocryptfs runs in
  foreground and we don't want launchd to respawn it on exit. The verifier
  does not penalize a missing `KeepAlive` (the default is false), but does
  not reward `KeepAlive=true` either.
- The macFUSE kext is unloadable in the use.computer sandbox (see
  `specific_env_notes/macfuse_macos/notes.md`). Mount attempts will fail —
  the LaunchAgent will exit non-zero on first login — but the verifier
  doesn't care; it scores the *setup artifacts*, not the runtime behavior.
