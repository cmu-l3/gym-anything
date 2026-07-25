# `audit_macfuse_install` — macFUSE Installation Compliance Audit

Environment: `macfuse_env@0.1` (macOS, use.computer dev fleet)

## Domain context

macFUSE (formerly OSXFUSE) is the FUSE filesystem framework for macOS — it
allows third-party developers to ship custom filesystems (sshfs, ntfs-3g,
git-fuse, etc.) without writing their own kernel extensions. macFUSE itself
provides the kext-userspace bridge.

A real macOS endpoint security audit will include macFUSE specifically because:
- it ships kernel extensions, which are a privileged-code-execution surface
- it installs a preference pane in System Settings
- it installs userspace shared libraries that other filesystems link against
- enterprises need to inventory what versions are deployed across the fleet

The agent's job is the **audit phase** of that workflow: gather authoritative
facts about the installed macFUSE, structured as a JSON report. This is the
artifact a security engineer would attach to a compliance ticket or feed to
an asset inventory.

## Why this is hard (but not too hard)

Difficulty rating: `medium`.

- **Discovery burden**: low. The description spells out which fields are
  needed and what each field means. The agent does NOT have to figure out
  what to audit.
- **Path burden**: medium. The agent has to choose the right command for
  each field — `defaults read` for the Info.plist, `pkgutil --pkg-info` for
  package metadata, `kextstat` for kernel load state, `ls` and counting for
  directory/file counts. None of these are obvious from the description.
- **JSON construction**: low–medium. The agent has to assemble a valid JSON
  object with the exact key names and correct types (string / int / bool).
- **Anti-gaming**: the two `*_install_time` fields are unfakable Unix epochs
  specific to this sandbox's install timestamp. Without probing pkgutil on
  the live machine, the agent can score at most 60/100 — below the 70 pass
  threshold (see strategy enumeration below).

## Ground-truth values (live install in dev sandbox, 2026-05)

| Field | Source | Expected value |
|---|---|---|
| `bundle_version` | `defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleShortVersionString` | `"4.10.2"` |
| `bundle_identifier` | `defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleIdentifier` | `"io.macfuse.filesystems.fs.macfuse"` |
| `pkg_core_version` | `pkgutil --pkg-info io.macfuse.installer.components.core` (line `version:`) | `"4.10.2"` |
| `core_pkg_install_time` | same source, line `install-time:` | sandbox-specific Unix epoch |
| `prefpane_pkg_install_time` | `pkgutil --pkg-info io.macfuse.installer.components.preferencepane` | sandbox-specific Unix epoch |
| `kext_currently_loaded` | `kextstat | grep -i fuse` returns empty? | `false` (kext can't load — SIP + kext consent) |
| `mount_helper_path` | known from install layout | `"/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse"` |
| `supported_macos_versions_count` | `ls /Library/Filesystems/macfuse.fs/Contents/Extensions/ | wc -l` | `13` (10.9, 10.10, ..., 10.16, 11, 12, 13, 14, 15) |
| `libfuse_dylib_count` | `ls /usr/local/lib/libfuse*.dylib | wc -l` | `4` (libfuse.2.dylib, libfuse.dylib, libfuse3.4.dylib, libfuse3.dylib) |
| `prefpane_installed` | `test -d /Library/PreferencePanes/macFUSE.prefPane` | `true` |

## Scoring (100 pts, pass at 70)

| Criterion | Pts | Partial | Notes |
|---|---:|---:|---|
| C1 Report file (exists + fresh + valid JSON) | 10 | 5 stale / 2 invalid | gate-style |
| C2 `bundle_version` exact match | 5 | — | binary |
| C3 `bundle_identifier` exact match | 5 | — | binary |
| C4 `pkg_core_version` exact match | 5 | — | binary |
| C5 `core_pkg_install_time` within ±2s | 20 | — | **unfakable** |
| C6 `prefpane_pkg_install_time` within ±2s | 20 | — | **unfakable** |
| C7 `kext_currently_loaded` exact match | 5 | — | binary |
| C8 `mount_helper_path` exact match | 5 | — | binary |
| C9 `supported_macos_versions_count` exact match | 10 | — | binary |
| C10 `libfuse_dylib_count` exact match | 5 | — | binary |
| C11 `prefpane_installed` exact match | 10 | — | binary |
| **Total** | **100** | | pass at 70 |

Anti-Pattern 4 safety: sum of all partial-only credit = 5 (only C1 has
partial). 5 ≪ 70 pass threshold ✓

## Strategy enumeration (Anti-Pattern 13 check)

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | C10 | C11 | Score | Pass? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | ✗ |
| Wrong target (strict gate) | gate | gate | gate | gate | gate | gate | gate | gate | gate | gate | gate | **0** | ✗ |
| Mass-guess (no probing of live install) | 10 | 5 | 5 | 5 | 0 | 0 | 5 | 5 | 10 | 5 | 10 | **60** | ✗ |
| Partial (probed bundle but not pkgutil, got kext wrong) | 10 | 5 | 5 | 5 | 20 | 0 | 0 | 5 | 0 | 5 | 0 | **55** | ✗ |
| Correct behavior (probed everything) | 10 | 5 | 5 | 5 | 20 | 20 | 5 | 5 | 10 | 5 | 10 | **100** | ✓ |

**The mass-guess row is the key adversarial check**: an agent that knows
macFUSE 4.10.2 documentation perfectly can populate 8 of the 11 fields
correctly without ever opening Terminal. But the two `*_install_time` fields
(40 pts total) are sandbox-specific — they can only be obtained by running
`pkgutil --pkg-info` on the live machine. 60/100 is strictly below the 70
pass threshold, so the task cannot be passed without actually probing the
live install.

## Wrong-target rejection (Pattern 2)

Strict gate: if the report file exists and is valid JSON but contains zero
mention of "macfuse" or "/Library/Filesystems" anywhere in its serialized
form, the verifier returns score=0 regardless of file-existence credit. This
fires if the agent audits a completely different framework (e.g. an NTFS
driver instead).

## Setup → Export → Verify flow

1. **`setup_task.sh`** (pre_task)
   - Deletes any pre-existing report at `~/Documents/macfuse_audit_report.json`
   - Records task-start Unix timestamp at `/tmp/macfuse_audit_task_start_timestamp`
   - Launches Terminal so the agent has a CLI workspace
   - Does NOT echo any of the expected values

2. **Agent action** (max 60 steps)
   - Open Terminal (already launched), type commands to gather each field
   - Build a JSON object with the exact keys listed in the task description
   - Save to `/Users/lume/Documents/macfuse_audit_report.json` via heredoc / editor

3. **`export_result.sh`** (post_task)
   - Re-gathers all ground-truth values from the system at export time
   - Parses the agent's report file, extracts per-field values, detects
     "mentions_macfuse" for the wrong-target gate
   - Writes both ground-truth and agent values to
     `/tmp/audit_macfuse_install_result.json`

4. **`verifier.py`** (program-mode success)
   - `copy_from_env` pulls the result file to a local temp path
   - Compares agent fields against ground truth, applies per-field scoring
   - Returns `{score, passed, feedback, subscores}`

## Notes

- Pre_task convention: `pre_task` launches Terminal (the natural CLI surface
  for a sysadmin audit). This mirrors `12_macos_environments.md`'s
  "pre_task launches the app" rule — for macFUSE the "app" is Terminal,
  since macFUSE itself is a kernel framework with no UI window.
- The `kext_currently_loaded = false` expected value is itself a notable
  signal: macFUSE installed-on-disk ≠ macFUSE loaded-in-kernel on this
  sandbox (SIP enabled + kext user consent gate). An agent that assumes
  install implies load will silently lose 5 points on C7.
