# family_accessibility_elderly

A System Settings task. The agent must enable six macOS accessibility features
that together make the machine usable for an elderly family member — large cursor,
high-contrast display, sticky/slow keys for motor-impaired typing, zoom via scroll
wheel, and full display clarity (reduce transparency).

The task tests whether the agent can navigate to **Accessibility** in the macOS 13+
System Settings sidebar — which is buried below the fold — and find the correct
sub-panels: Display, Pointer Control, and Keyboard within Accessibility. Each
panel lives on a separate page inside the Accessibility section, requiring multiple
navigations. The agent cannot satisfy the task from a single pane.

## Required settings

| # | Setting | Target value | `defaults` domain & key |
|---|---|---|---|
| 1 | Increase Contrast | Enabled | `com.apple.universalaccess.increaseContrast == 1` |
| 2 | Reduce Transparency | Enabled | `com.apple.universalaccess.reduceTransparency == 1` |
| 3 | Cursor size | ≥ 3.0 (large) | `com.apple.universalaccess.cursorSize >= 3.0` |
| 4 | Scroll wheel zoom | Enabled | `com.apple.universalaccess.closeViewScrollWheelToggle == 1` |
| 5 | Sticky keys | Enabled | `com.apple.universalaccess.stickyKey == 1` |
| 6 | Slow keys | Enabled | `com.apple.universalaccess.slowKey == 1` |

Cursor size is a continuous slider (range roughly 1.0–4.0). The verifier
accepts any value ≥ 3.0 as full credit, and 1.5–3.0 as partial.

## Baseline (what setup_task.sh resets to)

| # | Setting | Baseline value |
|---|---|---|
| 1 | Increase Contrast | false (0) |
| 2 | Reduce Transparency | false (0) |
| 3 | Cursor size | 1.0 (system default, key absent) |
| 4 | Scroll wheel zoom | false (0) |
| 5 | Sticky keys | false (0) |
| 6 | Slow keys | false (0) |

## Scoring (100 points, pass at 60)

| Criterion | Full | Partial | Zero |
|---|---|---|---|
| C1 Increase Contrast | 20 if true | — | else |
| C2 Reduce Transparency | 20 if true | — | else |
| C3 Cursor size | 20 if ≥ 3.0 | 10 if ≥ 1.5 and < 3.0 | 0 if ≤ 1.0 |
| C4 Scroll wheel zoom | 15 if true | — | else |
| C5 Sticky keys | 15 if true | — | else |
| C6 Slow keys | 10 if true | — | else |

**Max partial-only total**: `0 + 0 + 10 + 0 + 0 + 0 = 10` < pass threshold `60`.

## Anti-gaming: strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | Total | Pass? |
|---|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Cursor only (medium) | 0 | 0 | 10 | 0 | 0 | 0 | **0** (strict gate) | No |
| Three features correct | 20 | 20 | 20 | 0 | 0 | 0 | **60** | Yes (min pass) |
| Four features correct | 20 | 20 | 20 | 15 | 0 | 0 | **75** | Yes |
| All six correct | 20 | 20 | 20 | 15 | 15 | 10 | **100** | Yes |

## Why this task is real-world relevant

Accessibility configuration for elderly relatives is one of the most
common reasons non-technical users open System Settings. The six
settings chosen are all recommended in Apple's own accessibility guides
and in published dementia/low-vision caregiver handbooks. The
difficulty comes from the fragmented UI: each sub-feature is on a
different page deep in the Accessibility tree.

## Verifier inputs (what export_result.sh produces)

`/tmp/family_accessibility_elderly_result.json`:

```json
{
  "task_start": 1715000000,
  "increase_contrast": true,
  "reduce_transparency": true,
  "cursor_size": 3.5,
  "scroll_wheel_zoom": true,
  "sticky_key": true,
  "slow_key": true,
  "read_errors": []
}
```
