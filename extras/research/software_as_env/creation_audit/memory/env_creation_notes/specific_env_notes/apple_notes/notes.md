# Apple Notes on macOS \u2014 Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/apple_notes_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1, Notes
preinstalled at `/Applications/Notes.app` aka `/System/Applications/Notes.app`)

> **See also:** `12_macos_environments.md` for the general macOS env guide;
> `specific_env_notes/safari/notes.md` for Safari's analogous lessons.

---

## Install Story: Trivial

Notes is preinstalled on every macOS image. `install_apple_notes.sh` verifies
the bundle exists at one of two candidate paths and prints the version. On
macOS 15 under the use.computer `base-macos` image the bundle lives at
`/System/Applications/Notes.app` with **no** `/Applications/Notes.app`
symlink \u2014 verified by `ls /Applications/Notes.app` returning ENOENT in the
smoke-run hook log. `open -a Notes` still launches the app because
LaunchServices resolves by bundle ID, but a strict `[ -d /Applications/Notes.app ]`
check under `set -eu` fails. The install hook checks both paths
(`for candidate in /Applications/Notes.app /System/Applications/Notes.app`)
so it succeeds regardless of which layout the image uses. No DMG, no Rosetta,
no brew.

Reset takes ~15-18s on a fresh sandbox (vs ~70s for Google Earth's DMG/Rosetta
install).

---

## Configuration: `defaults write com.apple.Notes`

Useful keys observed in `setup_apple_notes.sh`:

| Key | Type | Purpose |
|---|---|---|
| `NSQuitAlwaysKeepsWindows` | bool | False so quitting Notes during export doesn't leave a ghost window on next launch |
| `NSAutomaticSpellingCorrectionEnabled` | bool | False \u2014 critical, otherwise autocorrect rewrites agent-typed phrases (e.g., "OKR" \u2192 "OK") before the verifier sees them |
| `NSAutomaticDashSubstitutionEnabled` | bool | False \u2014 prevents "$5M" \u2192 "$5\u2014M" surprises |
| `NSAutomaticQuoteSubstitutionEnabled` | bool | False \u2014 keeps straight quotes |
| `NSAutomaticTextReplacementEnabled` | bool | False |
| `DefaultEditorViewSize` | int | 1 (deterministic default editor pane size) |

Unlike Safari, Notes' preferences appear to read directly from the standard
domain \u2014 we did not need to write into a sandbox-container path. `defaults
read com.apple.Notes` reflects the values immediately after `killall cfprefsd`.

---

## State Files

| File | Format | What's in it |
|---|---|---|
| `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` | SQLite + CoreData | The notes database. Notes themselves live in `ZICCLOUDSYNCINGOBJECT` rows. |
| `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite-wal` | SQLite WAL | Write-ahead log; flush with `PRAGMA wal_checkpoint(TRUNCATE)` before copying for verifier reads |
| `~/Library/Containers/com.apple.Notes/Data/Library/Preferences/com.apple.Notes.plist` | Binary plist | Sandbox-mirrored prefs (in practice, prefs from `defaults write` propagate here without extra ceremony, unlike Safari) |

Notes encodes the rich-text body inside a zlib-compressed protobuf blob in
`ZICNOTEDATA.ZDATA`. Decoding it from scratch is painful (no public schema).
For our verifier we sidestep that entirely \u2014 see the AppleScript pattern below.

---

## AppleScript: First-Class Citizen

Apple Notes has a **rich app-scripting interface**. Critically, `tell
application "Notes" \u2026` is direct app scripting (not System Events / AX), so
it works fine over SSH from `sshd-keygen-wrapper` \u2014 no TCC trap (per the
guidance in `12_macos_environments.md`).

Useful idioms used by `create_meeting_agenda/export_result.sh`:

```applescript
-- Count notes by name
tell application "Notes" to return (count of (notes whose name is "Q3 Planning Kickoff"))

-- Get the first matching note's title and body
tell application "Notes" to return (name of item 1 of (notes whose name is "Q3 Planning Kickoff"))
tell application "Notes" to return (body of item 1 of (notes whose name is "Q3 Planning Kickoff"))

-- Enumerate every note + creation date
tell application "Notes"
  set output to ""
  repeat with n in (every note)
    set output to output & (name of n) & character id 9 & \
      ((creation date of n) as \u00abclass isot\u00bb as string) & character id 30
  end repeat
  return output
end tell

-- Make a new note (used in setup helpers and evidence collection)
tell application "Notes" to make new note with properties \
  {name:"Q3 Planning Kickoff", body:"<h1>Title</h1><ul><li>line</li></ul>"}

-- Delete pre-existing notes by name
tell application "Notes"
  set matchingNotes to (notes whose name is "Q3 Planning Kickoff")
  repeat with n in matchingNotes
    delete n
  end repeat
end tell
```

The `body` field is **HTML**. When making a note, you pass HTML and Notes
renders it; when reading, you get the HTML representation back. For
verifiers, stripping tags with a simple `HTMLParser` (stdlib) gives you the
plain text \u2014 see `create_meeting_agenda/export_result.sh`'s `_HTMLToText`
class.

---

## Known Gotchas

### `lsappinfo list | grep -iE 'Notes( |$)'` does NOT match Notes
**Symptom:** the verifier scored 50 / `window_registered=False` even though
Notes was clearly running.

**Root cause:** `lsappinfo list` prints app entries as `"Notes" ASN:0x0-0x3e03e:`
\u2014 the closing `"` immediately follows the name, so the pattern `Notes( |$)`
(expecting a trailing space or EOL) never matches.

The safari_env equivalent (`Safari( |$)`) happens to match because Safari has
helper processes named `Safari Networking`, `Safari Graphics and Media`, etc.,
whose lines contain `Safari ` (with a literal space). Apple Notes has no such
helper, so the pattern falls through. **Do not copy the safari pattern
blindly into a new env \u2014 verify it works against the actual app's process
table.**

**Fix:** match the `bundleID="com.apple.Notes"` line, which is unambiguous
across all use.computer base-macos sandboxes:

```bash
/usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.Notes"'
```

Applied to both the polling loops in `setup_task.sh` and the verifier check
in `launch_apple_notes/verifier.py`.

### Notes' default body includes the title as `<h1>`
**Symptom:** the export's `note_body_text` contains the note title repeated
at the top (e.g., "Q3 Planning Kickoff\nQ3 Planning Kickoff\nHire 3 senior\u2026").

**Why:** when you `make new note with properties {name:..., body:"<h1>X</h1>..."}`,
Notes uses the first line of the body as the displayed title AND keeps the
title field. Reading `body` later returns that `<h1>` wrapper, so the title
appears twice in the plain-text rendering.

This is **not a bug** \u2014 the verifier scores on phrase containment (the
required body lines), and "Q3 Planning Kickoff" being present once or twice
makes no difference. Documented here so future task creators know the body
text shape isn't pristine "exactly what I typed."

### SDK's `keyboard.press(key, modifiers=[...])` silently drops the modifier
**Symptom:** Notes is the frontmost app (`lsappinfo front` returns the Notes
ASN), but `sb.keyboard.press("n", modifiers=["cmd"])` does not open a new
note. No errors; the call returns successfully.

**Probe:** From the interactive_pilot for `create_meeting_agenda`, sending
the same keychord via `sb.keyboard.hotkey("cmd+n")` DID open a new note on
the very next call against the same sandbox \u2014 confirming that the issue is
the `press(\u2026, modifiers=\u2026)` path, not focus or TCC or anything else.

**Workaround:** prefer `keyboard.hotkey("cmd+n")` for any modifier-bearing
chord. `apple_notes_session.py`'s `cmd_key` was patched to route any
`modifiers AND keys` chord to `hotkey()` instead of `press(key,
modifiers=[\u2026])`.

This may affect every macOS env, not just Apple Notes \u2014 worth re-testing
the safari_env probes that use modifier chords for Web Inspector etc.

### `keyboard.press("Return")` does NOT produce a newline in Notes' body
**Symptom:** Typing `"line 1"` + press Return + `"line 2"` results in
`"line 1line 2"` in the note body \u2014 no newline between them.

**Root cause:** This is the same Return-vs-Enter gotcha documented in
`12_macos_environments.md` for Safari's address bar. In Notes' rich-text
editor, `Return` keycode is similarly not interpreted as "insert paragraph
break."

**Workaround:** use `keyboard.type("line1\\nline2")` instead. The SDK's
`type` method converts embedded `\\n` into proper newline keystrokes that
Notes accepts as paragraph breaks. Verified end-to-end in the
interactive_pilot run (see `06_after_typing.png` for the broken state and
`08_after_typing_newlines.png` for the working one).

For tasks that need multiple separate paragraphs, build the body as a single
string with `\\n` between lines and pass it to `keyboard.type` in one call.

### Toolbar coordinate click can hover but not click-through
**Symptom:** Visual grounding returns reasonable pixel coordinates for the
Notes toolbar's "New Note" compose icon, and `sb.mouse.click(x, y)` succeeds
(API returns 200), but the click only surfaces the hover tooltip ("Create a
note") and does NOT create a new note.

**Cause:** unclear. The icon may be in a region where the SDK's mouse click
gets routed as a hover-only event, or the toolbar window is in a special
hit-test state that filters single clicks. Did NOT debug further because:

**Workaround:** use `Cmd+N` via `keyboard.hotkey` (or the File menu via
AppleScript). Both bypass the toolbar-icon click entirely and create a new
note reliably.

This is documented here so future task authors know NOT to base critical
agent actions on Notes-toolbar-icon clicks. Use keyboard shortcuts or
menu-bar paths.

### `«class isot»` ISO date format is local-time and naive
AppleScript's `(creation date of n) as «class isot» as string` returns
`"YYYY-MM-DDTHH:MM:SS"` with no timezone suffix \u2014 it's naive local time.
The export uses `time.mktime(parsed.timetuple())` to convert (which assumes
local time). On the use.computer fleet the VM timezone matches the parsed
date's intended TZ, so this works. If a future image runs in UTC and the
hook script in local-time, this could drift; consider switching to
`do shell script "date \u2026 +%s"` if precision becomes critical.

### Notes app must be RUNNING for export's AppleScript queries
The export script calls `tell application "Notes" to count of notes whose
name is X` \u2014 if Notes isn't running, osascript launches it implicitly, which
takes ~3-5s and may spawn extra notes if onboarding state is incomplete. The
export defensively re-launches Notes if it isn't running before doing
AppleScript queries.

### iCloud sync is absent in the sandbox
There's no iCloud account configured in `base-macos`. All notes land in
"On My Mac" \u2192 default "Notes" folder. The `whose name is X` AppleScript
filter scans across folders anyway, so this doesn't matter for verification.
If a future image preloads an iCloud account, expect a sync delay that could
mask freshly-created notes from the export's first query \u2014 add a 2-3s
post-write settle in the simulator.

---

## End-to-End Verification (live, dev sandbox, 2026-05)

```
launch_apple_notes (smoke):
  reset took ~17s (cold-ish)
  verifier: passed=True, score=100

create_meeting_agenda happy_path:
  reset took ~17s; AppleScript note creation ~1s; export ~3s; verifier ~5s
  verifier: passed=True, score=100 (all four criteria full credit)

create_meeting_agenda do_nothing:
  reset took ~10s; verifier: passed=False, score=0
  feedback: "No evidence of task completion: target note does not exist
             and no notes were created after task start."

create_meeting_agenda wrong_target:
  reset took ~10s; agent created a note with content matching task body
  but wrong title; verifier: passed=False, score=0 (strict gate)
  feedback: "Wrong target: a note was created after task start but its
             title does not match 'Q3 Planning Kickoff'. Found titles:
             ['Random Personal Note']."
```

Evidence package:
`benchmarks/cua_world-macos/environments/apple_notes_env/evidence_docs/`
\u2014 per-flow subdirs with screenshots, hook logs, export JSON, and verifier
result JSON.

---

## What to Watch For When Adding More Tasks

1. **Folder-organization tasks** \u2014 Notes' AppleScript exposes `folders` and
   `account` collections; you can `make new folder with properties {name:"X"}`
   and `move note (...) to folder "X"`. The default account on `base-macos`
   is "On My Mac". The verifier can read folder structure via similar AS
   queries.

2. **Tagging tasks** \u2014 Notes' tag system uses `#tag` in body text. The body
   HTML preserves the `#` chars; the verifier can grep for them. Tags are
   also stored in a separate CoreData entity (`ZTAG`?) but we haven't probed
   that in this env yet.

3. **Pinning tasks** \u2014 `pinned` is a writable boolean property on a note.
   `tell application "Notes" to set pinned of note "X" to true`.

4. **Attachment tasks** \u2014 Notes can hold images, drawings, sketches. The
   `attachments` collection on a note lets the verifier count them, but
   verifying *contents* requires reading the attachment files from
   `~/Library/Group Containers/group.com.apple.notes/Accounts/\u2026/Media/`.

5. **Reset between tasks** \u2014 deleting via AppleScript is reliable but slow
   (each `delete n` causes a separate CoreData transaction). For tasks that
   need a guaranteed-clean slate, an alternative is to wipe the entire
   NoteStore directory in `setup_task.sh` (`rm -rf
   ~/Library/Group\\ Containers/group.com.apple.notes/*`) and then launch
   Notes \u2014 it'll re-create the empty store on first launch. We did not
   need this for `create_meeting_agenda` because the AppleScript delete
   step plus the verifier's strict-title check makes the slate effectively
   clean.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for window
pgrep -x Notes >/dev/null || open -a Notes
for i in $(seq 1 30); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.Notes"' && break
  sleep 1
done

# Read a Notes pref
defaults read com.apple.Notes NSAutomaticSpellingCorrectionEnabled

# Create a note from the CLI
osascript -e 'tell application "Notes" to make new note with properties \
  {name:"Hello", body:"<div>World</div>"}'

# List all note names + creation dates
osascript <<'AS'
tell application "Notes"
  set out to ""
  repeat with n in (every note)
    set out to out & (name of n) & " | " & ((creation date of n) as \u00abclass isot\u00bb as string) & linefeed
  end repeat
  return out
end tell
AS

# Wipe Notes state for a fresh start
osascript -e 'tell application "Notes" to quit'
sleep 2; pkill -x Notes
rm -rf ~/Library/Group\ Containers/group.com.apple.notes/*
```
