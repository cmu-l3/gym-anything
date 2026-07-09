# presentation_mode_setup

A System Settings task. The agent must apply five concrete macOS user
preferences that, together, configure the machine into a "presentation mode"
— a real configuration an IT admin or presenter would set up before a demo.

The task tests whether the agent can navigate the **new macOS 13+ System
Settings UI** (which differs substantially from the pre-Ventura System
Preferences grid) to multiple distinct panes: General/Appearance,
Desktop & Dock, and Control Center. Alternatively, an agent that recognises
the underlying `defaults` domains can apply the same changes via Terminal —
that path is legitimate (the System Settings UI is just a front-end for
these prefs).

## Required settings

| # | Setting | Target value | `defaults` domain & key |
|---|---|---|---|
| 1 | Appearance | Dark mode | `NSGlobalDomain.AppleInterfaceStyle == "Dark"` |
| 2 | Dock position | Left edge of screen | `com.apple.dock.orientation == "left"` |
| 3 | Dock auto-hide | Enabled | `com.apple.dock.autohide == 1` (true) |
| 4 | Dock icon size | Smallest (≤32 px) | `com.apple.dock.tilesize <= 32` |
| 5 | Menu bar clock | 24-hour format | `com.apple.menuextra.clock.DateFormat` contains `HH` |

Real macOS slider range for Dock tilesize is 16 (slider all the way to
Small) through 128 (slider all the way to Large), default 48. "Small"
in the slider's labelled left third is ≤32; the verifier accepts any
value in that range so the agent doesn't have to land on an exact pixel.

The 24-hour clock check uses the `DateFormat` string (e.g.
`"EEE MMM d  HH:mm"` for 24h, `"EEE MMM d  h:mm a"` for 12h). The marker
is the uppercase `HH` (24-hour) vs the lowercase `h` (12-hour) — this is
Unicode Technical Standard #35's date pattern syntax and unambiguous.

## Baseline (what setup_task.sh resets to)

Before the agent gets control, `setup_task.sh` forces all five settings
to the OPPOSITE of their target values (Anti-Pattern #7 in
`14_task_design_antipatterns.md`):

| # | Setting | Baseline value |
|---|---|---|
| 1 | Appearance | Light (key absent from NSGlobalDomain) |
| 2 | Dock position | bottom |
| 3 | Dock auto-hide | false |
| 4 | Dock icon size | 48 (system default) |
| 5 | Menu bar clock | 12-hour ("EEE MMM d  h:mm a") |

After resetting, setup_task.sh runs `killall Dock SystemUIServer cfprefsd`
so the live UI reflects the baseline (the Dock and menu bar both re-read
their prefs on restart), and then launches System Settings so the agent
sees a clean starting state.

## Scoring (100 points, pass at 60)

Each criterion is binary 20/0 except for Dock tilesize which has a
partial-credit tier for "changed but not small enough":

| Criterion | Full | Partial | Zero |
|---|---|---|---|
| C1 Dark mode | 20 if `"Dark"` | — | else |
| C2 Dock orientation | 20 if `"left"` | 5 if `"right"` (wrong direction — credit for *some* movement) | else |
| C3 Dock auto-hide | 20 if `true` | — | else |
| C4 Dock tilesize | 20 if `≤32` | 10 if changed from 48 but not `≤32` | 0 if `48` or missing |
| C5 24-hour clock | 20 if `DateFormat` contains `HH` | — | else |

**Max partial-only total**: `0 + 5 + 0 + 10 + 0 = 15` < pass threshold `60`.
Per Anti-Pattern #4 in `14_task_design_antipatterns.md`, no partial-only
score can pass. Verified in `test_verifier_offline.py`.

**Strict wrong-target gate** (Pattern #2 in `03_verification_patterns.md`):
if the agent changed *something* from baseline but landed on a value that
neither matches the task target nor matches the baseline AND zero
criteria are fully correct, the verifier returns `score=0` immediately.
This catches the "blind agent who toggled random things hoping for
credit" scenario. Tested in `test_verifier_offline.py`.

## Anti-gaming: strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Mass-mistake (set Dock right, leave others at baseline) | 0 | 5 | 0 | 0 | 0 | **0** (strict gate) | No |
| Mass-changed-but-wrong-target (all 5 changed, all wrong) | 0 | 5 | 0 | 10 | 0 | **0** (strict gate) | No |
| Half-done (Dark+autohide+24h, dock untouched) | 20 | 0 | 20 | 0 | 20 | **60** | Yes (just barely) |
| Three-of-five correct | 20 | 20 | 20 | 0 | 0 | **60** | Yes |
| Four-of-five correct | 20 | 20 | 20 | 20 | 0 | **80** | Yes |
| All five correct | 20 | 20 | 20 | 20 | 20 | **100** | Yes |
| All five correct (Dock right instead of left) | 20 | 5 | 20 | 20 | 20 | **85** | Yes |

The half-done strategy passing at the threshold is intentional — the
task explicitly states all 5 changes; partial credit for completing 3
of 5 is reasonable, and 60 is meant to mean "majority of work done"
not "everything perfect". An agent reading the description will aim
for all 5 anyway.

## Why this task is real-world relevant

System administrators on shared/lab Macs configure machines into a
presentation profile constantly: dimming/dark UI for stage projection,
hidden Dock so audience attention is on the slides, large or repositioned
Dock for accessibility, 24-hour clock for international audiences. The
specific values picked here are real configurations from public IT-admin
playbooks (e.g., the SUNY Mac kiosk profile, NIST 800-179 macOS
hardening, the Caltech presentation-machine setup guide).

## Verifier inputs (what export_result.sh produces)

`/tmp/presentation_mode_setup_result.json`:

```json
{
  "task_start": 1715000000,
  "appearance": "Dark",                  // string or null
  "dock_orientation": "left",            // string or null
  "dock_autohide": true,                 // bool
  "dock_tilesize": 16,                   // int or null
  "clock_date_format": "EEE MMM d  HH:mm", // string or null
  "clock_is_24h": true,                  // computed bool (DateFormat contains 'HH')
  "any_settings_touched": true,          // computed bool
  "read_errors": []                      // list of any plistlib/defaults read failures
}
```

The verifier reads this JSON via `copy_from_env` and computes per-criterion
scores. All export-side logic is wrapped in try/except (Anti-Pattern #12);
unreadable keys yield `null` rather than malformed JSON.
