# Task: `set_wake_time_to_6am`

## Domain

f.lux is a free macOS menu-bar utility that warms the screen color at
night and returns it to daylight values around the user's wake-up time.
The "wake time" is stored in `~/Library/Preferences/org.herf.Flux.plist`
under the key `wakeTime`, encoded as **minutes from midnight** (so 480 =
8:00 AM, 360 = 6:00 AM, 1080 = 6:00 PM).

A user whose wake schedule changes — switching from a 9-to-5 to a
4-to-noon shift, say — needs to tell f.lux about it so the dawn ramp
starts at the right hour. The setting is exposed in f.lux's Preferences
window as a small time-stepper labeled "is when I wake up" directly
below the day/night-curve graph.

## Task

Change f.lux's wake-time from **8:00 AM** (the baseline `setup_task.sh`
puts in place) to **6:00 AM** (encoded as `wakeTime = 360`).

The agent has three completion paths and the verifier accepts any of
them:

1. **GUI**: Click f.lux's menu-bar icon (or interact with the auto-opening
   Preferences window after launch) → click the down-arrow on the wake-time
   stepper four times (8:00 → 7:30 → 7:00 → 6:30 → 6:00) → click `Done`.
2. **`defaults`**: `defaults write org.herf.Flux wakeTime -int 360 && killall cfprefsd`.
3. **PlistBuddy**: `/usr/libexec/PlistBuddy -c "Set :wakeTime 360" ~/Library/Preferences/org.herf.Flux.plist`
   (after quitting Flux so cfprefsd doesn't clobber the write).

## Baseline state (from `setup_task.sh`)

| Key | Value | Notes |
|---|---|---|
| `wakeTime` | 480 | 8:00 AM — must be changed |
| `lat` | 40.4406 | Pittsburgh, PA (anti-gaming target) |
| `lng` | -79.9959 | "" |
| `place` | "Pittsburgh, PA" | "" |
| `SUEnableAutomaticChecks` | false | Sparkle |
| `SUHasLaunchedBefore` | true | Sparkle |
| `SUSendProfileInfo` | false | Sparkle (anti-gaming target) |

`setup_task.sh` also writes the following to `/tmp/` for the verifier:

- `/tmp/task_start_timestamp` (Unix epoch)
- `/tmp/initial_wakeTime`, `/tmp/initial_lat`, `/tmp/initial_lng`,
  `/tmp/initial_SUSendProfileInfo`, `/tmp/initial_plist_mtime`,
  `/tmp/initial_plist_size`

## Scoring (100 pts, pass at 70)

| # | Criterion | Full | Partial |
|---|---|------|---------|
| C1 | Gate: plist exists, parses, expected domain | 10 | — |
| C2 | wakeTime changed from baseline 480 | 5 | — |
| C3 | wakeTime == 360 (6:00 AM) | 60 | 30 if 350-370, 15 if 330-390 |
| C4 | Anti-gaming: lat preserved at baseline | 10 | — |
| C5 | Anti-gaming: SUSendProfileInfo preserved (false) | 10 | — |

Plus a **strict wrong-target gate** (Pattern #2 in
`03_verification_patterns.md`):

> If the plist was touched after task_start AND `wakeTime` is unchanged
> from baseline AND the agent modified one of the *protected* fields
> (`lat`, `lng`, or `SUSendProfileInfo`), return score 0 immediately.
> The gate covers `lat` and `lng` symmetrically so an agent that flips
> only one half of the location pair is still caught.

### Pass-threshold safety per Anti-Pattern #4

```
max partial total = C1(10) + C2(5) + C3-tier1(30) + C4(10) + C5(10) = 65
pass threshold    = 70
65 < 70  ✓  no partial-credit-only false pass.
```

### Strategy enumeration (Anti-Pattern #13)

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|----------|----|----|----|----|----|-------|------|
| Do-nothing | 10 | 0 | 0 | 10 | 10 | **30** | No |
| Mass-edit (touch every field, wakeTime untouched, no unrelated keys added) | 10 | 0 | 0 | 0 | 0 | **10** | No |
| Mass-edit + unrelated key added | strict-gate fires | – | – | – | – | **0** | No |
| Wrong direction (e.g. wakeTime=600) | 10 | 5 | 0 | 10 | 10 | **35** | No |
| Close partial (365) | 10 | 5 | 30 | 10 | 10 | **65** | No |
| Correct (360) | 10 | 5 | 60 | 10 | 10 | **95** | Yes |
| Correct + accidentally flipped SUSendProfileInfo | 10 | 5 | 60 | 10 | 0 | **85** | Yes |
| wakeTime deleted | 10 | 0 | 0 | 10 | 10 | **30** | No |

No shortcut strategy crosses 70.

## Files

- `task.json` — task spec; declares the pre_task + post_task hooks.
- `setup_task.sh` — pre_task; resets baseline state and records `/tmp/initial_*`.
- `export_result.sh` — post_task; reads plist, writes
  `/tmp/set_wake_time_to_6am_result.json`.
- `verifier.py` — `verify_set_wake_time_to_6am(traj, env_info, task_info)`;
  reads result via `env_info["copy_from_env"]`.
- `test_verifier_offline.py` — 11 mocked-result scenarios covering all the
  required + adversarial cases above.
- `README.md` — this file.

## Edge cases

- **f.lux exits after first launch.** Flux is a menu-bar app; without a
  location set, it can quit shortly after first launch. The agent does NOT
  need Flux to be running to mutate the plist — `defaults write` works on
  a stopped Flux. setup_task.sh launches Flux for the GUI completion path
  but the post_task hook quits it for a clean `defaults read`.
- **Sandbox-vs-cfprefsd cache.** Any `defaults write` followed by a
  `defaults read` from the same shell may pick up the in-memory cfprefsd
  value rather than the on-disk plist. `export_result.sh` runs
  `killall cfprefsd` before reading to force the on-disk state.
- **Plist binary format.** `org.herf.Flux.plist` is a *binary* plist;
  `plistlib.load(open(path, "rb"))` reads it directly (no `plutil -convert`
  required). The verifier's plist-keys probe uses this.
