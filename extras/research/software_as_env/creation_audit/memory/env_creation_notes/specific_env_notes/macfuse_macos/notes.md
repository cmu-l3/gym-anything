# macFUSE on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/macfuse_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1)

> **See also:** `12_macos_environments.md` for the general macOS env guide;
> `specific_env_notes/google_earth_macos/notes.md` and `specific_env_notes/safari/notes.md`
> for two other built-out macOS envs.

---

## Install Path (working as of 2026-05)

**Pinned URL that works**:
`https://github.com/macfuse/macfuse/releases/download/macfuse-4.10.2/macfuse-4.10.2.dmg`
(6.3 MB DMG, single .pkg inside.)

The macFUSE 4.x series uses a **kext** (via the legacy KEXT-bridge runtime).
macFUSE 5.x switches to a System Extension, but neither path can actually
*load* in the sandbox (see below). The on-disk bundle install works
identically; for tasks that audit *what is installed*, 4.x is fine.

**Shape of the DMG**: drag-and-drop is NOT supported — macFUSE ships a single
`.pkg` installer, named `Install macFUSE.pkg` inside `Extras/` on the DMG.
Use Pattern B from `12_macos_environments.md`:

```bash
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" \
              | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)
PKG=$(find "$MOUNT_POINT" -maxdepth 3 -name "*.pkg" -type f | head -1)
sudo installer -pkg "$PKG" -target /
hdiutil detach "$MOUNT_POINT" -force
```

**Total install time** on a fresh sandbox: ~5s (6 MB download + ~2s installer
+ ~1s misc). Faster than google_earth_env (~50s) because the DMG is small
and no Rosetta is needed (macFUSE is universal binary).

**Rosetta**: not required. macFUSE 4.10.2 is a universal binary.

---

## Kext / System Extension Cannot Load in the Sandbox

The base-macos sandbox has SIP enabled (`csrutil status` →
`System Integrity Protection status: enabled`) AND kext user consent
enabled (`spctl kext-consent status` → `Kernel Extension User Consent:
ENABLED`).

Result: macFUSE installs cleanly to `/Library/Filesystems/macfuse.fs/` but
the kernel extension **never loads**:
- `sudo /Library/Filesystems/macfuse.fs/Contents/Resources/load_macfuse`
  succeeds silently (rc=0) but `kextstat | grep -i fuse` returns nothing.
- `systemextensionsctl list` shows `0 extension(s)`.
- On Apple Silicon, kext load requires Reduced Security mode set via
  Recovery Mode — the sandbox doesn't expose Recovery boot.

**Practical implication for task design**: do NOT design tasks that require
live FUSE mounts (sshfs, ntfs-3g, etc. that depend on the kext). Tasks
should focus on **inspecting / auditing** the installed-on-disk artifacts —
Info.plist values, pkgutil receipts, file inventories, prefpane presence.

The current `audit_macfuse_install` task explicitly codifies
`kext_currently_loaded: false` as a verifiable audit finding. This turns
the limitation into a feature: a real sysadmin audit must capture whether
the kext is actually loaded vs. just installed.

---

## Verifier-Friendly Footprint

What macFUSE leaves on disk after `installer -pkg`:

| Path | What's in it |
|---|---|
| `/Library/Filesystems/macfuse.fs/` | The bundle (Info.plist, Resources, 13 kext variants under Extensions/) |
| `/Library/Filesystems/macfuse.fs/Contents/Info.plist` | CFBundleShortVersionString, CFBundleIdentifier (`io.macfuse.filesystems.fs.macfuse`) |
| `/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse` | setuid mount helper binary (188 KB) |
| `/Library/Filesystems/macfuse.fs/Contents/Resources/load_macfuse` | setuid kext loader (~170 KB) |
| `/Library/Filesystems/macfuse.fs/Contents/Extensions/{10.9,...,15}/` | 13 macOS-version-specific kext variants |
| `/Library/PreferencePanes/macFUSE.prefPane/` | System Settings panel for macFUSE preferences |
| `/usr/local/lib/libfuse.2.dylib` + `libfuse.dylib` symlink | libfuse v2 runtime |
| `/usr/local/lib/libfuse3.4.dylib` + `libfuse3.dylib` symlink | libfuse v3 runtime |
| `/usr/local/lib/libfuse.la` | libtool archive metadata |
| `/usr/local/include/fuse/*.h` | C/C++ headers (fuse.h, fuse_common.h, fuse_lowlevel.h, fuse_opt.h, …) |

Two pkgutil components register:
- `io.macfuse.installer.components.core` — the bundle + libs + headers (149 files)
- `io.macfuse.installer.components.preferencepane` — the System Settings panel

Both report `version: 4.10.2` and an `install-time:` Unix epoch. The
install-time is **per-sandbox** (set when the pkg ran) and forms the basis
of the audit task's anti-gaming check (see next section).

---

## Anti-Gaming Pattern: Per-Sandbox `pkgutil install-time`

The `audit_macfuse_install` task uses an **unfakable per-sandbox value** to
prevent agents from passing without ever opening Terminal: `pkgutil --pkg-info`
reports an `install-time` Unix epoch that is set at .pkg install time and
is therefore unique to each sandbox provision.

The verifier scores `core_pkg_install_time` and `prefpane_pkg_install_time`
(20 pts each, ±2s tolerance) against ground truth captured at export-time by
`export_result.sh`. An agent that knows all public macFUSE facts (version,
bundle identifier, mount helper path, the 13 supported macOS variants, the
4 libfuse files, prefpane presence, etc.) but never runs `pkgutil --pkg-info`
can score at most 60/100 — strictly below the 70 pass threshold.

This is a general pattern worth replicating in any audit-style task: find
a per-sandbox value that the agent cannot predict from documentation
(install-time, sandbox UUID, NSDate-recorded timestamps in app config files,
etc.) and weight it heavily enough that the task cannot be passed by
guessing alone.

See `task_creation_notes/14_task_design_antipatterns.md#Anti-Pattern-13` for
the broader strategy enumeration framework that motivated this design.

---

## Known Gotchas

### `kextstat` + `grep -ciq` quirk
`kextstat 2>/dev/null | grep -ciq fuse && echo true || echo false` will
return `false` cleanly. But running `kextstat` alone on macOS 15.4.1 also
spawns `kmutil showloaded` which prints to stderr — *not* a problem when
piped through `grep`, but if you `cat /dev/null`-suppress stderr too
aggressively you'll lose useful debugging info on the unrelated noise.
Just `2>/dev/null` works.

### `keyboard.press("Return")` does NOT submit Terminal commands
Confirmed during the `audit_macfuse_install` interactive pilot (2026-05-18,
see `evidence_docs/audit_macfuse_install/interactive_pilot/02_after_probe_command.png`
vs `02b_after_enter.png`). Typing a command into Terminal then sending
`key Return` leaves the command unexecuted on the prompt line. Sending
`key Enter` instead immediately executes.

This **reinforces** the existing finding from `12_macos_environments.md`
("Keyboard `Enter` ≠ `Return` in Safari (and probably elsewhere)"). Update:
"and probably elsewhere" now confirmed for Terminal too. The general rule
holds — use `Enter` for command/form submit; use `Return` only for newline
insertion in text editors.

### Multi-line heredoc typing works (1300+ chars, 14 newlines)
The interactive pilot typed a 1321-char Python heredoc with 14 embedded
newlines via a single `keyboard.type()` call. zsh accepted every newline as
a `heredoc>` continuation. The final `PYEOF\n` + `key Enter` correctly
terminated the heredoc and executed the Python block. Consistent with the
existing `notion_session` finding (1053 chars / 21 newlines) but a bit
longer.

### Python 3.12+ `SyntaxWarning: invalid escape sequence '\.'`
Python 3.12 raises a `SyntaxWarning` (not an error) for `'^libfuse.*\.dylib$'`
because `\.` is not a valid string escape. The script still runs and produces
correct output. Safe to ignore in audit scripts, but in production code use
raw strings (`r'^libfuse.*\.dylib$'`) to silence it.

### `display.get_info()` returns 0×0 on the dev fleet
The use.computer SDK's `MacOSSandbox.display.get_info()` call returned
`width=0, height=0, scale=1.0` against `api.dev.use.computer` on
2026-05-17/18 — even though `screencapture` and `screenshot.take_full_screen`
produce real 1920×1080 PNGs. The session-driver scaling code uses these
dims for the `--from1280` flag, so a 0×0 display would scale all clicks
to (0, 0). **Workaround for any custom `*_session.py`**: after `boot`,
hard-code `state["display"] = [1920, 1080]` (or the real value from a
quick `screencapture | sips -g pixelWidth`). The audit task's
`macfuse_session.py` interactive pilot used this workaround successfully
on 2026-05-18; see
`evidence_docs/audit_macfuse_install/interactive_pilot/README.md` for the
exact coordinate scaling that worked: visual_grounding returned (250, 265)
in 1280×720, manually scaled to (375, 397) in 1920×1080.

### visual_grounding works well for Terminal-output reading
The `mcp__visual-grounding__visual_grounding` MCP tool successfully read
specific JSON values from a Terminal pretty-print of the audit report —
including a 10-digit Unix epoch (`core_pkg_install_time=1779077953`),
a 1-digit count, and string field values. This is the recommended way for
a vision agent to verify its own output before declaring task completion,
especially when the output is text-only (no GUI rendering to inspect).

### Persistent "Updates Available" / "Tips" notification banners on base-macos
The use.computer dev fleet's `base-macos` image always boots with two
notifications stuck in the top-right corner — an "Updates Available" prompt
from `softwareupdated` and a "Tips" banner from the first-run app. They
persist across sandbox provisions and are visible in every screenshot
captured without dismissal (5 of 7 in macfuse_env's evidence). For
macfuse_env they don't matter — Terminal sits in the top-left and the
verifier is screenshot-free — but if you build a task whose UI lives in
the top-right (menu-extra reads, status-icon clicks, top-right-anchored
dialogs), dismiss them in your post_start (or pre_task) hook:

```bash
# Force NotificationCenter to drop queued banners (no TCC required).
killall NotificationCenter 2>/dev/null || true
sleep 1
```

The `killall` path works because launchd respawns NotificationCenter with
an empty queue. The alternative — `osascript -e 'tell System Events to
keystroke "w" using {command down}'` — fails over SSH (TCC blocks
`sshd-keygen-wrapper` from Accessibility per the
`12_macos_environments.md` TCC trap).

### Post-finalize screenshots add no new evidence for SSH-side-verifier tasks
For tasks whose `export_result.sh` + `verifier.py` run entirely SSH-side
(via `copy_from_env` / `exec_capture`) and never touch the GUI, a
"post-finalize" screenshot is byte-identical to the last "before-finalize"
screenshot. Caught during macfuse_env interactive_pilot collection: the
captured `05_post_finalize.png` matched `04_after_execution.png` exactly
(MD5 `7b0f2d6fde…`). For these tasks, drop the post-finalize capture from
the standard 5-screenshot sequence; the verifier_result.json + the agent's
report file (downloaded via `copy_from_env`) are the canonical
end-of-task evidence.

---

## Task Inventory

Current macFUSE env (`benchmarks/cua_world-macos/environments/macfuse_env/tasks/`):

- `launch_macfuse` — smoke task; pre_task hook does nothing app-launchy
  (macFUSE is a kernel framework, not an app), verifier just confirms the
  bundle exists on disk with a readable version and the mount helper
  binary is present. Validates env install end-to-end.
- `audit_macfuse_install` — medium-difficulty agent task; agent uses
  Terminal to gather 10 facts about the installed macFUSE and writes a
  JSON audit report. Anti-gaming via per-sandbox install-time. 100 pts
  total, pass at 70. Realistic sysadmin compliance audit workflow.

**Possible future tasks** (mirror Linux env patterns where applicable):

- `inventory_libfuse_consumers` — find all binaries on the system that link
  against `libfuse*.dylib` via `otool -L`, write inventory. (Most likely
  empty in sandbox — interesting because the empty result is itself a
  verifiable audit finding.)
- `compare_macfuse_versions` — agent reads the installed macFUSE version
  AND the latest version available on the macFUSE GitHub releases page (via
  Safari or curl), compares, reports whether an upgrade is needed.
- `read_macfuse_license` — agent opens the License.rtf inside the bundle
  and extracts specific license-text claims (GPL? BSD? per-file?). Tests
  document-reading via Quick Look or text-extraction commands.

---

## Quick-Reference Commands

```bash
# Install macFUSE 4.10.2 from scratch
DMG_URL="https://github.com/macfuse/macfuse/releases/download/macfuse-4.10.2/macfuse-4.10.2.dmg"
curl -fL --retry 5 -o /tmp/macfuse.dmg "$DMG_URL"
MOUNT=$(hdiutil attach -nobrowse -readonly /tmp/macfuse.dmg | awk -F'\t' '$NF ~ /^\/Volumes\//{print $NF}' | tail -1)
sudo installer -pkg "$MOUNT/Extras/macFUSE 4.10.2.pkg" -target /
hdiutil detach "$MOUNT" -force; rm /tmp/macfuse.dmg

# Read bundle metadata
defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleShortVersionString  # → "4.10.2"
defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleIdentifier          # → "io.macfuse.filesystems.fs.macfuse"

# pkg receipt + install timestamp (per-sandbox)
pkgutil --pkg-info io.macfuse.installer.components.core
pkgutil --pkg-info io.macfuse.installer.components.preferencepane

# Kext load state (always 'false' in sandbox)
kextstat | grep -i fuse || echo NOT_LOADED
systemextensionsctl list

# File-system enumeration
ls /Library/Filesystems/macfuse.fs/Contents/Extensions/ | wc -l    # → 13
ls /usr/local/lib/ | grep -c '^libfuse.*\.dylib$'                  # → 4
test -d /Library/PreferencePanes/macFUSE.prefPane && echo INSTALLED

# All installed files for one pkg component
pkgutil --files io.macfuse.installer.components.core
pkgutil --files io.macfuse.installer.components.preferencepane
```
