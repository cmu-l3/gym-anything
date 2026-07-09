# f.lux macOS — Step 0 Research Notes

Researched 2026-05-18. 8 sources surveyed per the Step 0 requirement in
`task_creation_notes/06_task_creation_checklist.md`.

---

## Sources + Key Insights

### Source 1 — Official macOS Quick Start
URL: https://justgetflux.com/news/pages/macquickstart/

- **Wake time is the anchor of the entire circadian schedule.** f.lux uses the
  wake time you set to derive all of its light transition timings. This is the
  single most important config value.
- **Expanded daytime settings** (Options menu): enables the daytime slider to
  go all the way to 1900K. By default the daytime slider stops much higher.
- **"Sleep in on weekends"**: sets a later wake time on Fri/Sat nights so the
  schedule shifts for weekend users. Option stored internally.
- **Backwards Alarm Clock**: answers "how many hours of sleep will I get if I
  go to bed now?" — gives reminders every 30 minutes when it gets very late.
- **"OS X Dark theme at sunset"**: f.lux can toggle macOS Dark Mode at sunset
  and restore Light Mode in the morning. The feature is in Options.
- **"Disable for current app"**: opens a per-app exception. f.lux remembers
  disabled apps forever until explicitly re-enabled.
- Fast transitions: 20-second fade (checked) vs. 1-hour gradual (unchecked).
- Movie Mode: preserves shadow detail / skin tones for 2.5 hours.
- Darkroom mode: removes 100% blue + green, inverts colors for night vision.

### Source 2 — Official FAQ
URL: https://justgetflux.com/faq.html

- f.lux goes down to **1900K** (candlelight) — Night Shift maxes out at 3400K.
- Per-app disabling stores the key `disable-{bundleID}` (bool) in the plist
  **plus** a `disableCount` integer key. If `disableCount` is 0, f.lux will
  not check per-app settings at all. This is undocumented but confirmed by
  the developer in forum replies.
- Hue integration: **macOS does NOT support Philips Hue sync** — Windows only.
  Old blog posts suggesting it works on Mac are stale.
- Binary plist at `~/Library/Preferences/org.herf.Flux.plist`; safe to edit
  with `defaults write org.herf.Flux` or PlistBuddy.

### Source 3 — f.lux Forum: Per-App Disable Plist Pattern
URL: https://forum.justgetflux.com/topic/7656/how-to-undo-disable-for-current-app

- **`disable-{bundleID}` plist keys** are the mechanism for per-app disabling.
  Example: `disable-com.google.Chrome` = true means f.lux is OFF when Chrome
  is the frontmost app.
- **`disableCount`** must be incremented (> 0) for f.lux to read any
  `disable-*` keys. If it's missing or 0, all per-app settings are ignored.
  This is the most common gotcha for scripted per-app configuration.
- To undo, write the key back to false (or delete the key and decrement
  `disableCount`).

### Source 4 — f.lux Forum: Keyboard Shortcuts / AppleScript
URL: https://forum.justgetflux.com/topic/1928/how-to-create-keyboard-shortcuts

- f.lux has **no native AppleScript dictionary**. Automation is done via
  GUI scripting through `System Events`: click menu-bar items programmatically.
- Community solution: **Shortflux** — AppleScript that clicks f.lux menu items
  by name (e.g., "Movie mode", "Disable for an hour", "Until sunrise"). Works
  even if the menu bar icon is hidden by Bartender (insert keystroke to reveal
  it first).
- Can be bound to hotkeys via Automator, BetterTouchTool, Alfred, FastScripts.
- This is the main "chainable workflow" pattern f.lux users share in dotfiles.

### Source 5 — f.lux Forum: Advanced Settings / Plist Keys
URL: https://forum.justgetflux.com/topic/4397/how-to-access-preferences-and-settings-on-macbook

- Confirmed `defaults read org.herf.Flux` works to inspect all pref keys.
- A developer reply confirms using `defaults write` + `killall cfprefsd` is
  the recommended scripting path for setting preferences programmatically.
- `plutil -convert xml1` can be used before manual editing; `plutil -convert
  binary1` to convert back. But `defaults write` is simpler and safer.

### Source 6 — HowToGeek: f.lux + Philips Hue Sync
URL: https://www.howtogeek.com/248915/how-to-sync-f.lux-and-philips-hue-lights-for-eye-friendly-evening-lighting/

- **macOS does NOT support f.lux → Hue sync** (Windows only). Confirmed.
  "Only the Windows version currently supports Hue integration."
- For macOS, users use separate Philips Hue Sync app instead (screen color →
  ambient lights, but that's a different product).

### Source 7 — Comparison: f.lux vs Night Shift (nightshiftkeeper.com + imore.com)
URLs:
- https://nightshiftkeeper.com/blog/flux-vs-night-shift-vs-other-blue-light-apps-mac/
- https://www.imore.com/why-flux-better-night-shift-mac-now

- f.lux removes 4–5× as much blue light as Night Shift at equivalent settings.
- Night Shift cannot go below 3400K; f.lux goes to 1900K. This is the #1 user
  complaint about Night Shift that drives f.lux adoption.
- **Pain point**: Color-sensitive work (photo editing, video grading) is
  impossible with f.lux in bedtime mode. The per-app disable feature exists
  specifically for this — disable for Lightroom, Capture One, Final Cut Pro.
- **"Expanded daytime settings"** enable 1900K during the day too, for users
  who need to match warm office lighting or reduce eye strain all day.

### Source 8 — Hacker News f.lux threads
URLs:
- https://news.ycombinator.com/item?id=30626803
- https://news.ycombinator.com/item?id=15471745

- HN users discuss f.lux's Backwards Alarm Clock as a sleeper feature — many
  don't know it exists. The feature computes hours remaining until wake time.
- Commenters note: Night Shift on macOS has no "always on" mode and can't
  stay active 24/7 (resets after sleep/restart). f.lux always persists.
- Users share dotfiles that `defaults write org.herf.Flux` all pref keys
  after a fresh install — this is the standard power-user bootstrap pattern.
- **Chainable workflow**: dotfile runners call `setup_flux.sh` on boot (writes
  wakeTime, SU keys, K-temp keys) so the environment is reproducible.

---

## Pain Points Extracted

1. **disableCount gotcha**: Per-app disabling silently does nothing if
   `disableCount` is 0. Users discover this only when per-app rules don't work.
2. **K-temperature key names not in docs**: Bedtime/Night/Day K keys are not
   documented. Users must `defaults read` diff before/after UI interaction to
   find them. (See notes.md §K-Temperature Pref Keys for the task strategy.)
3. **Expanded daytime not enabled by default**: The daytime slider is locked
   at a high minimum; users frequently ask how to get warmer daytime colors.
4. **Hue on macOS doesn't work**: Many blog posts say it does; it doesn't.
   (Windows only.) Causes confusion when users try to set it up on Mac.
5. **Wake time unit encoding**: wakeTime is minutes-from-midnight; other
   macOS apps use seconds. Easy to set the wrong value programmatically.

## Cool Configs Extracted

1. **Per-app disable for color-critical apps**: Creative users disable f.lux
   for Lightroom, Capture One, Final Cut Pro using `disable-{bundleID}` keys.
2. **Shortflux + hotkeys**: Bind "Movie mode" or "Disable for an hour" to a
   keyboard shortcut via AppleScript GUI scripting + BetterTouchTool/Alfred.
3. **Expanded daytime + warm office**: Enable expanded daytime settings and
   set all three temperatures to warm values (e.g., 5000K day / 3400K sunset
   / 1900K bedtime) for an all-day warm-tone display.
4. **Dark theme at sunset**: f.lux triggers macOS Dark Mode at sunset and
   Light Mode in the morning — a useful two-for-one accessibility config.
5. **Backwards alarm clock**: Power users enable this + set a precise wake
   time so f.lux's "how many hours left?" reminders count down correctly.

## Chainable Workflows Extracted

1. **Dotfile bootstrap**: `defaults write` all pref keys → `killall cfprefsd`
   → `open -a Flux` — the standard power-user install script pattern.
2. **Shortflux + Shortcuts.app**: Trigger "Movie mode" via Shortcuts.app
   automation, or "Disable until sunrise" when launching a game.
3. **Per-app disable + launch agent**: Write `disable-com.apple.Preview false`
   via a launchd job when launching Lightroom, re-enable on quit.

---

## Task Design Implications

Based on the research above, the 5 created tasks (wakeTime + Sparkle key
repairs) are **technically correct** but cover only one feature area. Research
reveals several unexplored, harder feature areas:

| Feature | Plist Key(s) | Difficulty Driver |
|---|---|---|
| Per-app disable | `disable-{bundleID}` + `disableCount` | disableCount gotcha; bundle ID lookup |
| K-temperature (Bedtime) | unknown — diff probe required | key discovery |
| Expanded daytime settings | unknown — diff probe required | key discovery + feature obscurity |
| Dark theme at sunset | unknown — diff probe required | cross-feature (f.lux + Dark Mode) |
| Backwards alarm clock | unknown | obscure feature |
| Fast transitions toggle | unknown | obscure feature |

**For future task development**: `disable-{bundleID}` + `disableCount` is the
highest-value unexplored area. A task requiring the agent to enable per-app
disabling for a specific creative app (e.g., Preview.app) would be genuinely
very_hard because:
1. Agent must know/discover the app's bundle ID
2. Agent must write both `disable-{bundleID}` = true AND increment `disableCount`
3. If only one step is done, verification fails

**Difficulty label correction (AP1)**: The current 5 tasks give explicit target
values in descriptions → they should be labeled "hard" not "very_hard". Only
tasks requiring goal-only descriptions (agent discovers values AND mechanism)
justify "very_hard".
