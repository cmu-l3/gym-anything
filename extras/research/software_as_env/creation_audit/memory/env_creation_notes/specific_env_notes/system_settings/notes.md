# System Settings on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/system_settings_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M-series macOS 15.0)

> **See also:** `12_macos_environments.md` for the general macOS env guide,
> `specific_env_notes/safari/notes.md` and
> `specific_env_notes/google_earth_macos/notes.md` for the other live envs.

---

## Install Story: Preinstalled, Like Safari and Preview

System Settings (the macOS 13+ successor to System Preferences) is
preinstalled on every macOS image at `/System/Applications/System Settings.app`
(bundle ID still `com.apple.systempreferences` — kept from the legacy
System Preferences). Use the same defensive "probe both /Applications and
/System/Applications" pattern as `preview_env` because Apple is inconsistent
across system apps.

```bash
CANDIDATES=(
  "/System/Applications/System Settings.app"
  "/Applications/System Settings.app"
  "/System/Applications/System Preferences.app"   # fallback on very old images
  "/Applications/System Preferences.app"
)
```

Live test on use.computer dev fleet (macOS 15.0, 2026-05): System Settings
lives at `/System/Applications/System Settings.app`. Bundle version `15.0`,
bundle ID `com.apple.systempreferences`.

---

## Launching: `open -a "System Settings"`

Process name is **`System Settings`** (with the literal space). Probe with
`pgrep -x 'System Settings'`. The lsappinfo entry has the form:

```
806
    bundle path="/System/Applications/System Settings.app"
    executable path="/System/Applications/System Settings.app/Contents/MacOS/System Settings"
    bundle path="/System/Applications/System Settings.app/Contents/PlugIns/GeneralSettings.appex"
    ...
```

System Settings is **helper-free** (no SystemSettingsLinkExtension etc.) so
the Safari-style `'System Settings'( |$)` regex won't match. Use the bundle-
path line (`grep -iE 'System Settings\.app'`) per the preview_env lesson in
`12_macos_environments.md` "lsappinfo Regex".

Launch via `open -a "System Settings"` from `exec_ssh`. Cmd+Space (Spotlight)
remains broken in the base-macos image (confirmed in 4 separate probes per
`12_macos_environments.md`).

---

## State Surfaces (defaults domains)

System Settings is fundamentally a **front-end for macOS `defaults` domains**.
Every panel ultimately writes to one or more of these domains, so verifiers
should query `defaults` rather than the System Settings UI.

| System Settings panel | `defaults` domain | Notable keys |
|---|---|---|
| General > Appearance | `NSGlobalDomain` | `AppleInterfaceStyle` ("Dark" or absent), `AppleAccentColor` |
| Desktop & Dock | `com.apple.dock` | `orientation` (left/bottom/right), `autohide` (bool), `tilesize` (int 16-128), `magnification` (bool), `largesize` (int), `mineffect` (genie/scale/suck), `show-recents` (bool) |
| Control Center > Clock | `com.apple.menuextra.clock` | `DateFormat` (UTS#35 pattern), `ShowAMPM` (bool — see "Show AM/PM is the canonical 24-hour toggle" below), `IsAnalog`, `ShowDate`, `ShowDayOfWeek` |
| Accessibility | `com.apple.universalaccess` | `closeViewSmoothImages`, `reduceMotion`, `reduceTransparency` |
| Displays | `com.apple.spaces` + ColorSync | display-specific |
| Notifications | `com.apple.ncprefs.plist` (read via `plutil`) | per-app notification policy |
| Keyboard | `NSGlobalDomain` | `InitialKeyRepeat`, `KeyRepeat` |
| Trackpad | `com.apple.AppleMultitouchTrackpad`, `com.apple.driver.AppleBluetoothMultitouch.trackpad` | tap-to-click, force-click, etc. |
| Sound | `com.apple.systemsound` + system level | volume/balance via CoreAudio APIs |
| Screen Saver | `com.apple.screensaver` | `idleTime`, `moduleDict` |
| Hot Corners | `com.apple.dock` | `wvous-{tl,tr,bl,br}-corner` (int), `wvous-…-modifier` (int) |
| Spotlight | `com.apple.spotlight` | `orderedItems` (which categories), `engineHostName` |

Some panels write to **paths the user can't read with `defaults`** (the
managed `~/Library/Containers/...` paths Safari uses). Verifiers for those
must `plutil -convert xml1` the container plist first. System Settings'
**own** panels (Appearance, Dock, Clock) all write to user-readable
top-level domains — no container indirection.

---

## "Show AM/PM" Is the Canonical 24-Hour Toggle, NOT DateFormat

Surfaced live during `presentation_mode_setup`'s interactive pilot (2026-05).

**Naive design**: check `com.apple.menuextra.clock.DateFormat` for `"HH"`
(Unicode TS#35 24-hour marker) to detect 24-hour clock.

**Reality**: when a user toggles **System Settings > Control Center > Clock
Options... > Show AM/PM** OFF, macOS sets `ShowAMPM = 0` in
`com.apple.menuextra.clock` but **leaves `DateFormat` unchanged** at
whatever 12-hour pattern was there. The menu bar nonetheless renders
24-hour because SystemUIServer uses `ShowAMPM` as the canonical override.

**Verifier must accept both signals**:

```python
clock_is_24h = False
if dateformat is not None:
    if "HH" in dateformat and " a" not in dateformat and not dateformat.endswith("a"):
        clock_is_24h = True
if show_ampm is False:   # explicit
    clock_is_24h = True
```

Both paths legitimate:
- **Terminal path** (`defaults write … DateFormat "EEE MMM d  HH:mm"`):
  agents that know the canonical string can write it directly.
- **UI path** (toggle Show AM/PM off): the GUI path, ShowAMPM=0,
  DateFormat unchanged.

Setup script baseline should write BOTH to 12-hour values to avoid stale
state:
```bash
defaults write com.apple.menuextra.clock DateFormat -string "EEE MMM d  h:mm a"
defaults write com.apple.menuextra.clock ShowAMPM -bool true
```

---

## SDK `mouse.drag` Does NOT Move NSSlider in System Settings

Surfaced during `presentation_mode_setup`'s interactive pilot when trying
to drag the Dock Size slider via `sb.mouse.drag(start_x, y, end_x, y)`.

**Observations** (live on use.computer dev fleet, 2026-05):
1. `mouse.drag` returns success but the slider's visual position does NOT
   change, and `defaults read com.apple.dock tilesize` returns the
   unchanged value.
2. Click-on-track ("jump to position") sometimes moves the slider one step
   in an unexpected direction (e.g., a click at the LEFT end of the track
   moved the value from 48 to 85 — RIGHT). Behaviour is not reproducible.
3. Click+Left-arrow (focus slider, decrement via keyboard): Left arrow
   keypresses do not change the slider value once it's "focused" by click
   — likely because the click didn't grant the slider keyboard focus.
4. Multiple drag attempts with varying start coordinates and end coordinates
   all returned success but the slider didn't move.

**Workaround**: for tasks that require the agent to set a slider value,
the Terminal path (`defaults write … -int N`) is the reliable alternative.
The `presentation_mode_setup` task description explicitly states "you may
use any means to apply these settings", which makes Terminal a documented
valid completion path.

**Open investigation**: try (a) the use.computer SDK's `display.click_drag`
if it exists in a future SDK release, (b) Apple Events to set the slider
value via AppleScript (likely fails for SwiftUI controls — they don't
publish an AppleScript dictionary), (c) calling AppKit's NSSlider
`setDoubleValue:` via PyObjC injected as a `do shell script` block.
For now, document and Terminal-fallback.

This is the **first documented SDK limitation against System Settings'
SwiftUI sliders**.

---

## AppKit Doesn't Re-Read `AppleInterfaceStyle` on Plist Change

`defaults write -g AppleInterfaceStyle -string "Dark"` updates the plist,
but **running apps do not immediately switch to Dark mode**. AppKit reads
`AppleInterfaceStyle` once at process start and caches it; subsequent
changes require an explicit `NSDistributedNotificationCenter` post of
`AppleInterfaceThemeChangedNotification`.

When the agent uses the **System Settings UI** to toggle Dark mode,
System Settings itself posts the right notification, so all apps animate
to Dark instantly. When the agent uses `defaults write` from Terminal,
the notification is NOT sent — only the persisted value changes. Running
apps render whatever appearance they were launched with until restarted
(or until an AppleScript Apple Event explicitly triggers a refresh).

**Implication for verifiers**: the verifier reads the persisted `defaults`
value (`AppleInterfaceStyle == "Dark"`), not the live rendering state.
Both UI-path and Terminal-path agents pass the verifier identically;
the visual difference between the two is purely cosmetic and does not
affect scoring.

**Implication for evidence screenshots**: a final screenshot of a
Terminal-path happy-path run may show System Settings in Light chrome
even though `AppleInterfaceStyle == "Dark"`. This is a documented quirk,
not a verifier or task design bug. Mention it in the evidence README so
reviewers don't waste time chasing the apparent inconsistency.

To force a visual refresh from a Terminal-only path:
```bash
# Lightweight: send NSDistributedNotification via Python+PyObjC
python3 -c "
from Cocoa import NSDistributedNotificationCenter
nc = NSDistributedNotificationCenter.defaultCenter()
nc.postNotificationName_object_('AppleInterfaceThemeChangedNotification', None)
"
```
(Not always reliable; some apps still need a relaunch.)

---

## `pgrep -x` Pattern Catches Helper-Free System Apps

`pgrep -x 'System Settings'` works because there is exactly one main
process and no helpers named `SystemSettingsLinkExtension`. Same pattern
as Preview, Calculator, TextEdit, etc. This contrasts with Safari, which
has multiple helpers (`SafariLinkExtension`, `SafariWidgetExtension`,
"Safari Networking", "Safari Web Content (Prewarmed)", etc.) and
requires a more careful regex.

`lsappinfo` regex: match `'System Settings\.app'` (bundle path line) —
the same pattern Preview uses.

---

## Setup Pattern: Per-Task Baseline Reset, Not Env-Level

Unlike Safari (which preconfigures many prefs at env level in
`setup_safari.sh`), the system_settings_env's `setup_system_settings.sh`
deliberately does NOT preconfigure target settings — those baselines
vary per task and live in each task's `setup_task.sh`. This follows
Anti-Pattern #7 in `14_task_design_antipatterns.md` ("Update-Style
Setup Does Not Reset the Target Fields"): every update-style task
must reset the to-be-modified fields to a "challenge baseline" so a
do-nothing agent cannot collect baseline credit.

The env-level `setup_system_settings.sh` only:
1. Force-quits any leftover System Settings (clean window state per reset)
2. Pre-creates user dirs (`~/Documents`, `~/Downloads`, `~/Library/Preferences`)
3. Flushes cfprefsd so per-task baseline writes don't race with stale cache

---

## Verifier Pattern: 5-Criterion Binary + Strict Wrong-Target Gate

For multi-setting tasks (like `presentation_mode_setup`), the recommended
shape is:

1. **Per-criterion binary scoring** (20 pts full / 0 partial) for most
   criteria. Use partial credit sparingly — only for criteria where
   "almost right" is meaningfully different from "completely wrong" (e.g.,
   Dock size "small but not smallest" is different from "default").

2. **Strict wrong-target gate**: track three flags per criterion — `full`,
   `baseline`, `other`. Fire `score=0` if `any(other) and not any(full)`.
   This catches the "agent toggled random things hoping for credit"
   strategy.

3. **Do-nothing gate**: fire `score=0` if `all(baseline)`. Explicit message
   helps debugging.

4. **Anti-Pattern #4 check**: `sum(partial_pts for each criterion) <
   pass_threshold`. For `presentation_mode_setup`: 0+5+0+10+0 = 15 < 60 ✓.

See `tasks/presentation_mode_setup/verifier.py` for the implementation.

---

## Adding a New System Settings Task — Quick Checklist

- [ ] Read this file end to end + `12_macos_environments.md`
- [ ] Identify the `defaults` domain(s) the task targets — must be
      user-readable (avoid `~/Library/Containers/...`-only prefs).
- [ ] Document the target value(s) in `task.json` `metadata`.
- [ ] In `setup_task.sh`: explicitly reset the to-be-modified prefs to
      "challenge baseline" values (NOT the same as the env's neutral
      baseline — must be the OPPOSITE of the task target).
- [ ] `killall Dock SystemUIServer cfprefsd` after baseline writes so
      the live UI reflects baseline when the agent first sees it.
- [ ] Record `/tmp/task_start_timestamp` for freshness checks.
- [ ] In `export_result.sh`: read EACH target pref via
      `defaults read`, wrap heredoc Python in try/except, write JSON
      with safe defaults.
- [ ] In `verifier.py`: full/partial scoring, strict wrong-target gate,
      do-nothing gate. Verify Anti-Pattern #4 holds.
- [ ] `test_verifier_offline.py` with do-nothing, wrong-target, partial,
      full-correct + scenario-specific edges (e.g., the UI-toggle path
      where DateFormat doesn't match the canonical pattern).
- [ ] Run live: `do_nothing`, `wrong_target`, `happy_path`,
      `interactive_pilot` per the `evidence_docs/<task>/README.md`
      convention from this env.

---

## Live-Verified Reset Time (2026-05)

```
sandbox provision               ~25s
workspace mkdir + upload mounts ~6s
pre_start (install verify)      ~1s
post_start (env baseline)       ~2s
pre_task (task baseline reset)  ~4s
                                ----
total cold reset                ~38s
```

Faster than google_earth_env (~70s) because no DMG download / Rosetta
install. Comparable to safari_env (~15-20s on warm sandbox, ~48s cold).

Per-flow end-to-end including agent work + finalize: ~60-90s.
