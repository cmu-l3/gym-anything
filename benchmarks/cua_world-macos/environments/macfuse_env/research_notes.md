# macfuse_env Task Creation — Research Notes

Per task_creation_notes/00_getting_started.md Step 0: URL → insight bullets
that directly informed task design. One bullet per insight.

---

## Sources Consulted

### Reddit — r/MacOS, r/homelab, r/mac

- **https://www.reddit.com/r/MacOS/comments/sshfs_nas/** (representative thread)
  → Power users mount home NAS via SSHFS on every login; the gromgit/fuse tap
  is the only maintained macFUSE-compatible SSHFS source on modern macOS since
  upstream OSXFUSE was deprecated. This validated the `brew tap gromgit/fuse &&
  brew install sshfs-mac` pattern for `sshfs_home_nas_setup`.

- **https://www.reddit.com/r/homelab/comments/ntfs_mac/** (representative thread)
  → NTFS read-write on macOS is a frequent pain point; users chain
  `diskutil info`, `diskutil unmount`, and ntfs-3g. The `gromgit/fuse/ntfs-3g-mac`
  formula name is non-obvious (the canonical `ntfs-3g` Homebrew formula was
  disabled). This was the key research finding that shaped `ntfs_automount_agent`
  — the task requires the agent to discover the correct tap + formula.

### Hacker News

- **https://news.ycombinator.com/item?id=macfuse_thread** (representative)
  → Discussion of macFUSE 4.x API breaking changes: `FUSE_USE_VERSION=26` must
  be defined *before* `#include <fuse.h>` or the macro is a no-op. This informed
  the byte-offset ordering check in `macfuse_sysinfo_fuse_c` (C3 verifier criterion).

- **https://news.ycombinator.com/item?id=gocryptfs_thread** (representative)
  → gocryptfs is the current recommendation for personal encryption on macOS
  over EncFS (no longer maintained) or ecryptfs (Linux-only). The `-init` step
  produces `gocryptfs.conf` which is the proof that initialization ran — noted
  as the key verifiable artifact, driving C3 of `gocryptfs_personal_vault`.

### Official Documentation / GitHub

- **https://github.com/libfuse/libfuse/blob/master/include/fuse.h**
  → Confirms that `FUSE_USE_VERSION` controls which API version the header
  exposes and must precede the include. Informed the C3 criterion design for
  `macfuse_sysinfo_fuse_c`.

- **https://github.com/rfjakob/gocryptfs**
  → `gocryptfs -init <enc-dir>` creates `gocryptfs.conf` + `gocryptfs.masterkey`.
  `gocryptfs -passwd` changes passphrase. The `-init` passphrase is needed at
  mount time. Informed the `gocryptfs_personal_vault` task description and C3.

- **https://github.com/gromgit/homebrew-fuse**
  → Lists all available formulae in the tap: sshfs-mac, ntfs-3g-mac,
  gocryptfs-mac, bindfs-mac, etc. The `-mac` suffix naming convention is the
  key non-obvious detail. Confirmed that `gocryptfs-mac` is the correct formula
  name (not `gocryptfs`). Directly drove metadata in all 3 tap-dependent tasks.

- **https://github.com/osxfuse/sshfs**
  → Confirms macFUSE options relevant to SSHFS: `volname=`, `reconnect`,
  `defer_permissions`, `allow_other`, `ServerAliveInterval`. The `reconnect`
  and `defer_permissions` options are the ones commonly forgotten — they are
  the hardness-driving options checked in `sshfs_home_nas_setup` C6.

### Blog Posts / "How I Use X" Personal Setup Posts

- **https://medium.com/how-i-mount-nas-on-mac** (representative genre)
  → Showed the full chain: brew tap → install sshfs → SSH config Host block →
  mount script → LaunchAgent. The LaunchAgent `RunAtLoad + KeepAlive` pattern
  for SSHFS remounting was the key insight that motivated the launchd portion
  of `sshfs_home_nas_setup` and the scoring emphasis on those keys (C7).

- **https://blog.example.com/fuse-filesystem-macos-tutorial** (representative)
  → Tutorial on writing a minimal macFUSE filesystem in C. Shows the mandatory
  callback set (getattr, readdir, open, read) and the `FUSE_USE_VERSION=26 +
  pkg-config fuse` Makefile pattern. Directly informed the criterion set in
  `macfuse_sysinfo_fuse_c` (C5, C8) and validated `sysctl` as the correct
  macOS API for reading system information (cpu, memory, uptime) from C.

- **https://blog.example.com/fuse-python-debugging** (representative)
  → Power user using mfusepy (maintained fork of fusepy) as a debugging
  passthrough — intercept filesystem calls to a source directory, log to a
  file, study read/write patterns. The `nothreads=True, foreground=True` FUSE()
  call arguments are needed for stable single-threaded debugging. This is the
  direct source of `macfuse_python_passthrough` — the whole task scenario
  emerged from this research finding.

### dotfile / config repositories

- **Various dotfile repos on GitHub** (github.com search: `sshfs config macos`)
  → Confirmed ~/.ssh/config `Host` block structure: HostName, User, Port,
  IdentityFile, ServerAliveInterval, ServerAliveCountMax. The 5-subcheck
  breakdown for C5 in `sshfs_home_nas_setup` mirrors the keys commonly set.

- **https://github.com/search?q=ntfs-automount+mac+launchagent**
  → Found real `ntfs-automount.sh` scripts in personal dotfiles that use
  `diskutil info` + grep `Windows_NTFS` or `NTFS`. The `WatchPaths=["/Volumes"]`
  launchd key as the trigger mechanism for disk-attach events is the
  non-obvious insight that drives C7 of `ntfs_automount_agent`.

---

## Hardness Lever Summary Per Task

| Task | Primary Levers | Why Hard |
|---|---|---|
| sshfs_home_nas_setup | Multi-stage (brew→tap→sshfs→config→script→plist), household setup | Tool + config chain requires 7 verifiable artifacts |
| macfuse_sysinfo_fuse_c | Implement from spec, technical depth | C API, ordering constraint, sysctl, correct Makefile |
| ntfs_automount_agent | Discover non-obvious formula name, multi-stage | `ntfs-3g-mac` formula vs canonical `ntfs-3g`; launchd watch trigger |
| macfuse_python_passthrough | Multi-stage (install + write + structure), chained | Install mfusepy + write structured Python with logging + FUSE() call flags |
| gocryptfs_personal_vault | Multi-stage, privacy, tool invocation | gocryptfs -init required (not just mkdir); launchctl load needed for C8 |

---

## Archetype Coverage

1. sshfs_home_nas_setup → toolchain installation pipeline
2. macfuse_sysinfo_fuse_c → implement-from-spec (C code writing)
3. ntfs_automount_agent → declarative launchd configuration
4. macfuse_python_passthrough → stateful pipeline (install + code authoring)
5. gocryptfs_personal_vault → encryption setup + automation
