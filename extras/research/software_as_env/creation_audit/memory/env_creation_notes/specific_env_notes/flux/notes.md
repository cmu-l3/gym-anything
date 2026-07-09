# f.lux on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/flux_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1, Flux 42.2)

> **See also:** `12_macos_environments.md` for the general macOS env guide;
> `specific_env_notes/safari/notes.md` and
> `specific_env_notes/google_earth_macos/notes.md` for the other live macOS envs.

---

## Install Story: `.zip`, not `.dmg` (Pattern A-variant)

f.lux ships from `https://justgetflux.com/mac/Flux.zip` (a 302 redirect to
`https://macflux.b-cdn.net/Flux.zip`, ~2 MB). The `.dmg` URL (`Flux.dmg`)
returns 404 — old blog posts that reference it are stale.

The zip extracts directly to `Flux.app` (no nested folder, no DMG mount).
This makes install a 3-step `curl | unzip | ditto`:

```bash
curl -fL --retry 5 --retry-delay 5 -o /tmp/Flux.zip https://justgetflux.com/mac/Flux.zip
unzip -qo /tmp/Flux.zip -d /tmp/flux_install
sudo ditto /tmp/flux_install/Flux.app /Applications/Flux.app
sudo xattr -dr com.apple.quarantine /Applications/Flux.app
```

**No Rosetta needed.** Flux 42.2's binary is a universal Mach-O:

```bash
$ lipo -archs /Applications/Flux.app/Contents/MacOS/Flux
x86_64 arm64
```

Total install wall-clock on the use.computer dev fleet: ~2.7s. This makes
flux_env the fastest macOS env reset in the repo (~16s cold boot to
verifier pass), beating safari_env (~16s — Safari preinstalled) and
google_earth_env (~70s, x86 Rosetta path).

---

## Bundle Facts

| Property | Value |
|---|---|
| Bundle ID | `org.herf.Flux` |
| Bundle path | `/Applications/Flux.app` (user-installed) |
| Executable | `Flux` (so `pgrep -x Flux` works) |
| Version (current) | 42.2 |
| Last Flux.zip update | 2023-05-17 |
| LSUIElement | **true** — menu-bar agent, no Dock icon |
| Sandboxed | **false** — no `~/Library/Containers/org.herf.Flux/` dir |
| Code-signed | yes (Apple-Issued Developer ID) |

---

## Configuration Story: `defaults write org.herf.Flux`

Flux is NOT sandboxed, so its preferences live at the canonical path:

```
~/Library/Preferences/org.herf.Flux.plist
```

There is no Container redirection (unlike Safari). `defaults read/write
org.herf.Flux` operates directly on this file; a `killall cfprefsd` flush
afterward is still recommended to make the writes visible on the next
launch.

### Confirmed-working pref keys (Sparkle / update-suppression)

These are read by the Sparkle auto-update framework Flux uses. Setting them
in `setup_flux.sh` suppresses the "checking for updates" UI on first launch
and disables phone-home behavior:

| Key | Type | Effect |
|---|---|---|
| `SUEnableAutomaticChecks` | bool | `false` ⇒ no background update polling |
| `SUHasLaunchedBefore` | bool | `true` ⇒ Sparkle skips the "first launch" prompt |
| `SUSendProfileInfo` | bool | `false` ⇒ no system-profile telemetry |

### NOT-confirmed pref keys (location)

Setting `lat`, `lng`, `place` in `setup_flux.sh` DOES persist them into
`org.herf.Flux.plist` (verified post-launch via `defaults read`), but the
Preferences-window Location field remained empty and the first-run "Where
are you?" dialog still appeared. Flux IS reading the plist (it added its own
`version` and `wakeTime` keys after first launch), but evidently uses
*different* key names internally for the location UI. The actual keys are
unknown without a live probe.

**To discover the real location keys** (todo for the next task developer):

1. Boot a flux_env sandbox.
2. Manually click into the Preferences window's Location field, type
   "Pittsburgh, PA", press Search, click Done.
3. `defaults read org.herf.Flux` and diff against the freshly-installed
   baseline. The new key names are the real ones.

### Confirmed-effective pref keys (observed after first launch)

| Key | Type | Value seen | Notes |
|---|---|---|---|
| `version` | int | 3 | Internal config-schema version, Flux-managed. Written shortly after first launch. |
| `wakeTime` | int | 480 (8:00 AM) → 360 (6:00 AM) | Minutes from midnight. Stepper UI writes in 15-minute increments. |
| `steptime` | int | 24 (only after UI interaction) | Internal animation/stepping bookkeeping. Not present after a pure `defaults write`. |

### Stepper UI mechanics (verified live via visual-grounding, 2026-05-18)

The "is when I wake up" time stepper in the Preferences window:

- **One click = 15 minutes.** Going 8:00 AM → 6:00 AM is exactly 8 down-clicks.
  Not 1 hour per click as you might guess.
- **UP and DOWN arrows are only ~8 display-pixels apart** (in 1920×1080 the
  UP-arrow center is at ~y=628 and the DOWN-arrow center is at ~y=636,
  given the default Preferences-window position). Visual-grounding has
  to be specific about which one you want or the LLM may return the
  wrong half of the stepper.
- **No commit is required.** The stepper writes to `org.herf.Flux.plist`
  on each click; clicking the "Done" button just dismisses the window.
  Tasks verifying the plist value can leave the window open if convenient.
- **Flux's UI updates the day/night curve graph in real time** as the
  stepper changes. After 8 down-clicks, the status string changes
  ("The sun has set." → "You're getting sleepy.") and the colour-temp
  reading drops from 4480 K (Sunset, default time of day for the
  use.computer dev fleet) to 2463 K (Bedtime/Candle). Useful visual
  confirmation when an agent needs an in-screen signal.

---

## Known Gotchas

### First-run preferences window opens automatically

On its first launch in a fresh sandbox, Flux opens its preferences window
(titled `f.lux preferences`) on top of the desktop. The window is NOT
modal — Flux continues to function — but it occupies the center of the
screen and may be in the way of UI-driving tasks.

The preferences window has a `Done` button (bottom right) that dismisses
it without saving location. Tasks that need a clean desktop on first
launch should either:
- Click Done in the pre_task hook (requires UI automation), OR
- Quit and re-launch Flux in pre_task (the preferences window doesn't
  re-open on subsequent launches once `SUHasLaunchedBefore=1` is set), OR
- Live with the window open.

For the `launch_flux` smoke task we live with the window open — its
presence is itself evidence Flux is running, and pgrep+lsappinfo both
pass regardless of UI state.

### `LSUIElement = true` means no Dock icon

Flux is a menu-bar agent (Info.plist sets `LSUIElement = true`). There is
NO Dock icon and NO main app window in the normal app sense. The visible
affordance is a small icon in the macOS menu bar (between the system
control center icons). Click that icon to open the preferences popover.

**Implication for verifiers:** the safari/google_earth-style check
"window registered with LaunchServices" still works — `lsappinfo list`
shows the bundle path immediately after `open -a Flux`. But "window
visible on screen" via screenshot is harder because the menu-bar icon is
~20×20 px and not easily matched. Prefer plist / process-level checks
over screenshot matching.

### Helper-free app — bundle-path lsappinfo pattern required

Flux is a single-binary app with no helper processes (no equivalent of
Safari's `SafariLinkExtension` etc.). Its `lsappinfo list` entry is:

```
31) "Flux" ASN:0x0-0x36036:
    bundleID="org.herf.Flux"
    bundle path="/Applications/Flux.app"
    executable path="/Applications/Flux.app/Contents/MacOS/Flux"
```

The Safari-style word-boundary regex `'Flux( |$)'` does NOT match — the
"Flux" name is followed by a colon (from the ASN line), not space/EOL.
Match the bundle-path line instead, which is the same fix the
`preview_env` smoke verifier uses (documented in
`12_macos_environments.md` under "`lsappinfo` Regex: Helper-Free Apps
Need a Different Pattern"):

```python
exec_capture("/usr/bin/lsappinfo list 2>/dev/null | grep -iE 'Flux\\.app' || true")
```

---

## Useful state files for future tasks

| State | Path | Format |
|---|---|---|
| Preferences | `~/Library/Preferences/org.herf.Flux.plist` | Binary plist |
| Sparkle update info | `~/Library/Application Support/Flux/` | (likely; not probed) |
| Cache | `~/Library/Caches/org.herf.Flux/` | (likely; not probed) |

For verifiers, prefer parsing `org.herf.Flux.plist` over UI inspection.
`plistlib.load(open(path,"rb"))` works directly on the binary plist; no
`plutil -convert xml1` step needed.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for registration
pgrep -x Flux >/dev/null || open -a Flux
for i in $(seq 1 30); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app' && break
  sleep 1
done

# Force-quit (idempotent)
osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
pkill -x Flux 2>/dev/null || true

# Inspect prefs
/usr/bin/defaults read org.herf.Flux

# Inspect prefs from raw plist (no cfprefsd cache effects)
/usr/libexec/PlistBuddy -c "Print" ~/Library/Preferences/org.herf.Flux.plist

# Reset for a fresh first-launch
pkill -x Flux 2>/dev/null
rm -f ~/Library/Preferences/org.herf.Flux.plist
killall cfprefsd 2>/dev/null
```

---

## End-to-End Verification (live, dev sandbox, 2026-05-17)

```
boot() → reset took 16s on a cold sandbox
  pre_start (install_flux.sh): 2.7s  (curl 2.1MB + unzip + ditto)
  post_start (setup_flux.sh):  1.8s  (defaults write × 6, cfprefsd flush)
  pre_task (setup_task.sh):    2.9s  (open -a + lsappinfo poll, registered after 1s)
verifier: passed=True, score=100
```

Visual evidence:
`benchmarks/cua_world-macos/environments/flux_env/evidence_docs/launch_flux/panel_view.png` —
Flux's preferences window centered on desktop with the canonical
first-launch content. Confirms Flux is running and rendering its UI.

---

## K-Temperature Pref Keys (as of 2026-05-18 — UNCONFIRMED, awaiting live probe)

The f.lux preferences window has Daytime / Sunset / Bedtime temperature sliders.
The pref key names for these are NOT yet confirmed via `defaults read` diff (no
live probe done yet for the color-temperature tasks). Based on community research,
plausible key names include `nightColor`, `lateColorTemp`, `dayColor`, `bedK`.

**Task design approach**: use a *diff-based detection* strategy rather than
hard-coding key names. The setup_task.sh captures a full plist KV snapshot to
`/tmp/initial_plist_kv.json`; export_result.sh captures a final snapshot.
The verifier diffs the two dicts and looks for any key with a changed integer
value in the K-temperature range [1000, 7500], excluding known non-K keys
(`wakeTime`, `version`, `steptime`). This is robust to unknown key names.

**To discover the real key names** (priority for next task developer):
1. Boot flux_env sandbox.
2. Run `defaults read org.herf.Flux` and capture the baseline.
3. Open Preferences window, drag Bedtime slider to 1900K.
4. Run `defaults read org.herf.Flux` again and diff.
5. The new/changed key is the Bedtime K key — update this notes file with the
   confirmed name and value type.

**wakeTime range reminder**: valid values are 0–1440 in 15-minute increments
(minutes from midnight).

**LIVE TESTING DISCOVERY (2026-05-18)**: Flux normalizes out-of-range wakeTime
values on launch. Specifically:
- wakeTime=28800 (seconds encoding) → Flux writes 1425 on launch
- wakeTime=1440 (midnight boundary) → Flux writes 1425 on launch
- 1425 = 23:45 (11:45 PM) appears to be Flux's clamped maximum

**Consequence for task design**: if Flux is launched in setup_task.sh AFTER
writing an out-of-range wakeTime, Flux will overwrite the value. Two
mitigations applied in this task suite:
1. `repair_wrong_wake_time_encoding`: Does NOT launch Flux in setup_task.sh.
   The bad value (28800) stays in the plist for the agent to repair directly.
2. `full_preference_audit_and_repair`: Changed baseline from 1440 → 660
   (11:00 AM). 660 is within the valid stepper range so Flux won't normalize
   it. Verifier BASELINE_WAKETIME updated from 1440 to 660.

Safe wakeTime baselines for seeding (Flux will NOT overwrite these):
- Any value in [0, 1425] in 15-minute increments
- Verified safe: 480 (8:00 AM), 600 (10:00 AM), 660 (11:00 AM), 1200 (8:00 PM)
- Unsafe: 1440 (midnight boundary), 28800 (out of range)

---

## Task Suite Summary (added 2026-05-18, updated live test 2026-05-18)

Five hard tasks in `tasks/` (difficulty label: "hard" per AP1 — descriptions
give explicit target values):

| Task ID | Archetype | Baseline challenge | Target | Live do-nothing |
|---|---|---|---|---|
| `sync_wake_time_to_circadian_schedule` | computation + multi-param | wakeTime=480, SU keys wrong | wakeTime=315 (computed from sunrise), SU keys=false | score=10, passed=False ✓ |
| `configure_nighttime_temperature` | discovery | clean plist, K key unknown | Bedtime K=1900 (plist diff detection) | score=30, passed=False ✓ |
| `repair_wrong_wake_time_encoding` | error repair | wakeTime=28800 (Flux NOT launched) | wakeTime=480 (minutes) | score=40, passed=False ✓ |
| `configure_complete_sleep_profile` | pipeline | wakeTime=600, SUEnable=true | wakeTime=390, Bedtime K=1900, SUEnable=false | score=10, passed=False ✓ |
| `full_preference_audit_and_repair` | audit + repair | wakeTime=660, both SU=true | wakeTime=480, both SU=false | score=10, passed=False ✓ |

All 43 offline verifier tests pass. All 5 live do-nothing tests pass.
