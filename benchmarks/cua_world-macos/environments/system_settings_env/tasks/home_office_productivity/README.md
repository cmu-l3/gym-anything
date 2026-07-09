# home_office_productivity

A System Settings task. The agent must configure five macOS preferences
for a home-office worker who wants the Mac to adapt its appearance
automatically (Light by day, Dark at night), always show scroll bars,
suppress UI sound effects that interrupt video calls, remove the Dock
recent-apps section for a cleaner workspace, and use the faster Scale
window-minimize effect instead of the default Genie.

The task spans **Appearance** (auto mode, scroll bars, minimize effect),
**Sound** (UI sound feedback), and **Desktop & Dock** (recent apps,
minimize effect). The auto-appearance setting (`AppleInterfaceStyleSwitchesAutomatically`)
is a less-visible checkbox that only appears when Light or Dark mode is
not explicitly forced — the agent must find it in the Appearance pane
without accidentally overriding it to a static mode.

## Required settings

| # | Setting | Target value | `defaults` domain & key |
|---|---|---|---|
| 1 | Automatic Light/Dark mode | Enabled | `NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically == 1` |
| 2 | Show scroll bars | Always | `NSGlobalDomain.AppleShowScrollBars == "Always"` |
| 3 | UI sound effects | Off | `NSGlobalDomain.com.apple.sound.beep.feedback == 0` |
| 4 | Dock recent apps | Hidden | `com.apple.dock.show-recents == false` |
| 5 | Minimize effect | Scale | `com.apple.dock.mineffect == "scale"` |

`AppleShowScrollBars` accepted values: `"Always"`, `"Automatic"`, `"WhenScrolling"`.
Baseline is `"Automatic"`.

## Baseline (what setup_task.sh resets to)

| # | Setting | Baseline value |
|---|---|---|
| 1 | Auto appearance | off (key absent) |
| 2 | Show scroll bars | Automatic |
| 3 | UI sound feedback | 1 (on) |
| 4 | Dock recent apps | true (shown) |
| 5 | Minimize effect | genie |

`setup_task.sh` also deletes `AppleInterfaceStyle` so the machine is in
Light mode (not Dark) at baseline, which makes the auto-switch checkbox
visible in the Appearance pane.

## Scoring (100 points, pass at 60)

All criteria are binary (no partial tiers):

| Criterion | Full | Zero |
|---|---|---|
| C1 Auto appearance | 20 if `AppleInterfaceStyleSwitchesAutomatically == 1` | else |
| C2 Always scroll bars | 20 if `"Always"` | else |
| C3 UI sounds off | 20 if `beep.feedback == 0` | else |
| C4 No recent apps | 20 if `show-recents == false` | else |
| C5 Scale minimize | 20 if `"scale"` | else |

**Max partial-only total**: `0` < pass threshold `60`.

## Anti-gaming: strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Wrong scroll bars ("WhenScrolling") | 0 | 0 | 0 | 0 | 0 | **0** (strict gate) | No |
| Three correct | 20 | 20 | 20 | 0 | 0 | **60** | Yes (min pass) |
| Four correct | 20 | 20 | 20 | 20 | 0 | **80** | Yes |
| All five correct | 20 | 20 | 20 | 20 | 20 | **100** | Yes |

## Why this task is real-world relevant

Home-office workers with multiple monitors or who frequently switch between
light and dark environments all use these settings. "Always show scroll bars"
is recommended for keyboard-heavy workflows where scroll position is critical.
Removing the Dock recent-apps section and switching to Scale effect are
standard tips in Mac productivity guides. The auto-appearance toggle is
deliberately hard to find because it only appears in a specific UI state
(not when a static Light or Dark mode is pinned), which tests whether the
agent reasons about modal UI state rather than blindly clicking.

## Verifier inputs (what export_result.sh produces)

`/tmp/home_office_productivity_result.json`:

```json
{
  "task_start": 1715000000,
  "auto_appearance": true,
  "scrollbars": "Always",
  "ui_sound_feedback": 0,
  "dock_show_recents": false,
  "dock_mineffect": "scale",
  "read_errors": []
}
```
