# QuickTime Player on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/quick_time_player_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1, QuickTime Player 10.5)

> **See also:** `12_macos_environments.md` for the general macOS env guide;
> `specific_env_notes/safari/notes.md` for the preinstalled-app baseline;
> `specific_env_notes/preview/` for the closest analog (system app, document-based AppKit,
> NSShowAppCentricOpenPanelInsteadOfUntitledFile pattern).

---

## Install Story: Trivial (system app)

QuickTime Player is **preinstalled** on every macOS image at
`/System/Applications/QuickTime Player.app`. The base-macos sandbox ships
QuickTime Player 10.5 (universal binary, ARM64-native — no Rosetta needed).
`install_quick_time_player.sh` only verifies the bundle is present (probing
both `/Applications` and `/System/Applications`, like preview_env), and hard
fails otherwise. Cold install: <1s.

Apple has been migrating its first-party apps from `/Applications` to
`/System/Applications` since Catalina. QuickTime Player has been in
`/System/Applications/` for several macOS releases — always probe both
candidate paths.

---

## Process Name Has a Literal Space

The main process binary is `QuickTime Player` (with a space). Patterns that work:

| Use case | Pattern |
|---|---|
| Detect main process | `pgrep -x 'QuickTime Player'` |
| Detect via LaunchServices | `lsappinfo list \| grep -F 'bundleID="com.apple.QuickTimePlayerX"'` |
| Launch from SSH | `open -a "QuickTime Player"` |
| Quit via AppleScript | `osascript -e 'tell application "QuickTime Player" to quit'` |

Patterns that DO NOT work:
- `pgrep QuickTime` — matches helper / unrelated processes, may include false positives
- `pgrep QuickTimePlayer` — does not match (the binary has a space)
- `lsappinfo list \| grep 'QuickTime( |$)'` — Safari-pattern; QuickTime has no
  helpers with that punctuation shape, so the regex never matches even when
  QuickTime is fully running. Use the **bundleID grep** instead (apple_notes
  pattern) — robust regardless of helper-process presence.

The smoke verifier uses both `pgrep -x` and the bundleID grep AND'd
together. The negative case (QuickTime killed) returns score=0 cleanly.

---

## Configuration: `defaults write com.apple.QuickTimePlayerX`

Prefs domain is `com.apple.QuickTimePlayerX`. The "X" suffix is from the
QT10 rewrite in Snow Leopard and is still the canonical domain on macOS 15.4.
Read current keys with `defaults read com.apple.QuickTimePlayerX`.

| Key (com.apple.QuickTimePlayerX) | Type | Purpose |
|---|---|---|
| `NSShowAppCentricOpenPanelInsteadOfUntitledFile` | bool | When false, suppresses the modal NSOpenPanel that otherwise pops on first launch with no document. Required for screenshot determinism. |
| `NSQuitAlwaysKeepsWindows` | bool (global) | When false, prevents window/document restoration on next launch. Important so each reset starts clean. |
| `ApplePersistence` | bool (global) | Same as above; AppKit's older flag for the same behavior. |

QuickTime Player does NOT appear to be sandboxed in the same way Safari is
(no `~/Library/Containers/com.apple.QuickTimePlayerX/` container path
containing a separate prefs file). The standard
`~/Library/Preferences/com.apple.QuickTimePlayerX.plist` is the live file.
Verify with `defaults read com.apple.QuickTimePlayerX` after a write — the
key shows up there, not in a container path.

---

## Behavior on Launch with No File

QuickTime is a document-based AppKit app. Out of the box, `open -a "QuickTime
Player"` triggers a modal `NSOpenPanel` ("QuickTime Player wants to open a
file") that BLOCKS any further interaction until dismissed.

With `NSShowAppCentricOpenPanelInsteadOfUntitledFile = false` (written in
setup_quick_time_player.sh and cfprefsd-flushed), the launch is silent —
QuickTime activates as the front app with menu bar `QuickTime Player / File /
Edit / View / Window / Help` and NO window. Agents can then trigger
`File > New Movie Recording`, `File > New Audio Recording`, `File > New
Screen Recording`, or `File > Open File...` as needed for the task.

This is the same pattern as Preview and the apple_notes "no notes" splash;
the only thing different is QuickTime shows zero document window vs
Preview's empty fullscreen background.

---

## State Files for Verifier Strategy

Per the macOS guide, prefer **file-based verifiers** over UI inspection (no
TCC trap over SSH). For QuickTime tasks, the canonical state surfaces are:

| State | Path |
|-------|------|
| User preferences (domain plist) | `~/Library/Preferences/com.apple.QuickTimePlayerX.plist` |
| Movie/audio recordings (default save) | `~/Movies/` (movie recordings), `~/Desktop/` (alternative path users sometimes pick) |
| Screen recordings (default save) | `~/Movies/Screen Recording <timestamp>.mov` or `~/Desktop/` depending on user choice |
| Recent documents | `~/Library/Preferences/com.apple.QuickTimePlayerX.LSSharedFileList.plist` (recents) |
| Application Support | `~/Library/Application Support/com.apple.QuickTimePlayerX/` (rarely used) |

For "did the agent record N seconds of audio" tasks: check the resulting
file with `afinfo <path>` (gives duration, sample rate, encoding) — afinfo
is a system tool that ships on macOS by default. No third-party install
needed.

For "did the agent trim the clip" tasks: again `afinfo` for duration. Or
parse the QuickTime atom tree using Python's `mutagen` / `mediafile` (would
need install in pre_start) or `mdls <path>` (system tool, gives Spotlight
metadata including `kMDItemDurationSeconds`).

For "did the agent record N pixels of screen" tasks: check the result with
`mdls <path>` for `kMDItemPixelHeight` / `kMDItemPixelWidth`.

---

## Smoke Task — Live Run (2026-05-17)

```
reset() took ~13s on a warm sandbox provision (~50s cold including upload)
pre_start (install_quick_time_player.sh):  ~1s  (no install, just verify)
post_start (setup_quick_time_player.sh):   ~2s
pre_task (setup_task.sh):                  ~3-5s (open + lsappinfo poll, 1s)
verifier: passed=True, score=100
```

Visual evidence:
- `evidence_docs/launch_quick_time_player/launch_quick_time_player_panel_view.png`
  — what the interactive panel viewer sees after pre_task completes.
- `evidence_docs/launch_quick_time_player/live_smoke/{*.log, verifier_result.json, summary.json}`
  — hook logs + verifier output + structured trajectory summary.

Negative path probed via `osascript ... quit + pkill -x 'QuickTime Player'`,
verifier returned `{score: 0, passed: false}` as expected.

---

## What to Watch For When Porting Tasks

1. **Recording-permission TCC prompts** — QuickTime's `New Audio Recording`,
   `New Screen Recording`, and `New Movie Recording` all require microphone
   and/or screen recording permissions. The use.computer base-macos image
   is provisioned with these grants for `lume`. If you find recording fails
   silently in pre_task setup, check
   `tccutil reset Microphone com.apple.QuickTimePlayerX` and
   `tccutil reset ScreenCapture com.apple.QuickTimePlayerX` to re-prompt
   the system. As of dev fleet probe (2026-05) the default state was
   permissive enough for movie/audio capture to start without per-task prompts.

2. **`File > New Audio Recording` shortcut**: `Cmd+Option+N` (Option = Alt).
   Use the runner's `keyboard.hotkey("cmd+option+n")` per the
   notion_macos lesson — `keyboard.press("n", modifiers=[...])` drops
   modifiers in the use.computer SDK.

3. **`File > New Screen Recording` shortcut**: `Cmd+Ctrl+N` (note: this
   actually invokes the macOS 14+ Screenshot.app screen-recording flow, NOT
   QuickTime's own panel — Apple deprecated the QuickTime panel in favor of
   the global screenshot HUD). For task evidence purposes treat both as
   equivalent; the resulting file lands in `~/Desktop/` (Screenshot.app) or
   `~/Movies/` (QuickTime) depending on which path triggered.

4. **`File > Open File...` shortcut**: `Cmd+O`. Then a file path can be typed
   into the path-bar shortcut by hitting `Cmd+Shift+G` first (Go-to-folder).

5. **Trim mode shortcut**: `Cmd+T` opens the trim view. Save in-place is
   `Cmd+S`; Export As is `File > Export As > ...` (sub-menu with 4K, 1080p,
   720p, 480p, Audio Only — no shortcut).

6. **Quitting cleanly**: Use `osascript -e 'tell application "QuickTime Player"
   to quit'` followed by `pkill -x 'QuickTime Player'` (belt and suspenders).
   AppleScript quit is graceful (writes any pending recording-save state);
   pkill is a hard backstop.

---

## Known Gotchas

### "Updates Available" notification fires before post_start can suppress it
The system `Updates Available` toast in the top-right corner appears on cold
boot before `setup_quick_time_player.sh` writes
`com.apple.SoftwareUpdate AutomaticDownload=false`. The notification is
already queued by launchd's startup. Result: it visibly appears in the first
screenshot after reset. The `Tips Notification` toast (also seen on first
runs) IS suppressed by `com.apple.notificationcenterui doNotDisturb=true`.

Same limitation as apple_notes_env. Workaround for tasks that need clean
screenshots: dismiss the notification programmatically (click "Remind Me
Later") in pre_task before handing control to the agent. The smoke task
doesn't bother because the notification doesn't block input.

### Process name space-matching
`pgrep -x QuickTime` fails (no exact match). `pgrep -x 'QuickTime Player'`
works. Make sure to quote the full name with the literal space in any shell
or Python `exec_capture` call.

### Audio/movie hardware in the sandbox
The use.computer M4 fleet provides a software audio driver
(coreaudiod with a built-in test signal source) and a virtual display.
"New Audio Recording" produces a file with detectable content; "New Movie
Recording" captures the virtual webcam if one is attached (depends on
fleet config — probe before relying for task design).

---

## Quick-Reference Commands

---

## Real Task Built: `play_target_audio_clip` (2026-05-17)

Live-validated end-to-end. See `tasks/play_target_audio_clip/README.md` and
`evidence_docs/play_target_audio_clip/` in the env for details.

**Design summary:**
- Pre-stage a small Apple system sound (`/System/Library/Sounds/Funk.aiff`,
  ~2.16s) to `~/Documents/qtp_target_audio.aiff` at task-start time.
- pre_task opens the file in QuickTime so the agent starts with a loaded,
  paused document at `current_time = 0.0`.
- Single natural agent action: press `space` (QuickTime's default
  Play/Pause binding).
- export_result.sh queries QuickTime's AppleScript scripting interface
  (`tell application "QuickTime Player" to get current time of front
  document`, etc.) — no TCC issue because the scripting goes through Apple
  Events, not AX/System Events.
- Verifier: 5 criteria, 100-pt scale, pass at 60. Strict wrong-target gate
  on the front-document name. Pattern-#4 partial-only ceiling = 30.

**Live results:**

| Flow | Verifier | Notes |
|---|---|---|
| interactive_pilot (1 space press) | 100/100 PASS | Audio played to end; current_time = duration |
| do_nothing | 30/100 FAIL | C1+C2+C5 only; below pass threshold |
| wrong_target (open Basso.aiff) | 0/100 FAIL | Strict gate fired on front-doc mismatch |

**Offline mock tests:** 9 scenarios, all passing.

---

## Sandbox Status: QuickTime IS sandboxed, but defaults writes work

Confirmed live (probe_prefs flow, 2026-05-17): the container path
`~/Library/Containers/com.apple.QuickTimePlayerX/` exists (so QuickTime is
in fact sandboxed), but the writes that `setup_quick_time_player.sh`
performs via `defaults write com.apple.QuickTimePlayerX <key>` DO take
effect. Specifically:

- `NSShowAppCentricOpenPanelInsteadOfUntitledFile = 0` observably
  suppresses the modal NSOpenPanel that would otherwise pop on launch.
- `defaults read com.apple.QuickTimePlayerX` returns the values we wrote.
- The standard preferences file at
  `~/Library/Preferences/com.apple.QuickTimePlayerX.plist` is **absent**
  (no matches when listing `ls ~/Library/Preferences/com.apple.QuickTimePlayerX*`)
  — meaning the defaults system is auto-redirecting to the container path.

**Why this matters:** unlike Safari, where some prefs
(`IncludeDevelopMenu`, `ShowFavoritesBar`) DO NOT propagate from the
standard domain to the sandboxed app's actual reading location, QuickTime's
writes propagate cleanly. The "defaults writes don't work on sandboxed
apps" lesson from Safari does **not** generalize — it's app-specific.

**Cached prefs path discovery:** if you do need to read the actual sandbox
prefs file (e.g., to confirm a write took effect at the binary level), the
likely paths are:

- `~/Library/Containers/com.apple.QuickTimePlayerX/Data/Library/Preferences/com.apple.QuickTimePlayerX.plist`
- `~/Library/Containers/com.apple.QuickTimePlayerX/Data/.com.apple.containermanagerd.metadata.plist` (container metadata, not the user-prefs file)

Probe with `ls -la ~/Library/Containers/com.apple.QuickTimePlayerX/Data/` after
your `defaults write` runs.

---

## AppleScript Scripting Interface for Verifiers

QuickTime Player publishes a rich scripting `.sdef`. Available calls
relevant to verifiers (confirmed live 2026-05-17 — none of these triggered
a TCC prompt or returned -25211):

```bash
# Count of open documents.
osascript -e 'tell application "QuickTime Player" to get count of documents'

# Front document properties.
osascript -e 'tell application "QuickTime Player" to get name of front document'
osascript -e 'tell application "QuickTime Player" to get duration of front document'      # seconds, float
osascript -e 'tell application "QuickTime Player" to get current time of front document' # seconds, float
osascript -e 'tell application "QuickTime Player" to get playing of front document'      # true/false
osascript -e 'tell application "QuickTime Player" to get POSIX path of (file of front document as alias)'

# Per-document iteration (for tasks that load multiple files).
osascript -e 'tell application "QuickTime Player" to get name of every document'
```

These work because the AppleScript talks **directly** to QuickTime via
Apple Events (the app's own scripting interface), NOT via `System Events`
which is what triggers the TCC trap over SSH. The same pattern works for
any app that publishes a useful `.sdef`: Safari, Mail, Photos, etc.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for window registration
pgrep -x "QuickTime Player" >/dev/null || open -a "QuickTime Player"
for i in $(seq 1 30); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.QuickTimePlayerX"' && break
  sleep 1
done

# Read a pref
defaults read com.apple.QuickTimePlayerX

# Inspect a recorded file
afinfo ~/Movies/Audio\ Recording.m4a
mdls ~/Movies/Movie\ Recording.mov | grep -E 'Duration|Pixel|FSCreationDate'

# Reset for a fresh task
osascript -e 'tell application "QuickTime Player" to quit' 2>/dev/null
pkill -x 'QuickTime Player' 2>/dev/null
rm -f ~/Movies/*.mov ~/Movies/*.m4a ~/Desktop/Screen\ Recording*.mov 2>/dev/null
defaults delete com.apple.QuickTimePlayerX 2>/dev/null || true
```
