# macOS Environments Guide

Patterns and lessons learned from macOS-based gym_anything environments. The macOS family is younger than Linux/Windows/Android and only one runner currently targets it: **`UseComputerRunner`**, which drives remote macOS sandboxes via the [use.computer](https://use.computer) SDK.

> **See also:** `10_cross_cutting_patterns.md` general patterns (most apply unchanged), `specific_env_notes/google_earth_macos/` for the first concrete env, `specific_env_notes/safari/` for the preinstalled-app baseline, `specific_env_notes/notion_macos/` for the universal-binary DMG path + the screencapture-xattr verifier pattern + keyboard-modifier bug.

---

## Architecture: Remote Sandbox, Not a Local VM

Unlike Linux (Docker / Apptainer / QEMU on-host) and Windows (QEMU-in-Apptainer), the macOS guest **does not run on your hardware**. Each `start()` provisions a fresh macOS VM on a use.computer M4 Mac mini fleet:

```
gym-anything host ──HTTPS──▶ use.computer gateway ──▶ M4 Mac mini ──▶ macOS 15 VM (4 cores / 8 GB)
                                                                       └─ user 'lume' (passwordless sudo)
                                                                       └─ /Users/lume/workspace (uploaded mounts)
```

**Why it has to be remote:** Apple's EULA restricts macOS virtualization to Apple hardware, and Virtualization.framework caps nested virt at 2 VMs per host. Running macOS as a guest inside a Docker/QEMU container on a generic host isn't legally or technically possible.

**Implication for env design:** every `reset()` pays a network round-trip to provision a fresh VM. There's no local snapshot to load. See "No Checkpoint Caching" below.

---

## Authentication & Connection

The runner expects two env vars (read on construction, fails fast if `USE_COMPUTER_API_KEY` is unset):

```bash
export USE_COMPUTER_API_KEY=mk_live_…         # mint at https://use.computer
export USE_COMPUTER_BASE_URL=https://api.use.computer            # prod
# or                          https://api.dev.use.computer       # dev
```

**Key environments are scoped:** a `mk_live_*` key minted in prod returns 401 against dev (and vice versa). The SDK accepts both `api_key=` and `base_url=` to override at construction time.

---

## Workspace Path: `/Users/lume/workspace`, NOT `/workspace`

macOS root volume is **read-only** under SIP (System Integrity Protection, since Catalina). `mkdir /workspace` will fail with `Read-only file system`. The runner mounts uploads at `/Users/lume/workspace/` instead.

**For env.json:** mount targets and hook commands must use the macOS-native path.

```json
"mounts": [
  {"source": "benchmarks/cua_world-macos/environments/<env>/scripts",
   "target": "/Users/lume/workspace/scripts", "mode": "ro"},
  {"source": "benchmarks/cua_world-macos/environments/<env>/tasks",
   "target": "/Users/lume/workspace/tasks", "mode": "ro"}
],
"hooks": {
  "pre_start":  "/Users/lume/workspace/scripts/install_<app>.sh",
  "post_start": "/Users/lume/workspace/scripts/setup_<app>.sh"
}
```

Task `pre_task` paths follow the same pattern: `/Users/lume/workspace/tasks/<task>/setup_task.sh`.

---

## Installation Patterns

### Pattern A — Native Drag-and-Drop App (DMG with `.app` bundle)

```bash
DMG_URL="https://example.com/App.dmg"
DMG_PATH="/tmp/App.dmg"
curl -fL --retry 5 --retry-delay 5 -o "$DMG_PATH" "$DMG_URL"

# hdiutil attach prints "/dev/diskN\t...\t/Volumes/Name" — extract the mount point with awk.
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" \
              | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)

APP_SRC=$(find "$MOUNT_POINT" -maxdepth 2 -name "App.app" -type d | head -1)
sudo ditto "$APP_SRC" "/Applications/App.app"
hdiutil detach "$MOUNT_POINT" -force
sudo xattr -dr com.apple.quarantine "/Applications/App.app"   # bypass Gatekeeper on first launch
rm -f "$DMG_PATH"
```

### Pattern B — DMG with `.pkg` Installer (Google Earth Pro, increasingly common)

Modern Apple installers ship `.pkg` files inside the DMG instead of drag-and-drop `.app` bundles. Use `installer -pkg`:

```bash
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" \
              | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)
PKG=$(find "$MOUNT_POINT" -maxdepth 2 -name "Install *.pkg" -type f | head -1)
sudo installer -pkg "$PKG" -target /
hdiutil detach "$MOUNT_POINT" -force
```

Write your install script to **detect both shapes** — older docs/cookbooks may say drag-and-drop, but Google has migrated multiple flagship apps to `.pkg`. Probe with `find -name "*.pkg" -o -name "*.app"`.

### Pattern C — Homebrew Cask

`base-macos` ships Homebrew at `/opt/homebrew/bin/brew` but **not on the PATH for non-login SSH sessions**. Source the env explicitly:

```bash
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask <cask-name>
```

**Gotcha:** the `--no-quarantine` flag was removed from current Homebrew. If you see `Error: Calling the --[no-]quarantine switch is disabled`, just drop the flag.

### Rosetta 2 for x86 Binaries

Many macOS apps (including Google Earth Pro) still ship x86_64-only binaries. On Apple Silicon (use.computer is M4) you must install Rosetta first:

```bash
if [ "$(uname -m)" = "arm64" ]; then
  if ! /usr/bin/pgrep -q oahd; then     # oahd = Rosetta runtime daemon
    sudo softwareupdate --install-rosetta --agree-to-license
  fi
fi
```

`oahd` running ⇒ Rosetta is installed. Safe to gate on its presence.

---

## Task Convention (Same as cua_world)

**`pre_task` launches the app; agent tasks are operations inside the running app.**

This is the same convention as cua_world Linux/Windows envs. For macOS:

```bash
# tasks/<task_name>/setup_task.sh — idempotent app launch + wait
#!/bin/bash
set -eu
if ! pgrep -f "App Name" >/dev/null; then
  open -a "App Name"
fi
# Poll lsappinfo until the bundle registers a window (~30s max).
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qi "App Name"; then
    break
  fi
  sleep 1
done
sleep 3   # let startup dialogs settle
```

Smoke / verification tasks: `max_steps: 1`, no-op agent action, verifier just checks the app is running. Real agent tasks: pre_task launches; the task description is an in-app operation.

**Do not write "launch the app" as an agent task.** That breaks the convention and the interactive-VNC flow (`gym-anything run … -i --open-vnc`) shows an empty desktop because pre_task killed the app.

---

## Launching GUI Apps from SSH

Use `open -a "App Name"` — it goes through LaunchServices, attaches to the right user session, and produces a visible window.

```bash
open -a "Google Earth Pro"
```

**Do NOT** rely on Spotlight (`cmd+space`) injected via the keyboard API. The `base-macos` sandbox image does not respond to the Spotlight shortcut (Spotlight indexing is either disabled or not exposed to the shortcut layer). The keyboard inject path itself is fine — single keys and chords like `cmd+shift+s` work — but cmd+space specifically is a no-op.

---

## AppleScript / Accessibility over SSH: TCC Trap

`exec_ssh` runs commands under a responsibility chain rooted at `sshd-keygen-wrapper`. macOS's TCC framework does **not** grant Accessibility permissions to that chain by default. So AppleScript that walks the AX tree (`tell application "System Events" to …`, `attribute "AX..." of …`, `keystroke …`) fails silently with error -25211.

**Workarounds:**

1. Use `lsappinfo list`, `pgrep`, or `ps` for state probing — they don't need AX:
   ```bash
   /usr/bin/lsappinfo list 2>/dev/null | grep -i "App Name"
   pgrep -f "App Name"
   ```

2. The use.computer SDK ships an in-VM helper (`/usr/local/bin/ax_helper.py`) and a transpiler (`use_computer.ax_transpile`) that rewrites AppleScript AX patterns to call the helper through a different responsibility chain (launchd → cua-server → python3.12) that TCC does grant. Use this for verifiers that genuinely need AX:
   ```python
   from use_computer.ax_transpile import transpile, needs_exec_ax
   rewritten, _ = transpile(open("test.sh").read()) if needs_exec_ax(raw) else (raw, None)
   mac.upload_bytes(rewritten.encode(), "/tmp/test.sh")
   mac.exec_ssh("bash /tmp/test.sh")
   ```

3. The runner can expose an `exec_ax` method (the SDK's `MacOSSandbox.exec_ax`) for verifiers that need AX directly. Not currently in `env_info`; add if needed.

**Default for verifiers:** prefer the `pgrep` / `lsappinfo` / file-system path.

---

## VNC Is Gateway-Proxied, No Local Port

The runner exposes `vnc_url` (a `https://api.…/v1/sandboxes/<id>/vnc` URL) instead of `vnc_port`. Auth is bearer-token; opening the raw URL in a browser won't work without the use.computer dashboard's session cookie. For interactive viewing:

- `gym-anything run … -i --open-vnc` — prints the URL and tries to open it; you'll need the dashboard logged in.
- Use the use.computer dashboard (`https://use.computer`) — find your sandbox under reservations and click the noVNC button.

`SessionInfo.vnc_port` is `None` for this runner. Higher layers (`InteractiveSession`) fall back to `vnc_url` automatically.

---

## No Checkpoint Caching (Today)

`UseComputerRunner.supports_checkpoint_caching()` returns False. There is no snapshot/clone endpoint on the use.computer API today; we can't bake a "post-install" image and re-create from it. Every `reset()` pays the full install cost.

**Implications:**
- `env.reset(use_cache=True, ...)` will **raise** for use_computer-backed envs. Use `use_cache=False` (the CLI default).
- Per-env install cost compounds. For Google Earth Pro: ~70s cold (Rosetta + 82MB DMG + .pkg install). Larger apps (Xcode toolchain, Blender, FCP) will be much worse.
- **The fix is upstream**, not a local workaround. Asking use.computer to add a snapshot/image-bake API is the right ask. Per the gym-anything generality principle, do not invent a client-side tarball workaround that captures filesystem state but misses LaunchAgents, TCC grants, system services, etc. — it would silently produce divergent behavior across runners.

---

## Verifier Patterns

Process + LaunchServices window check (no AX, no TCC headaches):

```python
def verify_app_running(traj, env_info, task_info) -> dict:
    exec_capture = env_info["exec_capture"]
    pgrep_out = exec_capture("pgrep -f 'App Name' || true").strip()
    process_running = bool(pgrep_out)
    lsapp = exec_capture("/usr/bin/lsappinfo list 2>/dev/null | grep -i 'App Name' || true")
    window_registered = bool((lsapp or "").strip())
    passed = process_running and window_registered
    return {"passed": passed, "score": 100 if passed else (50 if process_running else 0),
            "feedback": f"process_running={process_running}; window_registered={window_registered}"}
```

For app-state checks beyond presence, prefer files: most macOS apps store state under `~/Library/Application Support/<App>/`, `~/Library/Preferences/com.<vendor>.<app>.plist`, or app-specific bundles (e.g. Google Earth's `~/Library/GoogleEarth/myplaces.kml`). `defaults read` is the canonical way to query plists.

---

## use.computer SDK Quirks Worth Knowing

- **`ExecResult` has `return_code` and `stdout` only.** No `exit_code`, no `stderr`. The runner's `exec()` reads `return_code`; verifiers calling `env_info["exec_capture"]` get a string.
- **`Computer.create()` doesn't take `image=` in its typed signature** even though the HTTP API does. The runner POSTs directly when `spec.image` is set, so envs can pick `base-macos` (default) or `base-human`.
- **Idle reaper: 2 minutes.** Sandboxes die after 2 min of no API touch + no SSH + no VNC. The runner starts a keepalive thread automatically; agents with >2-min think time inherit it for free.
- **Upload throughput is gateway-limited** (~4 MB/s on dev). Plan for slow uploads of large data fixtures.
- **`host=mm00X`** in the create payload is a hint, not a pin — the scheduler can re-route. Don't depend on session affinity.

---

## Cold Start Cost & Budgeting

Reset breakdown on a fresh sandbox with the Google Earth env:

| Step | Time |
|------|------|
| sandbox provision | ~1s |
| workspace mkdir + upload mounts | ~3s |
| `pre_start` (Rosetta + DMG + pkg) | ~50s |
| `post_start` (config dirs) | <1s |
| `pre_task` (open + window-register poll) | ~15s |
| obs capture, session info, etc. | ~5s |
| **total** | **~70-90s** |

For multi-task runs, expect that full cost per reset until upstream snapshot support lands.

---

## Hook Log Paths: ALWAYS Add a macOS Sibling

`src/gym_anything/env.py` redirects each hook's stdout/stderr to a Linux-only
path (`/home/ga/env_setup_*.log`, `/home/ga/task_*.log`) when no `macos`
branch is present. On macOS this fails silently — bash can't write to
`/home/ga/...` because the macOS root volume is read-only under SIP — and the
hook script **never runs**.

Surfaced first while porting `firefox/devtools_security_header_audit` to
Safari: `_run_post_task_hook` (env.py:908) lacked a macOS branch, so `export_result.sh`
never executed. The verifier read an empty `/tmp/<task>_result.json` and
returned "Could not retrieve result file" with score 0 — even when the agent
did the work correctly. Fixed by adding a macOS branch that writes to
`/Users/lume/task_post_task.log`.

**The rule:** any time `env.py` (or any other core file) introduces a
hardcoded `/home/ga/` path, mirror it with `/Users/lume/`:

```python
elif self._platform_family() == "macos":
    self._runner.exec(f"bash -lc {hook_cmd} > /Users/lume/task_X.log 2>&1")
```

Same for the log-collection list in `_finalize` (env.py:1027) — include both
the Linux and macOS variants; `copy_from` silently skips non-existent files
so listing both is safe and future-proofs the artifact bundle.

---

## Keyboard `Enter` ≠ `Return` in Safari (and probably elsewhere)

The SDK's `keyboard.press("Return")` sends a keycode that Safari's address
bar does NOT interpret as "submit form" — typing a URL + `Return` leaves
Safari sitting on the previous page even though the URL bar visually updates.
`keyboard.press("Enter")` (or `keyboard.hotkey("Enter")`) actually triggers
navigation.

Surfaced during the interactive pilot for `safari_env/devtools_security_header_audit`
(`evidence_docs/.../interactive_pilot/`): URL typed, Return sent, `osascript
... get URL of front document` reported `about:blank` (unchanged). After
sending `Enter`, document URL changed to the intended URL.

**Rule:** use `Enter` for "submit" / "go" in macOS apps via the SDK. Tasks
that need an explicit dismiss-by-Return (e.g., closing a dialog) may need to
try both; document per-app.

`keyboard.type(text)` with `\n` embedded does send Return-equivalent
keystrokes that Terminal accepts under heredoc mode — so multi-line script
typing works there. The `Enter`/`Return` distinction matters in form-submit
contexts specifically, not in raw line input.

---

## `keyboard.press(key, modifiers=[...])` Drops Modifiers — Use `hotkey()` Instead

Discovered during the `notion_env / save_notion_window_screenshot`
interactive pilot (2026-05-17). The use.computer SDK's
`MacOSSandbox.keyboard.press(key, modifiers=[...])` call does NOT apply
the modifier list in the base-macos sandbox:

```python
sb.keyboard.press("4", modifiers=["cmd", "shift"])
# Expected: triggers macOS Cmd+Shift+4 (region screenshot mode).
# Observed: the literal character "4" appears in the focused text field.

sb.keyboard.press("m", modifiers=["cmd"])
# Expected: minimizes the front window (Cmd+M).
# Observed: no visible effect.
```

By contrast, `keyboard.hotkey(chord_str)` DOES fire chords correctly:

```python
sb.keyboard.hotkey("cmd+shift+3")
# Observed: full-display screenshot written to ~/Desktop with
# kMDItemScreenCaptureType="display".
```

**Implications for env / runner code:**

1. **`UseComputerRunner._apply_keyboard` (use_computer.py:248) routes
   single-key-with-modifiers via `kb.press(key, modifiers=...)`.** Per
   this finding, that path silently drops modifiers. Agents that emit
   `inject_action({"keyboard": {"keys": ["cmd", "s"]}})` will see the
   literal "s" typed instead of triggering the foreground app's Save
   shortcut. **This is a runner-layer bug worth fixing — convert to
   `hotkey("+".join(keys))` for any chord with modifiers.**

2. **In env-side scripts (interactive drivers, evidence collectors),
   always call `keyboard.hotkey("cmd+...")` instead of
   `keyboard.press(..., modifiers=[...])`.** The macos_session.py and
   notion_session.py drivers in this repo do this.

3. **Multi-step screenshot chords (Cmd+Shift+4 + Space + click) remain
   unreliable even when the initial chord is sent via `hotkey()`.** In
   three separate probes, the follow-up Space + click did not produce a
   window screenshot. The reliable alternative is to drive `screencapture
   -w file.png` in the background via SSH and trigger via a mouse click
   on the target window — confirmed working in
   `benchmarks/cua_world-macos/environments/notion_env/evidence_docs/save_notion_window_screenshot/happy_path/`.

## Cmd+Space (Spotlight) Does Not Open Spotlight

Confirmed in 4 separate probes against base-macos. `keyboard.press("space",
modifiers=["cmd"])` succeeds (200 from the API) but Spotlight never appears.
Likely the macOS Sandbox base image either disables Spotlight indexing or
unbinds the shortcut. Open apps via the Dock, AppleScript
(`osascript -e 'tell application "X" to activate'`), or `open -a X` via SSH.

---

## System Apps Live in `/System/Applications/`, Not `/Applications/`

Apple's first-party system apps (Preview, Mail, Maps, Calculator, etc.)
live in `/System/Applications/` since Catalina; `/Applications/` is for
user-installed apps. Apple is inconsistent — Safari sits in
`/Applications/` on the use.computer dev fleet (macOS 15.4.1) for
backward-compat reasons, but Preview is at
`/System/Applications/Preview.app`.

**Practical implication for install scripts**: don't hard-code one path.
Probe both:

```bash
CANDIDATES=(
  "/Applications/<AppName>.app"
  "/System/Applications/<AppName>.app"
)
APP=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c" ]; then APP="$c"; break; fi
done
if [ -z "$APP" ]; then
  echo "FAILED — bundle not at either path" >&2
  ls /Applications /System/Applications | head -30 >&2
  exit 1
fi
```

LaunchServices (`open -a <AppName>`) finds the bundle either way via
bundle ID, so the runtime path doesn't matter — but explicit existence
checks in `install_<app>.sh` must look in both locations or they will
silently report success on a broken sandbox (cf. the `; echo done`
shell-wrapper trap that swallows exit codes in `preview_session.py`).

Surfaced in `preview_env`'s install hook (2026-05). Confirmed live on
use.computer dev: Preview ✗ in /Applications, ✓ in /System/Applications;
Safari ✓ in /Applications.

---

## `lsappinfo` Regex: Helper-Free Apps Need a Different Pattern

`safari_env`'s smoke verifier uses `grep -iE 'Safari( |$)'` on
`lsappinfo list` output to detect "Safari is registered". The regex works
for Safari because helpers like `SafariLinkExtension` and especially the
quoted-name entries (`"Safari Networking"`, with a literal space inside
the quotes) match `Safari ` followed by space.

**For apps without such helpers — Preview is one — the pattern never
matches.** Preview's lsappinfo entry is:

```
31) "Preview" ASN:0x0-0x2e02e: (in front)
    bundleID="com.apple.Preview"
    bundle path="/System/Applications/Preview.app"
    executable path="/System/Applications/Preview.app/Contents/MacOS/Preview"
```

`Preview` is followed by `"` (the closing quote), not space or
end-of-line. `Preview( |$)` returns nothing, the verifier reports
`window_registered=False`, and the smoke task scored 50 instead of 100
even though Preview was fully running.

**Fix — match the bundle-path line instead:**

```python
lsapp = exec_capture(
    "/usr/bin/lsappinfo list 2>/dev/null | grep -iE '<AppName>\\.app' || true"
)
```

The bundle-path line (`bundle path="/System/Applications/Preview.app"`)
is emitted exactly when LaunchServices has registered the app — same
signal, robust regardless of helper-process presence. Future helper-free
apps (Calculator, TextEdit, Stickies, Chess, etc.) should use this
pattern by default.

Surfaced in `preview_env`'s `launch_preview` smoke verifier (2026-05).

---

## Safari Is Sandboxed — Real Prefs Live in a Container

Safari runs out of an app sandbox; its preferences are NOT at the standard
`~/Library/Preferences/com.apple.Safari.plist` you might expect. The real
file is:

```
~/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari.plist
```

Some prefs (e.g. `HomePage`) do propagate from `defaults write com.apple.Safari`
to the sandbox via cfprefsd's internal sync. Others (`IncludeDevelopMenu`,
`ShowFavoritesBar`) don't take effect even when written to BOTH the standard
and container paths and with `killall cfprefsd` in between. The full
investigation matrix is in `specific_env_notes/safari/notes.md` ("Sandbox /
Develop menu" section) with probe screenshots under the per-task evidence
dir.

**Practical implications for task design:**
- `HomePage` works — safe to set in `setup_safari.sh` for deterministic
  start state.
- `IncludeDevelopMenu` / `ShowFavoritesBar` do NOT reliably surface. Don't
  design tasks that require them via menu UI; use `Cmd+Option+I` (Web
  Inspector shortcut) or Terminal `curl` instead. The
  `devtools_security_header_audit` task in safari_env was validated via the
  Terminal-curl path scoring 97/100.

**Open investigation**: find the canonical mechanism (MDM profile? user
gesture replay? undocumented key?) that activates these prefs. Not blocking
task work — agents have alternative completion paths.

---

## Adding a New macOS Env — Quick Checklist

- [ ] Read this file end to end
- [ ] Check `specific_env_notes/<app>_macos/` for prior notes on similar apps
- [ ] env.json: `base: "macos"`, mount targets at `/Users/lume/workspace/...`, hooks reference that path
- [ ] install script handles Rosetta + Pattern A or B (DMG → .app or DMG → .pkg), with brew cask as fallback
- [ ] `chmod +x scripts/*.sh tasks/*/*.sh` immediately after creation
- [ ] pre_task launches the app, polls `lsappinfo` for window registration
- [ ] verifier uses `pgrep` + `lsappinfo` (avoid AX over SSH)
- [ ] Test end-to-end via `gym-anything run … --task <task> -i --open-vnc` — the noVNC viewer must show the expected start state when the panel appears
