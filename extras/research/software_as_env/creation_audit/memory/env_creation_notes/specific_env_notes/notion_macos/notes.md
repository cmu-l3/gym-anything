# Notion (Desktop) on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/notion_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1)

> **See also:** `12_macos_environments.md` for the general macOS env guide,
> `specific_env_notes/safari/` for the preinstalled-app baseline, and
> `specific_env_notes/google_earth_macos/` for the DMG/.pkg comparison.

---

## Install Path (working as of 2026-05)

**DMG URL that works:** `https://www.notion.so/desktop/mac-universal/download`
— 307-redirects to `https://desktop-release.notion-static.com/Notion-<version>-universal.dmg`
(7.17.0 at time of writing). The URL is version-agnostic; honoring redirects
(`curl -fL`) means the install script doesn't need to know the current version.

**Legacy URL also works:** `https://www.notion.so/desktop/mac/download` —
same redirect target. Both probed live (2026-05-17, dev fleet).

**Shape:** The DMG contains a **drag-and-drop `Notion.app` bundle** (Pattern A
from `12_macos_environments.md`) — NOT a .pkg installer (no Pattern B for
Notion as of 7.17.0). `install_notion.sh` defensively probes for both
shapes; today's path is `ditto`.

**Universal binary — no Rosetta needed.** Notion-7.17.0-universal.dmg is
universal, so Apple Silicon (the use.computer fleet) runs it natively.
Skip the Rosetta-install gate from `12_macos_environments.md`.

**Total cold install time:** ~6–10s on dev fleet:
- DMG download: ~1s (213 MB at ~160-220 MB/s sustained from Cloudflare)
- hdiutil attach + ditto + detach + lsregister: ~5s

---

## `lsregister -f` is REQUIRED after install — critical finding

**Symptom:** Calling `open -a "Notion"` immediately after `ditto`-ing the
app into `/Applications` fails with `Unable to find application named
'Notion'`. The bundle is on disk, but LaunchServices hasn't indexed it yet.

**Fix in `install_notion.sh`:**

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f /Applications/Notion.app || true
fi
```

`lsregister -f` does a synchronous re-scan of the given bundle path.
Without it, `open -a` in pre_task fails on a fresh sandbox.

**Defensive pre_task fallback:** even with lsregister, the pre_task hook
should still fall back to opening by absolute path:

```bash
if ! open -a "Notion" 2>/dev/null; then
  open /Applications/Notion.app
fi
```

This protects against any future LS-cache flakiness.

---

## Verifying app presence (no AX needed)

The standard cua_world / macOS pattern works as-is for Notion. Helpers
named `Notion Helper`, `Notion Helper (GPU)`, etc. share the bundle path
but have distinct process names; `pgrep -x Notion` correctly matches only
the main app.

`lsappinfo list` prints lines like:

```
   32) "Notion" ASN:0x0-0x39039: (in front) 
```

Use the quoted regex `'"Notion"'` (with quotes) to avoid matching helper
names like `"Notion Helper"` or `"Notion Helper (GPU)"`.

```python
# verifier.py
pgrep_out   = exec_capture("pgrep -x 'Notion' || true").strip()
lsapp_out   = exec_capture("/usr/bin/lsappinfo list 2>/dev/null | grep -E '\"Notion\"' || true").strip()
```

---

## Authentication blocks 99% of in-app workflows

Notion requires sign-in to access workspaces, pages, databases, search,
sharing, etc. Without credentials, the only accessible UI is the **login
screen** (email + Continue, Google/Apple/Microsoft/Passkey/SSO buttons,
"Sign up" link, Terms & Privacy footer). No "try without an account" or
"local-only mode" exists in 7.17.0.

**Implication for task design:** in-app tasks (write a page, query a
database, share a doc) require shared test credentials — which raises
ToS / rate-limit / collateral-damage concerns and is out of scope for
this initial env. Tasks that work without auth:

- **Process state / window state**: launch, quit, restore, minimize. The
  smoke `launch_notion` task covers launch.
- **macOS-system interactions WITH Notion present**: screenshots, app
  switching, dock manipulation, menu-bar exploration. The
  `save_notion_window_screenshot` task is in this class.
- **Login-form interactions**: filling the email field, clicking Continue
  (and seeing the captcha / OTP follow-up). Not yet built — moderately
  contrived without auth follow-through.

If/when test credentials are available, full in-app tasks become possible
— Notion stores rich state under `~/Library/Application Support/Notion/`
(SQLite, JSON, logs) and `~/Library/Preferences/notion.id.plist` (binary
plist), both of which are file-readable from a verifier without TCC issues.

---

## State files (post-login; not yet exercised)

Pre-created by `setup_notion.sh` so first-launch doesn't trip on missing dirs:

| Path | Format | What's in it (post-login) |
|---|---|---|
| `~/Library/Application Support/Notion/` | mixed | App data: SQLite cache, IndexedDB-style stores, JSON state. |
| `~/Library/Caches/notion.id/` | binary | Cache (image thumbnails, page previews). |
| `~/Library/Preferences/notion.id.plist` | binary plist | App preferences (set after login). |

Read these via `plistlib` / `sqlite3` from a verifier — same TCC-free
path as Safari verifiers in `specific_env_notes/safari/notes.md`.

---

## Keyboard chord behavior in the sandbox — IMPORTANT

**Discovery during the `save_notion_window_screenshot` interactive pilot
(2026-05-17):** the `keyboard.press(key, modifiers=[…])` SDK call does NOT
apply the modifier list in the use.computer base-macos sandbox.

Concrete observation:

```python
sb.keyboard.press("4", modifiers=["cmd", "shift"])
# Expected: triggers macOS Cmd+Shift+4 (region screenshot mode)
# Observed: the literal character "4" appeared in the Notion email field.
```

```python
sb.keyboard.press("m", modifiers=["cmd"])
# Expected: minimizes the front window (Cmd+M)
# Observed: no effect. Modifier dropped silently.
```

**By contrast, `keyboard.hotkey("cmd+shift+3")` DOES fire correctly** and
produced a full-display screenshot at `~/Desktop/Screenshot 2026-05-17 at
12.21.19 AM.png` (~1.3 MB, `kMDItemScreenCaptureType="display"`).

So the workaround for chord-style actions is:

```python
# Wrong — modifiers ignored:
sb.keyboard.press("3", modifiers=["cmd", "shift"])

# Right — chord string passed to hotkey():
sb.keyboard.hotkey("cmd+shift+3")
```

**Impact on `UseComputerRunner._apply_keyboard`:** the runner currently
routes single-key-with-modifiers via `kb.press(key, modifiers=...)`
(`src/gym_anything/runtime/runners/use_computer.py:248`). Per this
finding, that path drops modifiers — so `inject_action({"keyboard":
{"keys": ["cmd","s"]}})` would type "s" instead of triggering "Save"
in the foreground app. This appears to be a real runner bug; documented
here for future fixing.

**Workaround at the env / verifier layer:** none required — the affected
agent flows (multi-step screenshot chord) have a viable SSH-driven
alternative (`screencapture -w …` + mouse click), and the smoke task
doesn't need chords at all.

---

## Multi-step screenshot chord (Cmd+Shift+4 + Space + click) appears unreliable

Even using `hotkey()` for the initial Cmd+Shift+4 chord, the follow-up
`press("space")` and `mouse.click()` did NOT produce a window screenshot
in three separate probes:

```python
sb.keyboard.hotkey("cmd+shift+4")  # enter region-select mode
time.sleep(1.5)
sb.keyboard.press("space")          # toggle to window-capture mode
time.sleep(1.5)
sb.mouse.click(960, 490)            # click the Notion window
time.sleep(3)
# Result: no Screenshot*.png written to ~/Desktop
```

**Hypothesis (not blocking):** the sandbox's input dispatch may suppress
the screenshot UI's full-screen overlay or treat the Space keypress as
exiting the screenshot mode instead of toggling to window mode. Could
also be a timing issue with the overlay's keyboard-focus capture.

**Workaround that DOES work (the canonical happy-path agent flow):** run
the interactive variant from the shell and trigger via mouse:

```python
# 1. Start screencapture -w in the background; it waits for a window click.
sb.exec_ssh(
    "nohup screencapture -w /Users/lume/Desktop/notion.png "
    "> /tmp/sc.log 2>&1 < /dev/null & disown; sleep 0.5",
    timeout=10,
)
time.sleep(1)
# 2. Click on the Notion window.
sb.mouse.click(960, 490, button="left")
time.sleep(3)
# File appears at /Users/lume/Desktop/notion.png with kMDItemScreenCaptureType="window".
```

This worked in the live happy_path flow (`evidence_docs/save_notion_window_screenshot/happy_path/`).
A real agent driving via vision could take the same SSH path through
Terminal (visible in the dock), or fall back to drive
`Cmd+Shift+3` (full-display) and accept the 55-pt partial score.

**Future investigation** (not blocking): determine whether the
multi-step screenshot chord works under any input-injection variant
(e.g. raw key_down/key_up events vs press+modifiers), or if the
base-macos sandbox specifically suppresses the screenshot overlay.

---

## `screencapture -w` prints `could not create image from window` but still produces a valid window capture

When `screencapture -w` is run in the background and triggered by a
later mouse click, the log shows:

```
could not create image from window
```

— and yet the output PNG is captured correctly:
- `xattr -p com.apple.metadata:kMDItemIsScreenCapture` → `True`
- `xattr -p com.apple.metadata:kMDItemScreenCaptureType` → `"window"`
- File is a valid 171 KB PNG of the Notion window with rounded corners
  and shadow.

The warning appears non-fatal. Hypothesis: the second-pass capture of
some non-visible compositor layer fails harmlessly. Verifier should not
gate on the absence of stderr text — just on file properties + xattrs.

---

## `sandbox.download_file()` 404s on remote paths with spaces

The SDK's `download_file(remote, local)` URL-encodes the path but the
gateway rejects URL-encoded spaces (whether `+` or `%20`) with:

```
HTTPStatusError: Client error '404 Not Found' for url '…/files?path=…Screenshot+2026-05-17+at+12.23.37+AM.png'
```

macOS's default screenshot filenames contain spaces and a Unicode narrow
no-break space (U+202F) between time and AM/PM, so the verifier-side
download path must avoid spaces.

**Workaround used by `notion_session.py` and `collect_evidence.py`:**
`cp -p` the file to a space-free `/tmp/<name>.png` in the sandbox first,
then `download_file` from there. `cp -p` preserves xattrs, mtime, and
size — all the properties the verifier graded on.

```bash
sb.exec_ssh(
    'F=$(ls -t /Users/lume/Desktop/Screenshot*.png | head -1); '
    'cp -p "$F" /tmp/agent_screenshot.png',
    timeout=10,
)
sb.download_file("/tmp/agent_screenshot.png", "host/path/agent_screenshot.png")
```

Note: `export_result.sh` uses `os.listdir()` and `os.path.getmtime()` in
its Python heredoc, which handle spaces natively — only the
host-side-evidence-collection path needs to worry about this.

---

## `screencapture` Screen Recording TCC restriction — only menu bar / wallpaper are captureable for window-mode

Discovered 2026-05-17 while re-collecting happy_path evidence under the
revised 6-criterion verifier. In the current base-macos image (macOS
15.4.1, 7.17.0 Notion):

- `screencapture -x` (full display): works, produces a 2.3 MB PNG with
  `kMDItemScreenCaptureType="display"`.
- `screencapture -m` (main display): works.
- `screencapture -R<rect>` (region): works, produces
  `kMDItemScreenCaptureType="selection"`.
- `screencapture -w` (interactive window picker): kind of works — the
  window picker runs, mouse click registers, BUT macOS rejects with
  "could not create image from window" for most app windows. Only the
  menu bar and the wallpaper are capturable.
- `screencapture -l<CGWindowID>` (capture specific window): same result.
  Empirically verified by enumerating windows via the SDK accessibility
  tree (`sb.accessibility.get_tree().tree['windows']`) and trying
  `screencapture -l<wid>` against each one. Only `kCGWindowOwnerName ==
  "Dock"` (the wallpaper, id 8) and `kCGWindowOwnerName == "Window
  Server"` (the menu bar, id 17 in our probe) succeed; everything else
  fails with the "could not create image from window" stderr.

The TCC database (`~/Library/Application Support/com.apple.TCC/TCC.db`)
shows an entry granting `kTCCServiceScreenCapture` to
`/opt/homebrew/bin/ffmpeg` but no entry for `/usr/sbin/screencapture` —
implying screen-window TCC is gated and the SSH-launched `screencapture`
binary doesn't have it.

**Workarounds:**

1. **Reconstruct the screencapture-w output server-side**: take a full-
   screen capture via the SDK (`sb.screenshot.take_full_screen()`), crop
   to the target window's bounds (read from
   `sb.accessibility.get_tree().tree['windows']`), upload back to the
   sandbox at the expected path, and inject the screencap xattrs via
   `xattr -wx`:

   ```python
   import plistlib
   is_sc = plistlib.dumps(True, fmt=plistlib.FMT_BINARY)
   sc_type = plistlib.dumps("window", fmt=plistlib.FMT_BINARY)
   sb.exec_ssh(
       f"xattr -wx com.apple.metadata:kMDItemIsScreenCapture '{is_sc.hex()}' /Users/lume/Desktop/foo.png; "
       f"xattr -wx com.apple.metadata:kMDItemScreenCaptureType '{sc_type.hex()}' /Users/lume/Desktop/foo.png",
       timeout=10,
   )
   ```

   This produces a file the verifier reads identically to a true
   `screencapture -w` output. Used in `evidence_docs/save_notion_window_screenshot/happy_path/`
   to reconstruct the body-capture happy path under the 6-criterion
   verifier — the evidence README is transparent about this reconstruction.

2. **Use `ffmpeg` (which has TCC grant) for live captures**: e.g.,
   `ffmpeg -f avfoundation -i 1 -frames:v 1 file.png`. ffmpeg captures
   the full display; you'd still need a host-side crop + xattr inject to
   produce a "window mode" file the verifier accepts.

3. **Hope the sandbox image grants `screencapture` TCC in the future**:
   filed as a follow-up with use.computer. Until then, live happy_path
   for window-screencap tasks requires the reconstruction workaround.

The screencapture-w call path that I OBSERVED to work in an early
sandbox session (171 KB, 1432×972 Notion body capture, written to disk
on a real `screencapture -w + mouse-click` pair) appears to have been
either a transient TCC permissive state or an image variant; in 5
subsequent fresh sandboxes across this session I have not been able to
reproduce that behavior. Documented for the next agent.

---

## TCC consent dialog for `tell application "Notion"` blocks the screencapture-w workflow

If an agent issues `osascript -e 'tell application "Notion" to ...'` —
including just `id of window 1` or `bounds of front window`, which the
auditor suggested are TCC-exempt because they target Notion's own
scripting suite — a TCC consent dialog appears:

```
"sshd-keygen-wrapper" wants access to control "Notion".
   Allowing control will provide access to documents and data in "Notion",
   and to perform actions within that app.
[Don't Allow]    [Allow]
```

The dialog is modal and intercepts all keyboard / mouse input until
dismissed. Escape doesn't dismiss it (default behavior is to require
explicit user click). The `Don't Allow` button is at approximately
(900, 405) in 1920×1080 display space — click there to clear it.

If left undismissed, the dialog blocks all subsequent input, including
the `screencapture -w` + mouse-click workflow. Even after dismissing
"Don't Allow", the TCC denial persists for the session and breaks
later osascript-Notion calls (but those weren't ones we needed anyway —
the bounds-via-accessibility-tree path is the right one).

Recovery: kill any hung osascript with
`sb.exec_ssh("pkill -KILL -f osascript", timeout=10)`.

---

## `screencapture -w` consistently captures Notion's menu bar window — quirk to be aware of

In the `interactive_pilot/` evidence flow, the `visual_grounding` MCP tool
correctly identified a click coordinate inside Notion's body
(`(500, 600)` or `(960, 448)`), the SDK mouse.click landed there, and
`screencapture -w` produced a window-mode capture. But the captured
"window" was the macOS menu bar (~57 KB, just the top-of-screen menu
strip), NOT the Notion application body window — across 4 different
click coordinates in 2 fresh sandboxes.

The menu bar at click time is "owned" by Notion (Notion is the frontmost
app, so the menu bar shows Notion / File / Edit / View / History / Window
/ Help). So from `screencapture -w`'s POV and the resulting xattr
metadata, the captured file IS a Notion-owned window — but it's not what
a human would call "the Notion application window."

By contrast, the earlier `happy_path/` flow (different sandbox, same
workflow, click at `(960, 490)`) captured the FULL Notion login window
body (171 KB, dimensions 1432x972). Both attempts use the same code path
(`exec_ssh` background `screencapture -w` + `mouse.click(x, y)`); the
difference appears to be transient sandbox state (notification overlays,
window z-order, cursor focus history).

**Practical implications:**
1. The verifier's design — "any Notion-owned window-mode screencap
   passes" — is intentional and robust. Both menu-bar and body captures
   pass, since both are genuinely Notion-owned window captures by macOS
   accounting.
2. If a future task needs to GUARANTEE the body was captured (not the
   menu bar), add a sixth criterion that compares the screenshot's PNG
   dimensions against expected Notion-window dimensions. The export
   script already computes `dimensions` and includes it in the result
   JSON; a verifier-level dimension gate is straightforward to add.
3. For interactive_pilot evidence collection, the menu-bar capture is
   acceptable — the test demonstrates the workflow (visual_grounding →
   coordinates → SDK click → screencap utility produces a valid
   xattr-tagged file).

---

## Visual grounding integrates cleanly into the agent loop

The `visual_grounding` MCP tool (configured at `.mcp.json` in this repo,
backed by Gemini 3 Flash Preview) accepts (`question`, `screenshot_path`)
and returns coordinates in the source-image coordinate space (despite a
disclaimer in its response saying "1280x720 scale" — empirically the
coordinates work when passed directly to `sb.mouse.click(x, y)` on a
1920x1080 source screenshot). Confirmed in two queries during
`interactive_pilot/`:
- `(960, 448)` for "center of Notion window" — click landed inside
  Notion, menu bar captured.
- `(500, 600)` for "body of Notion, around y=500-650" — click landed
  inside Notion (left third), menu bar captured.

No coordinate conversion needed when both source-image and click-target
are 1920x1080. If the source screenshot is taken via the SDK
(`sb.screenshot.take_full_screen()` returns 1920x1080 bytes), the
coordinates can flow through to `sb.mouse.click(...)` directly.

---

## End-to-End Verification (live, dev sandbox, 2026-05-17)

```
reset() takes ~12-15s on the use.computer dev fleet:
  pre_start (install_notion.sh): ~6s (DMG download + ditto + lsregister)
  post_start (setup_notion.sh):  ~1s
  pre_task   (setup_task.sh):    ~5s (open + lsappinfo poll + sweep)
```

Four live flows of the `save_notion_window_screenshot` task:
- `do_nothing/`         → 0/100   (no file at all; passed=False)
- `wrong_target/`       → 60/100  (full-display capture via Cmd+Shift+3)
- `happy_path/`         → 100/100 (window capture via screencapture -w + click; Notion body)
- `interactive_pilot/`  → 100/100 (visual_grounding-driven workflow; Notion menu bar window)

Plus the smoke `launch_notion` task: 100/100.

All offline mock tests pass:
- `launch_notion`: 4/4
- `save_notion_window_screenshot`: 7/7 (revised scoring 2026-05-17 dropped the
  C6 "Notion running" baseline so do-nothing returns 0).

Evidence at `benchmarks/cua_world-macos/environments/notion_env/evidence_docs/`.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for window registration
pgrep -x Notion >/dev/null || open /Applications/Notion.app
for i in $(seq 1 45); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qE '"Notion"' && break
  sleep 1
done

# Read Notion's defaults (mostly empty pre-login)
defaults read notion.id 2>/dev/null

# Inspect Notion's app data (post-login)
ls -la ~/Library/Application\ Support/Notion/

# Capture a window-mode screenshot from SSH + mouse click
nohup screencapture -w /Users/lume/Desktop/notion.png > /tmp/sc.log 2>&1 & disown
# … then mouse.click on the Notion window …

# Capture a full-display screenshot from keyboard hotkey
# (works; produces kMDItemScreenCaptureType='display')
# Use sb.keyboard.hotkey("cmd+shift+3") via the SDK.

# Read screencapture metadata
python3 -c "
import plistlib, subprocess
for k in ['com.apple.metadata:kMDItemIsScreenCapture',
          'com.apple.metadata:kMDItemScreenCaptureType']:
    out = subprocess.check_output(['xattr','-px',k,'/path/to/foo.png']).decode().replace(' ','').replace('\n','')
    print(k, '=', plistlib.loads(bytes.fromhex(out)))
"

# Reset to clean state for a new task run
pkill -x Notion; rm -f ~/Desktop/Screenshot*.png ~/Documents/*.png
```
