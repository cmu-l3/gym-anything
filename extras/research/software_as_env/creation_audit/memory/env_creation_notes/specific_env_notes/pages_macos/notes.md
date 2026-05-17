# Apple Pages on macOS \u2014 Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/pages_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15, Pages 14.5)

> **See also:** `12_macos_environments.md` for the general macOS env guide;
> `specific_env_notes/apple_notes/notes.md` for the sibling Apple-iWork-family
> env (same direct-app-scripting AppleScript pattern), and `safari/notes.md`
> for the `Enter` vs `Return` keyboard-chord finding which carries over here.

---

## Install Story: Trivial

Pages is **preinstalled** on every macOS base image at `/Applications/Pages.app`.
The base-macos sandbox ships Pages 14.5 (bundle id `com.apple.iWork.Pages`).
`install_pages.sh` only verifies the bundle is present and reads its version
\u2014 no DMG, no Rosetta, no Mac App Store install.

Same reset cost as `safari_env` / `apple_notes_env`: ~15-20s on a warm
sandbox.

`/Applications/Keynote.app` and `/Applications/Numbers.app` are also
preinstalled on the same image \u2014 future iWork envs can mirror the pages_env
shape with only the bundle id and AppleScript suite swapped.

---

## The Persistent "New Version of Pages Available" Upgrade Modal

**Symptom:** on every fresh launch of Pages 14.5, a modal dialog appears
covering the document area:

```
[ New Version of Pages Available
  This version will no longer be updated.
  To get the latest features, download Pages 15 or later from the App Store.
  ( Go to App Store ) ( Not Now ) ]
```

Without suppression this dialog blocks every interactive flow and the agent
has to dismiss it manually before each task. Worse, the dialog re-appears
even after dismissal on the next launch.

**Investigation:** `defaults read com.apple.iWork.Pages` surfaces three
related keys:

| Key | What it does |
|---|---|
| `TMAApplicationUpdateNotifier.MigrationAlertToInstallCallCounter` | Number of times the modal has been shown for "Install Pages 15" |
| `TMAApplicationUpdateNotifier.MigrationAlertToUpgradeCallCounter`  | Number of times the modal has been shown for an in-place upgrade |
| `TMAApplicationUpdateNotifier.MigrationAlertToInstallLastShownTimeStamp` | Unix timestamp of the last shown |
| `TMAApplicationUpdateNotifier.MigrationAlertToUpgradeLastShownTimeStamp` | Unix timestamp of the last shown |

**Fix that works** (verified live 2026-05): set all four to high values + flush
`cfprefsd`:

```bash
defaults write com.apple.iWork.Pages "TMAApplicationUpdateNotifier.MigrationAlertToInstallCallCounter" -int 9999
defaults write com.apple.iWork.Pages "TMAApplicationUpdateNotifier.MigrationAlertToUpgradeCallCounter" -int 9999
defaults write com.apple.iWork.Pages "TMAApplicationUpdateNotifier.MigrationAlertToInstallLastShownTimeStamp" -string "9999999999.0"
defaults write com.apple.iWork.Pages "TMAApplicationUpdateNotifier.MigrationAlertToUpgradeLastShownTimeStamp" -string "9999999999.0"
killall cfprefsd
```

After this, Pages launches straight to a usable editor (no modal). Confirmed
with screenshots in `pages_env/evidence_docs/launch_pages/smoke_run/` and
`pages_env/evidence_docs/draft_q3_product_memo/do_nothing/`.

Same Pages instance still shows top-right system Notification Center toasts
("Updates Available", "Tips") for a few seconds after launch. Those are
benign \u2014 they auto-dismiss and don't block input.

---

## Template Chooser Modal: Use AppleScript, Not Keyboard

**Symptom:** Pages on fresh launch shows a "Choose a Template" panel with
preset categories (Basic, Reports, Books, etc.). This is a modal that covers
the document area; clicking the "Blank" template + "Create" button advances
past it.

**Fix:** call `make new document` via AppleScript \u2014 it bypasses the chooser
entirely and creates a blank document directly. Works over SSH because we're
talking to the app (`tell application "Pages"`) rather than walking the AX
tree.

```bash
/usr/bin/osascript -e 'tell application "Pages" to make new document'
```

This is exactly the same pattern as `apple_notes_env` for "open a new note,"
and it's used in both `launch_pages/setup_task.sh` and
`draft_q3_product_memo/setup_task.sh`.

---

## AppleScript Over SSH WORKS for Pages

Verified live: `tell application "Pages"` queries and commands all succeed
over `exec_ssh` \u2014 same exemption as Apple Notes per the
`12_macos_environments.md` "AppleScript / Accessibility over SSH" section.

This is direct app scripting; it doesn't go through `System Events`, so TCC
doesn't block it.

Working commands (probed against the dev fleet 2026-05):

| Command | Returns / Effect |
|---|---|
| `tell application "Pages" to make new document` | New blank doc, returns its `id` |
| `body text of front document` | Plain text of the doc body |
| `set body text of front document to "..."` | Replaces body content |
| `name of front document` | Filename without extension (or "Untitled") |
| `save front document in (POSIX file "/path/to/file.pages")` | Saves; first save may take 5-10s, second-save just commits |
| `export front document to (POSIX file "...") as PDF` | Exports to PDF, also slow (~10s) |
| `close every document saving no` | Closes all docs, discarding unsaved changes |
| `tell application "Pages" to quit saving no` | Quits the app |

**Heads up on `save` timeouts:** the SDK's `exec_ssh` default timeout is 60s,
which is sometimes tight for Pages's first save (it has to materialize the
.pages package directory + index files). The HTTP response can time out even
when the save itself succeeds \u2014 the file ends up on disk anyway. Be liberal
with timeouts when invoking `save` from a host-side test.

---

## `body text` Property: Plain Text, Bullets Flattened

`body text of front document` returns the document's text content as plain
text. List bullets, headers, and other formatting are stripped. Useful for
phrase-presence verifiers \u2014 the verifier just substring-matches against
the returned text.

For richer queries (e.g., "is this line bulleted?") you'd need to read the
.pages package directly. Modern Pages stores the doc as a directory bundle
with `Index.zip` (XML inside) and binary index files. `strings` over the
package surfaces text content but not formatting.

For the draft_q3_product_memo task this is plenty: the verifier checks for
phrase substrings, not formatting.

---

## Filename in Save Dialog: `Enter`, Not `Return`

Same gotcha as Safari (`12_macos_environments.md` "Keyboard Enter \u2260 Return"
section), but Pages-specific reproduction in
`evidence_docs/draft_q3_product_memo/interactive_pilot/`:

After typing a filename in the Save dialog's "Save As:" field, pressing
`Return` does NOT trigger the default Save button \u2014 the dialog stays up
unchanged. Pressing `Enter` triggers Save and the file is committed to disk.

```python
sb.keyboard.press("Return")  # \u2718 dialog stays open
sb.keyboard.press("Enter")   # \u2713 Save button activates, file is saved
```

This is consistent with the Safari finding \u2014 macOS apps' default-button
activation responds to the `Enter` keycode, not the `Return` keycode (in some
SDK->macOS keycode mappings the two are distinct). Use `Enter` for any
"submit / OK / Save" default action in macOS dialogs driven by
`use_computer.keyboard.press`.

---

## `Return` Inside Document Body: Doesn't Insert Newline (sometimes)

A second `Enter` vs `Return` finding, in the Pages document body specifically:
when typing into the body, pressing the `Return` keycode (via
`sb.keyboard.press("Return")`) doesn't insert a newline in some sequences.
Pages keeps everything on one line until you intersperse `Enter` instead.

Observed in `evidence_docs/draft_q3_product_memo/interactive_pilot/02_after_typing.png`:
the four typed phrases concatenated onto a single soft-wrapped line because
the three `Return` chords between them were no-ops in Pages's text view.

**Impact on the task:** the verifier substring-matches against the body text,
so concatenated content still scores 100/100 (confirmed: the
interactive_pilot run got the full 100 score with one-line content). The
agent doesn't need newlines to pass.

**Open finding:** the `Return` no-op may be timing-related (the keyboard
chord lands before Pages has refocused the doc after a click) rather than a
hard Pages constraint \u2014 `Return` worked for paragraph breaks in offline
probes when typed via `sb.keyboard.type("foo\\nbar")`. Worth investigating
further if a task needs strict paragraph breaks.

---

## State Files for Verifier Strategy

For verifiers, prefer **AppleScript over file-based reads** for Pages \u2014
unlike Safari or Notes, the .pages package format is binary/proprietary
(zipped XML with binary indexes) and `strings` only surfaces text loosely.
But AppleScript provides clean reads:

| Read this... | ...with AppleScript |
|---|---|
| Body text of an open doc | `tell application "Pages" to return body text of front document` |
| Body text of a specific saved doc | `tell application "Pages" to return body text of document "MyDoc"` (assuming it's open) |
| List of open docs | `tell application "Pages" to return name of every document` |
| Doc's saved file path | `tell application "Pages" to return path of front document` |

**Fallback: `strings` on the .pages bundle.** Useful when the doc has been
saved-and-closed (so AppleScript can't read it). Modern Pages 14+ stores the
doc as a directory at `<basename>.pages/` with internal `Index.zip`,
`Index/Document.iwa`, etc. Running `strings` over the package surfaces typed
text in a noisy form \u2014 enough for substring matching.

The `draft_q3_product_memo` export script does both: AppleScript first, then
falls back to `strings` if AppleScript came back empty AND the file exists.

---

## Save Path: `~/Documents`, And the Save Dialog Defaults to It

Pages 14.5's first Save dialog defaults to `~/Documents` as the destination
folder, which means the agent doesn't need to navigate the file picker to
get to the task's expected save location. This makes `~/Documents/<filename>.pages`
a low-friction task target.

Note: `~/Documents/.localized` exists on the base image (an empty marker
file used by macOS's folder localization). It's harmless and the `find
-name '*.pages'` scan in `setup_task.sh` filters it out automatically.

---

## Cold Start Cost

Reset breakdown for the pages_env (smoke task, fresh sandbox):

| Step | Time |
|---|---|
| sandbox provision | ~22s |
| workspace mkdir + upload mounts | ~7s |
| `pre_start` (verify bundle) | <1s |
| `post_start` (set prefs + cfprefsd flush) | ~2s |
| `pre_task` (open Pages + `make new document`) | ~5s |
| obs capture, session info, etc. | ~3s |
| **total** | **~40s** |

For the operational task `draft_q3_product_memo`, add ~5-10s for the
pre-snapshot of `~/Documents` and the .pages-file deletion. Total still
under 60s on a warm fleet.

---

## End-to-End Verification (live, dev sandbox, 2026-05)

Five flows captured under `pages_env/evidence_docs/`:

| Flow | Score | Pass | Mechanism |
|------|-------|------|-----------|
| `launch_pages/smoke_run` | 100/100 | yes | pgrep + lsappinfo, no agent action |
| `draft_q3_product_memo/do_nothing` | 0/100 | no | do-nothing gate |
| `draft_q3_product_memo/wrong_target` | 0/100 | no | wrong-target gate (other .pages saved) |
| `draft_q3_product_memo/happy_path` | 100/100 | yes | AppleScript-scripted save at target path |
| `draft_q3_product_memo/interactive_pilot` | 100/100 | yes | full UI drive: click + type + Cmd+S + Enter-as-default-button |
| `draft_q3_product_memo/interactive_pilot_mcp` | 100/100 | yes | full UI drive using MCP visual_grounding for click coords (click + type + Cmd+S + click-Save-button) |

The `interactive_pilot_mcp` is the most agent-faithful: every click was
sited by `mcp__visual-grounding__visual_grounding` against a fresh
screenshot, then dispatched via `keyboard.type` / `mouse.click` against the
sandbox. The full path \u2014 click body \u2192 type 4 phrases \u2192 Cmd+S \u2192 type
filename \u2192 click yellow Save button \u2014 succeeded and scored 100/100.

---

## visual_grounding MCP Tool: Coordinate Space Gotcha

The `screenshot_query_mcp` server's system prompt instructs the VLM to
return coordinates "in 1280x720 scale" and the tool description repeats
the same. **Empirically (this env, gemini-3-flash-preview, 2026-05) the
coordinates returned for clicks on a 1920x1080 screenshot were actually in
the source-image pixel space (1920x1080), NOT 1280x720-normalized.**
The fixed boilerplate `NOTE: Any coordinates above are in 1280x720 scale`
in the response is appended regardless of what the model actually returned.

Practical impact for `pages_env/interactive_pilot_mcp/`:
- Doc-body click MCP returned `(424, 501)` \u2014 happened to also be in the
  body's 1280-space and within the body in 1920-space (the body is large).
- Save-button click MCP returned `(1114, 556)`. When scaled `--from1280`
  to `(1671, 834)`, the click missed the dialog and hit the Finder
  desktop. When dispatched as a raw display-pixel coordinate `(1114, 562)`,
  the click landed on the Save button and triggered save.

**Rule of thumb:** trust the MCP tool's coordinate as a raw pixel value
against the screenshot it analyzed. Don't apply a 1280-to-display scale on
top, even though the tool description says to. If the screenshot is
already 1920x1080 (which use.computer's `screenshot.take_full_screen()`
returns), the MCP output is in 1920x1080.

This is a per-model quirk \u2014 it may differ if `SCREENSHOT_QUERY_MODEL` is
swapped to a non-Gemini provider. Always verify with one probe click
before relying on the coordinates for a long pilot.

---

## System Notification Banners (audit finding, partially fixed)

On every fresh use.computer macOS sandbox boot, two persistent Notification
Center banners appear in the top-right corner:

1. **"Updates Available \u2014 Do you want to install these updates tonight?"**
   with `Install Tonight` / `Remind Me Later` buttons. Posted by macOS
   Software Update daemon (`softwareupdated`).
2. **"Tips Notification"** \u2014 small banner posted by `com.apple.tips`.

Neither obstructs the Pages document area (they sit in the top-right and
the document is centered) but they appear in every screenshot, which is
visually distracting in evidence packages.

**Programmatic suppression in `setup_pages.sh`** (added 2026-05):

```bash
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
defaults write com.apple.SoftwareUpdate AutomaticDownload -bool false
defaults write com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
defaults write com.apple.SoftwareUpdate ConfigDataInstall -bool false
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -bool false
defaults write com.apple.tips ShowTips -bool false

killall NotificationCenter 2>/dev/null || true
killall usernoted 2>/dev/null || true
```

This **fully suppresses the Software Update banner on subsequent boots** \u2014
verified live: a fresh sandbox after `setup_pages.sh` only shows the Tips
banner, not the Updates Available one.

**The Tips banner remains on the first boot** because the notification was
already queued by macOS before the hook ran. The defaults prevent FUTURE
Tips notifications but don't dismiss the already-queued one. Manual
dismissal (right-click the Tips banner \u2192 Turn Off) is reliable and was
done for the evidence package. The Turn Off action writes a flag in
`~/Library/Preferences/com.apple.ncprefs.plist` (the `flags` integer for
`com.apple.tips`), which persists across reboots only if the same user
profile is preserved. Since each use.computer sandbox is fresh, this needs
to happen once per sandbox.

**Recommended pattern for porting to other iWork envs**: include the same
`defaults write` block in `setup_<app>.sh`. If you need fully-clean
screenshots at evaluation time, drive the Tips right-click \u2192 Turn Off
dismissal via the SDK mouse APIs after `env.reset()` returns but before
the agent's first step. Both surfaces can be located via the MCP
`visual_grounding` tool; the Tips banner consistently appears centered
around (1730, 80) in 1920x1080 and the Turn Off context menu item at
(1810, 160).

The **agent's task completability is unaffected** by either banner. All
five draft_q3_product_memo evidence flows score as expected (do_nothing 0,
wrong_target 0, happy_path 100, interactive_pilot 100, interactive_pilot_mcp
100) whether the Tips banner is present or dismissed.

---

## `screencapture -x` From SSH Misses the Pages Window

**Symptom**: calling `/usr/sbin/screencapture -x /tmp/task_start.png` from
inside a setup_task.sh / export_result.sh (which runs over SSH from the
runner) captures only the wallpaper + macOS menu bar \u2014 the Pages window
frame is absent, even when `pgrep -x Pages` and `lsappinfo` confirm the
app is running and the window is registered.

By contrast, `sb.screenshot.take_full_screen()` from the use.computer SDK
renders the full screen including all app windows correctly.

**Root cause**: SSH-context screencapture and SDK screenshot use different
rendering paths. The SSH-launched `screencapture` is responsibility-rooted
in `sshd-keygen-wrapper` and only sees what its session can capture, which
omits the windowserver-composed app frames. The SDK path goes through the
use.computer agent's own rendering channel which sees the full screen.

**Fix**: Don't use `/usr/sbin/screencapture` in hook scripts. Let the
SDK-side per-step `panel_view*.png` be the authoritative trajectory
artifact instead. `apple_notes_env/tasks/create_meeting_agenda/setup_task.sh`
already documented this; `pages_env`'s setup_task.sh + export_result.sh
mirror the skip.

This is a per-app quirk too: safari_env's setup_task.sh calls
`screencapture -x` and that one DOES capture the Safari window. So it
seems to depend on the app's renderer (Safari uses WebKit's compositor,
Pages uses TPM/iWork's). When porting other iWork apps (Keynote, Numbers),
expect the same SSH-screencapture skip is needed.

---

## MCP Server Setup (.env required)

The visual-grounding MCP server (configured in
`/Users/pranjal/Developer/gym-anything2/.mcp.json`) reads its API key from
a sibling `.env` at `extras/research/software_as_env/creation_audit/mcp/.env`
\u2014 NOT the repo-root `.env`. The fallback chain inside
`screenshot_query_mcp.py` calls `load_dotenv(Path(__file__).parent / ".env")`
at import time. If that file is missing the provider key, the MCP tool
fails at first call with:

```
Error: Missing credentials. Please pass an `api_key`, ... or set the
OPENAI_API_KEY or OPENAI_ADMIN_KEY environment variable.
```

**Setup once per machine** (the `.env` is gitignored):

```bash
cp extras/research/software_as_env/creation_audit/mcp/.env.example \
   extras/research/software_as_env/creation_audit/mcp/.env
# Then edit to fill in GEMINI_API_KEY (or DATABRICKS_TOKEN / OPENAI_API_KEY).
```

The MCP server is launched once at Claude Code session start; if you
update the .env mid-session you must kill the existing server PIDs so
Claude Code respawns it:

```bash
pkill -f screenshot_query_mcp.py   # next MCP call respawns with new env
```

---

## Quick-Reference Commands

```bash
# Launch idempotently, wait for window, open a blank doc (skips template chooser)
pgrep -x Pages >/dev/null || open -a Pages
for i in $(seq 1 30); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.iWork.Pages"' && break
  sleep 1
done
osascript -e 'tell application "Pages" to make new document'

# Set body text
osascript -e 'tell application "Pages" to set body text of front document to "Hello, Pages"'

# Save document (slow first time \u2014 give it 60s+)
osascript -e 'tell application "Pages" to save front document in (POSIX file "/Users/lume/Documents/MyDoc.pages")'

# Export to PDF
osascript -e 'tell application "Pages" to export front document to (POSIX file "/Users/lume/Documents/MyDoc.pdf") as PDF'

# Quit cleanly (don't trip "User canceled" on unsaved docs)
osascript -e 'tell application "Pages" to quit saving no'

# Inspect a .pages bundle (modern format is a directory; strings surfaces body)
find "/Users/lume/Documents/MyDoc.pages" -type f -exec strings {} +
```

---

## What to Watch For When Porting Tasks

1. **Save-as flow**: most realistic Pages tasks involve a Save Dialog. The
   default folder is `~/Documents`, default filename is "Untitled". Agent
   needs to type the new filename then submit with `Enter` (not `Return`).

2. **Export flow**: similar to save-as. Pages supports export to PDF, Word
   (.docx), EPUB, plain text, RTF, and Pages-09. Use AppleScript's `export`
   command from a verifier or task setup if you need a deterministic export.

3. **Multi-document state**: if a task has the agent work across multiple
   open documents, `tell application "Pages" to count documents` and
   `document <name>` are clean reads. Filter by `name` to find the agent's
   target.

4. **Body content vs formatting**: `body text` strips formatting. If a task
   needs to verify "the agent applied bold to this phrase," you have to read
   the .pages bundle's internal index XML (non-trivial). For phrase-presence
   tasks (the simpler 80% case), `body text` is fine.

5. **Autocorrect rewrites**: Pages reads `NSAutomatic*` keys from
   NSGlobalDomain (not just from its own pref domain). `setup_pages.sh`
   disables them at the global level so phrases like `"$5M"`, `"NPS from 42
   to 55"`, `"30%"` aren't silently rewritten by smart-text substitution.

6. **First-launch dialogs**: the upgrade modal is the big one; if it's not
   suppressed, every task pre_task has to dismiss it. Don't skip the
   `TMAApplicationUpdateNotifier.*` writes in setup_pages.sh.
