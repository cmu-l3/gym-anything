# Raycast on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/raycast_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1)

> **See also:** `12_macos_environments.md` for the general macOS env guide,
> `specific_env_notes/notion_macos/notes.md` for the closest analogue
> (universal-binary DMG + drag-and-drop .app), and
> `specific_env_notes/safari/notes.md` for the preinstalled-app baseline.

---

## Install Path (working as of 2026-05-17)

**DMG URL that works:** `https://www.raycast.com/download`
— 308-redirects to `https://releases.raycast.com/download`
— 302-redirects to `https://worker.raycast-releases.com/?url=…` which signs a
Cloudflare R2 URL serving `Raycast.dmg` (currently `Raycast_v1.104.17_…_universal.dmg`).
Honoring redirects (`curl -fL`) means the install script doesn't need to know
the current version.

**Shape:** The DMG contains a **drag-and-drop `Raycast.app` bundle** (Pattern
A from `12_macos_environments.md`) — NOT a .pkg installer. `install_raycast.sh`
defensively probes for both shapes; today's path is `ditto`.

**Universal binary — no Rosetta needed.** `Raycast.app` Mach-O slices include
arm64, so Apple Silicon (the use.computer fleet) runs it natively. Skip the
Rosetta-install gate from `12_macos_environments.md`.

**Total cold install time:** ~7s on dev fleet (probed 2026-05-17):
- DMG download: ~1.5s (105 MB at ~138 MB/s sustained from Cloudflare)
- hdiutil attach + ditto + detach + lsregister: ~3-4s

---

## `lsregister -f` is needed after install (matches Notion finding)

Same root cause as `specific_env_notes/notion_macos/notes.md`: after
`ditto`-ing the app into `/Applications`, LaunchServices hasn't yet indexed
the new bundle, so `open -a Raycast` may fail with "Unable to find application
named 'Raycast'". `install_raycast.sh` calls `lsregister -f /Applications/Raycast.app`
to force a synchronous re-scan.

The smoke launch hook also has a defensive fallback that opens by absolute
bundle path if `open -a` still fails:

```bash
if ! open -a "Raycast" 2>/dev/null; then
  open /Applications/Raycast.app
fi
```

In practice on a fresh sandbox after `lsregister -f`, the `open -a "Raycast"`
path works directly.

---

## Raycast is NOT sandboxed — prefs live at the standard path

Unlike Safari (which runs out of `~/Library/Containers/com.apple.Safari/…`
under an App Sandbox profile), Raycast preferences live at the standard
unsandboxed paths:

```
~/Library/Preferences/com.raycast.macos.plist            (binary plist)
~/Library/Application Support/com.raycast.macos/          (SQLite + JSON state)
~/Library/Caches/com.raycast.macos/                       (cache)
```

`~/Library/Containers/com.raycast.macos` does **not** exist after install.
That means:

- `defaults write com.raycast.macos <key> <value>` writes to the path Raycast
  actually reads.
- `defaults read com.raycast.macos` reports real values (probed live, see
  "End-to-End Verification" below).
- No `killall cfprefsd` is required for prefs writes to surface — pref reads
  during launch hit the same path the writes target.

This contrasts with Safari, where `defaults write` to the standard path is
ignored by the sandboxed Safari process; see
`specific_env_notes/safari/notes.md` "Sandbox / Develop menu" section.

---

## Single-process app, no helpers

After `open -a Raycast`, only **one** process is running:

```
501 11008 1   0  1:36PM ??   0:02.98 /Applications/Raycast.app/Contents/MacOS/Raycast
```

No `Raycast Helper`, no `Raycast Helper (GPU)`, no `Raycast Networking`.
This is unlike Notion (an Electron app, ships ~5 helpers per session) and
Safari (Networking + Web Content + extensions helpers).

**Implications for the verifier:**
- `pgrep -x 'Raycast'` cleanly returns the single PID.
- `lsappinfo list | grep -iE 'Raycast'` returns the main app's entry
  (`bundleID="com.raycast.macos"`, `bundle path="/Applications/Raycast.app"`,
  no helper rows to inflate the count).
- The smoke verifier uses `grep -iE 'Raycast\.app'` for the bundle-path line,
  per the helper-free pattern from
  `specific_env_notes/preview/notes.md` and the "lsappinfo Regex" section of
  `12_macos_environments.md`. (Word-boundary `Raycast( |$)` would also work
  here, but the bundle-path match is more robust to future helper additions.)

---

## First-launch state: microphone TCC dialog + onboarding window

On the very first launch in a fresh sandbox (probed 2026-05-17), Raycast shows:

1. **A dark center "main window"** — empty, no foreground content visible
   behind the modal.
2. **A modal TCC consent dialog** layered on top: title `"Raycast" would like
   to access the microphone`, body `Raycast needs access to your Microphone
   to transcribe audio for translation`, buttons `Don't Allow` / `Allow`.
   This is macOS's TCC framework asking before Raycast is granted
   `kTCCServiceMicrophone`.
3. **Two stacked notifications top-right**: `Login Items / Notification` and
   `Tips / Notification`. Raycast registers itself as a login item on first
   launch (per the `raycastLoginItemAutoInstalled` pref); the notifications
   are macOS's UserNotifications framework surfacing those events.
4. **The Dock** has the Raycast hand icon next to the trash; Finder remains
   menu-bar-active because the microphone dialog has stolen modal focus.

**Evidence:**
`benchmarks/cua_world-macos/environments/raycast_env/evidence_docs/launch_raycast/interactive_pilot/launch_raycast_panel_view.png`.

**Implications for task design:**
- The microphone TCC dialog blocks any input that isn't a click on its two
  buttons. Tasks that need to drive the Raycast UI directly from the
  interactive panel must dismiss it first — `Don't Allow` is at approximately
  (449, 196) in 1280-grounding space, or (~ 673, 294) in 1920x1080 display
  space. Alternatively, future tasks can pre-grant `kTCCServiceMicrophone`
  to the Raycast bundle ID via TCC.db surgery (out of scope for the smoke
  task; documented for future tasks that need microphone access).
- The Login Items prompt does **not** block input — it's a non-modal banner
  in the top-right corner.
- The smoke verifier is not sensitive to the TCC dialog (it checks process +
  LaunchServices state, not window focus), so the dialog's presence does not
  affect `launch_raycast` scoring.

---

## Cmd+Space (Raycast's default hotkey) is broken in base-macos

Raycast's onboarding wants the user to assign a global hotkey; the most
common choice is **Cmd+Space** (replacing Spotlight). But the use.computer
base-macos sandbox image does NOT respond to the Cmd+Space chord at all
(documented across 4+ probes in `12_macos_environments.md` "Cmd+Space
(Spotlight) Does Not Open Spotlight"). The chord is silently dropped at the
input dispatch layer.

**Practical implications for task design:**
- Don't design Raycast tasks that require invoking the command palette via
  Cmd+Space. Even if Raycast were assigned that hotkey, the chord never fires.
- Use `open -a Raycast` from a SSH-driven Terminal to launch the menu-bar
  agent process (this is what `setup_task.sh` does for the smoke task).
- For tasks that need to open Raycast's command palette window from the
  GUI, options include:
  - Click the Raycast hand icon in the menu bar (visual_grounding from
    a screenshot).
  - Set Raycast's hotkey to a non-Cmd+Space chord (e.g., `Alt+Space` =
    Option+Space) during the agent flow, then invoke via `keyboard.hotkey(
    "alt+space")` — note `keyboard.hotkey` works for chords with modifiers,
    `keyboard.press(..., modifiers=[...])` silently drops them per
    `specific_env_notes/notion_macos/notes.md` "Keyboard chord behavior".
  - Use Raycast's URL scheme: `open raycast://<command-path>` from SSH.
    This bypasses the hotkey entirely.

---

## State files (verifier-friendly)

After Raycast has launched at least once, the following state files exist
and can be read from a TCC-free verifier (no AX, no AppleScript-over-SSH):

| Path | Format | What's in it |
|---|---|---|
| `~/Library/Preferences/com.raycast.macos.plist` | Binary plist | The `defaults` domain. Has e.g. `database_lastValidAppVersion`, `raycastInstallationDate`, `raycastAnonymousId`, `mainWindow_isMonitoringGlobalHotkeys`, `subscriptions_active`. Read via `defaults read com.raycast.macos` or Python's `plistlib`. |
| `~/Library/Application Support/com.raycast.macos/raycast-enc.sqlite` | SQLite (encrypted) | Main store (commands, snippets, extension data). Schema is encrypted — verifiers can check file mtime / size deltas but not contents. |
| `~/Library/Application Support/com.raycast.macos/raycast-activities-enc.sqlite` | SQLite (encrypted) | Activity log (commands run, history). Mtime delta after task ≈ "agent did something in Raycast". |
| `~/Library/Application Support/com.raycast.macos/raycast-emoji.sqlite` | SQLite (encrypted) | Emoji picker state. |
| `~/Library/Application Support/com.raycast.macos/NodeJS/` | Files | NodeJS runtime that Raycast ships for running extensions. Existence + mtime indicate extension activity. |
| `~/Library/Application Support/com.raycast.macos/posthog.queueFolder/` | Files | Telemetry queue. New files appear when Raycast records events. |
| `~/Library/Caches/com.raycast.macos/` | Binary cache | Standard NSURLCache + bundle caches. |

**Useful `defaults read com.raycast.macos` keys observed live:**

| Key | Type | Meaning |
|---|---|---|
| `database_lastValidAppVersion` | string | Last-seen app version (e.g. "1.104.17") |
| `database_lastValidOSVersion` | string | Last-seen OS version (e.g. "15.4.1") |
| `raycastInstallationDate` | date | First-launch timestamp |
| `raycastFirstKnownAppVersion` | data (JSON string) | First-installed version |
| `raycastLoginItemAutoInstalled` | date | When Raycast registered itself as a login item |
| `raycastShouldFollowSystemAppearance` | bool | Light/dark mode follows system |
| `mainWindow_isMonitoringGlobalHotkeys` | bool | True after a hotkey is bound |
| `subscriptions_active` | bool | True iff a Raycast Pro / Team plan is active |
| `floatingNotes_didCreateOnboardingNote` | bool | Set after onboarding completes |
| `onboarding_showTasksProgress` | bool | True while onboarding tasks are still in progress |
| `useHyperKeyIcon` | bool | UI customization |

Since Raycast is NOT sandboxed, `defaults write com.raycast.macos <key>
<value>` reliably updates the live file (unlike Safari's container path
detour). No `killall cfprefsd` is required.

**Verifiers that don't need encrypted-SQLite content** can rely on
plist-level signals (e.g., `mainWindow_isMonitoringGlobalHotkeys == True`
indicates an agent successfully bound a hotkey via the Settings UI).

---

## Authentication / sign-in not required for basic launcher

Raycast can be used without signing in — the launcher's core (open apps,
file search, calculator, clipboard history, snippets, system commands)
works locally. Pro features (AI chat, sync across devices, custom themes,
window management) are gated on a Pro subscription, but those don't surface
without explicit user interaction.

The first-launch onboarding window asks users to sign in or skip; the
skipped path lands in the main launcher UI. This means **agent tasks
operating on the local launcher don't need shared credentials**, unlike
Notion (which is gated on sign-in for almost every workflow — see
`specific_env_notes/notion_macos/notes.md` "Authentication blocks 99% of
in-app workflows").

---

## End-to-End Verification (live, dev sandbox, 2026-05-17)

```
reset() takes ~17s on the use.computer dev fleet:
  pre_start (install_raycast.sh): ~7s (105 MB DMG + ditto + lsregister)
  post_start (setup_raycast.sh):  ~1s (mkdir state dirs)
  pre_task   (setup_task.sh):     ~6s (open + 1s lsappinfo poll + 4s settle)
```

Live flows of `launch_raycast`:
- `interactive_pilot/`  →  100/100  (process_running=True (pid 11008);
                                     window_registered=True)

Live flows of `raycast_trigger_and_capture` (one fresh sandbox each):
- `do_nothing/`     →  0/100   (anti-gaming gate fires; agent took no
                                action, no screenshot saved, WAL delta=0)
- `wrong_target/`   →  0/100   (strict wrong-target gate fires; agent
                                ran `screencapture` directly but never
                                invoked any Raycast URL; WAL delta=0
                                while screenshot exists)
- `happy_path/`     →  100/100 (Terminal Dock click via
                                visual_grounding + AppleScript do-script
                                to run `open raycast://extensions/...`,
                                then `screencapture -x`; WAL grew 177 KB)

Offline mock tests:
- `launch_raycast`: 4/4 (do-nothing, partial, defensive anomaly, full launch).
- `raycast_trigger_and_capture`: 9/9 (do-nothing, two wrong-target variants,
  three partial-credit variants, full-correct, two threshold edge cases).

Evidence at `benchmarks/cua_world-macos/environments/raycast_env/evidence_docs/launch_raycast/interactive_pilot/`:
- `launch_raycast_panel_view.png` — the screenshot the noVNC viewer would
  show at the moment the interactive panel appears.
- `panel_view_final.png` — final screenshot captured by `finalize` after
  the verifier was called (identical to panel view — verifier is read-only).
- `verifier_result.json` — `{"passed": true, "score": 100, "feedback":
  "process_running=True (pids: 11008); window_registered=True"}`.
- `env_setup_pre_start.log`, `env_setup_post_start.log`, `task_pre_task.log`
  — hook stdout/stderr captured during boot.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for LaunchServices registration
pgrep -x Raycast >/dev/null || open -a Raycast || open /Applications/Raycast.app
for i in $(seq 1 45); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qE 'Raycast\.app' && break
  sleep 1
done

# Read Raycast's defaults (works directly — Raycast is not sandboxed)
defaults read com.raycast.macos

# Inspect Raycast's app data
ls -la ~/Library/Application\ Support/com.raycast.macos/

# Open a Raycast URL scheme (bypasses Cmd+Space hotkey, which is broken in
# the sandbox). Examples:
open "raycast://extensions/raycast/system/lock-screen"
open "raycast://extensions/raycast/system/empty-trash"

# Force-quit Raycast (e.g., to reset for the next task)
pkill -x Raycast
rm -rf ~/Library/Application\ Support/com.raycast.macos
rm -f ~/Library/Preferences/com.raycast.macos.plist
```

---

## URL-scheme behavior (probed 2026-05-17)

Two flavors of `raycast://` URLs exist, with very different observable effects:

### Visible-only URLs (no activity logging)

`raycast://confetti` is an Easter egg keyword. Sending `open 'raycast://confetti'`
from Terminal makes Raycast briefly render colorful confetti pieces over the
desktop (confirmed visually — see
`benchmarks/cua_world-macos/environments/raycast_env/evidence_docs/raycast_trigger_and_capture/`).
But Raycast does NOT log this trigger to `raycast-activities-enc.sqlite-wal`,
does NOT add a posthog event, does NOT modify any other state file. The
activity-log directory contents are byte-identical before and after.

**Implication**: don't use `raycast://confetti` (or similar pure-UI URLs) as
the trigger in tasks that verify via filesystem state. The agent's URL would
fire correctly but the verifier would see no evidence.

### Logged URLs (extension-path scheme)

`raycast://extensions/<author>/<extension>/<command>` URLs DO log:

```bash
open 'raycast://extensions/raycast/clipboard-history/clipboard-history'
```

This triggers (a) Raycast intercepting the URL and showing a "Request to run
Clipboard History — The command was triggered from outside of Raycast.
[Run Command] [Always Run Command] [Cancel]" confirmation dialog, and (b)
**immediately writes ~177 KB to `raycast-activities-enc.sqlite-wal`** (the
file is *created* by this write — it does not exist on a fresh sandbox until
Raycast logs an activity). Plus a new event JSON in
`~/Library/Application Support/com.raycast.macos/posthog.queueFolder/`.

**The activity log write happens BEFORE the confirmation dialog**, so a
verifier that checks WAL size delta does not need the agent to dismiss the
dialog — the trigger evidence is already on disk.

**Verifier signal recommendation**: check `raycast-activities-enc.sqlite-wal`
size delta against a baseline recorded in `setup_task.sh`. Use a threshold
of ~1024 bytes to filter background ticks (probed at 0-228 bytes in
do-nothing / wrong-target flows) while reliably catching logged URL
triggers (177 KB on first invocation, ~5 KB on subsequent).

### Raycast's external-trigger security prompt

When a URL is triggered from outside the Raycast process tree (e.g. via
`open ...` from Terminal), Raycast shows a confirmation dialog before
executing the command. The dialog is modal but does NOT block other apps
(only Raycast's command flow). Crucially, the activity-log entry is
recorded *before* the dialog appears, so disk-based verifiers don't depend
on dismissing it. Tasks that need the URL's full effect (e.g. a UI side
effect of the command itself) DO need the agent to click "Run Command" or
"Always Run Command".

`raycast://` URLs invoked from inside Raycast (e.g. from one extension to
another) do NOT trigger the prompt — but agents in this env can't reach
that path without first dismissing the onboarding flow, so for tasks today
the external-trigger prompt is the realistic experience.

---

## Open Investigations (not blocking the smoke task)

1. **Pre-grant `kTCCServiceMicrophone` to com.raycast.macos** so the
   microphone TCC dialog doesn't block first-launch interaction. Would
   need to insert a row into `~/Library/Application Support/com.apple.TCC/TCC.db`
   with `service=kTCCServiceMicrophone, client=com.raycast.macos,
   client_type=0, auth_value=2`. Probably blocked by macOS SIP — `TCC.db`
   is read-only without disabling SIP. Acceptable workaround: an
   `interactive_pilot/setup` step that clicks `Don't Allow` on the dialog
   before any task work starts.

2. **Bind a non-Cmd+Space hotkey for Raycast** so tasks that need to invoke
   the command palette have a working chord. Could be done in `setup_raycast.sh`
   by writing to the `com.raycast.macos.plist` (key name unknown — observed
   keys don't obviously expose the hotkey-binding pref). Alternative: drive
   the binding through the Settings UI during pre_task.

3. **Extension installation pipeline**. Raycast's extensions are downloaded
   from the Raycast Store; installing one requires a Raycast account or at
   least an authenticated `raycast.com` cookie. Out of scope for offline /
   credential-free task design today.
