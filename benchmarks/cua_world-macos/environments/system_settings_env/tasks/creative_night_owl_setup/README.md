# creative_night_owl_setup

A System Settings task. The agent must configure five preferences tailored
to a creative professional who types late at night: reduce on-screen animation,
set key repeat to the fastest possible speed with the shortest initial delay,
and assign productivity hot corners (Show Desktop, Mission Control).

The task spans three separate panes: **Accessibility → Motion** (reduce
motion), **Keyboard** (repeat rates), and **Desktop & Dock → Hot Corners**
(each corner is a separate interaction). The key-repeat sliders require
precise placement at their minimum positions, which the agent must interpret
from the label or discover empirically.

## Required settings

| # | Setting | Target value | `defaults` domain & key |
|---|---|---|---|
| 1 | Reduce Motion | Enabled | `NSGlobalDomain.AppleReduceMotion == 1` |
| 2 | Key repeat rate | Fastest (≤ 2) | `NSGlobalDomain.KeyRepeat <= 2` |
| 3 | Delay until repeat | Shortest (≤ 15) | `NSGlobalDomain.InitialKeyRepeat <= 15` |
| 4 | Bottom-left hot corner | Show Desktop (4) | `com.apple.dock.wvous-bl-corner == 4` |
| 5 | Top-right hot corner | Mission Control (2) | `com.apple.dock.wvous-tr-corner == 2` |

KeyRepeat range: 2 (fastest) to 120 (slowest), system default 6.
InitialKeyRepeat range: 15 (shortest) to 120 (longest), system default 25.
The verifier accepts any value at or below the threshold as full credit.

Hot corner action codes: 0=disabled, 2=Mission Control, 4=Show Desktop,
5=Screen Saver, 10=Put Display to Sleep, 13=Lock Screen, 14=Notification Center.

## Baseline (what setup_task.sh resets to)

| # | Setting | Baseline value |
|---|---|---|
| 1 | Reduce Motion | off (key deleted) |
| 2 | Key repeat rate | 6 (system default) |
| 3 | Delay until repeat | 25 (system default) |
| 4 | Bottom-left hot corner | 0 (disabled) |
| 5 | Top-right hot corner | 0 (disabled) |

## Scoring (100 points, pass at 60)

| Criterion | Full | Partial | Zero |
|---|---|---|---|
| C1 Reduce Motion | 20 if true | — | else |
| C2 Key repeat | 25 if ≤ 2 | 10 if changed from 6 but > 2 | 0 if still 6 |
| C3 Initial delay | 25 if ≤ 15 | 10 if changed from 25 but > 15 | 0 if still 25 |
| C4 Bottom-left corner | 15 if == 4 | — | else |
| C5 Top-right corner | 15 if == 2 | — | else |

**Max partial-only total**: `0 + 10 + 10 + 0 + 0 = 20` < pass threshold `60`.

## Anti-gaming: strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Partial-only (both sliders moved, not max) | 0 | 10 | 10 | 0 | 0 | **0** (strict gate) | No |
| Three correct (motion + repeat + corners) | 20 | 25 | 0 | 15 | 0 | **60** | Yes |
| Four correct | 20 | 25 | 25 | 15 | 0 | **85** | Yes |
| All five correct | 20 | 25 | 25 | 15 | 15 | **100** | Yes |

## Why this task is real-world relevant

Heavy keyboard users (writers, developers, musicians using keyboard shortcuts)
routinely max out key-repeat settings. Hot corners for Mission Control and
Desktop are among the most common productivity shortcuts on macOS. Reduce
Motion is a common setting for users with motion sensitivity or who find
animations distracting at night. The combination of numeric slider precision
and hot-corner assignment in three different panes makes this genuinely hard.

## Verifier inputs (what export_result.sh produces)

`/tmp/creative_night_owl_setup_result.json`:

```json
{
  "task_start": 1715000000,
  "reduce_motion": true,
  "key_repeat": 2,
  "initial_key_repeat": 15,
  "hot_corner_bottom_left": 4,
  "hot_corner_top_right": 2,
  "read_errors": []
}
```
