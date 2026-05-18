# `raycast_trigger_and_capture`

## Task

Trigger Raycast through its URL-scheme deep link from Terminal, then
capture a fresh screenshot proving the action took place. The deliverable
is a screenshot at `/Users/lume/Desktop/raycast_screenshot.png` that
satisfies all of:

1. The file exists.
2. Its modification time is after `task_start`.
3. It carries the `com.apple.metadata:kMDItemIsScreenCapture` xattr,
   proving it was written by `/usr/sbin/screencapture`.

In addition, Raycast's encrypted activity SQLite WAL
(`~/Library/Application Support/com.raycast.macos/raycast-activities-enc.sqlite-wal`)
must grow by at least 1 KB after `task_start`, proving Raycast was actually
triggered (background ticks alone fall well under this threshold).

## Domain context

Raycast is a macOS productivity launcher with first-class
`raycast://` URL-scheme integration. Two flavors of URL exist:
- **Easter-egg keywords** like `raycast://confetti` produce a visible
  UI effect but DO NOT log to the activity database (probed live
  2026-05-17 — confetti animation rendered but `raycast-activities-enc.sqlite-wal`
  was unchanged).
- **Extension paths** like `raycast://extensions/<author>/<extension>/<command>`
  produce a logged activity event — the activity SQLite WAL grows by
  ≥100 KB on first invocation in a fresh sandbox.

This task therefore directs the agent at the canonical
`raycast://extensions/raycast/clipboard-history/clipboard-history` URL,
which both shows a visible UI (the Clipboard History panel) AND triggers
a logged activity event the verifier can detect.

This task exercises the URL-scheme path (rather than the launcher hotkey,
which is broken in the use.computer sandbox — see
`specific_env_notes/raycast_macos/notes.md` "Cmd+Space (Raycast's default
hotkey) is broken in base-macos").

## Verification (100 pts, pass at 60)

| # | Criterion | Pts | Source |
|---|---|---|---|
| C1 | Screenshot exists at deliverable path | 15 | `os.path.isfile` |
| C2 | Screenshot mtime > task_start | 15 | `os.stat().st_mtime` |
| C3 | Screenshot carries `kMDItemIsScreenCapture` xattr | 20 | `xattr -px` + `plistlib` |
| C4 | Raycast activity WAL grew ≥ 1024 B | 50 | size delta vs pre_task snapshot |

### Anti-gaming gates (fired before scoring)

- **Do-nothing**: NOT C1 AND NOT C4 → 0. (No screenshot AND no Raycast
  activity beyond background ticks.)
- **Wrong-target**: C1 AND NOT C4 → 0. (Agent captured a screenshot via
  `Cmd+Shift+3` or `screencapture` but never invoked the Raycast URL.
  Without C4, no scoring runs — see Pattern #2 in
  `task_creation_notes/03_verification_patterns.md`.)

### Partial-credit invariant (Anti-Pattern #4)

After the wrong-target gate, every reachable scoring combination requires
C4. The smallest "passing" combo is C4 + C1 = 65. C4 alone = 50 < 60 is the
largest non-passing partial — pass threshold strictly above max partial. ✓

## Realistic agent path (visual_grounding-driven)

```text
1. screenshot                            → frame_00
2. visual_grounding("Where is the Terminal icon in the Dock?", frame_00)
3. click <terminal_dock_xy>              → Terminal foreground
4. screenshot                            → frame_01 (Terminal window open)
5. type "open 'raycast://extensions/raycast/clipboard-history/clipboard-history'"
6. key Return                            → Raycast shows clipboard history panel
7. type "/usr/sbin/screencapture -x /Users/lume/Desktop/raycast_screenshot.png"
8. key Return                            → screenshot saved
9. finalize                              → verifier reads result JSON
```

The happy_path evidence flow exercises exactly this path; interactive_pilot
documents the visual_grounding-driven flow with eyes-on verification of each
frame.

## Edge cases handled

- **Pre-existing screenshot file**: `setup_task.sh` deletes
  `~/Desktop/raycast_screenshot.png` so a leftover from a previous run
  cannot satisfy C1.
- **WAL background ticks**: `setup_task.sh` records the WAL size after a
  2-second settle (so Raycast's background init writes are baked in).
  Background ticks contribute ≤ 100 B between snapshots in probes; the
  1024 B threshold is comfortably above the noise floor.
- **Stale `task_start_timestamp`**: written by setup_task.sh on every
  invocation; export uses the most recent value.
- **Not all `raycast://` URLs are equivalent for the verifier**: the C4
  criterion requires Raycast to log activity to
  `raycast-activities-enc.sqlite-wal`. Only **extension-path URLs**
  (`raycast://extensions/<author>/<extension>/<command>`) log; visible-only
  URLs like `raycast://confetti` render UI but write nothing to disk and
  will silently fail C4 (probed live 2026-05-17 — see
  `specific_env_notes/raycast_macos/notes.md` "URL-scheme behavior"). The
  task description hardcodes `raycast://extensions/raycast/clipboard-history/clipboard-history`
  for this reason.

## Files

```
raycast_trigger_and_capture/
├── README.md                 ← this file
├── task.json                 ← task metadata + hook wiring
├── setup_task.sh             ← pre_task (launch + bookkeeping)
├── export_result.sh          ← post_task (produce result JSON)
├── verifier.py               ← scoring + gates
└── test_verifier_offline.py  ← 9 offline scenarios
```

## Related references

- `specific_env_notes/raycast_macos/notes.md` — Raycast install / state-file
  / hotkey constraints
- `12_macos_environments.md` — base-macos sandbox constraints (TCC over SSH,
  Cmd+Space broken, screencapture xattr semantics)
- `task_creation_notes/03_verification_patterns.md` — Pattern #2
  (strict wrong-target gate)
- `task_creation_notes/14_task_design_antipatterns.md` — Anti-Pattern #4
  (pass threshold > max partial)
