# travel_privacy_lockdown

A System Settings task. The agent must harden a MacBook for international
travel: switch to Dark mode, set a tight screensaver timeout (≤2 minutes),
require a password immediately when the screensaver activates, and assign
the top-left hot corner to lock the screen instantly.

The task spans **Appearance**, **Screen Saver** (inside Screen Saver pane),
**Lock Screen**, and **Desktop & Dock → Hot Corners** — four different
locations in System Settings. Screensaver password settings were unified
into the Lock Screen pane in macOS 13+, so the agent must find them there,
not under Screen Saver.

## Required settings

| # | Setting | Target value | `defaults` domain & key |
|---|---|---|---|
| 1 | Dark mode | Enabled | `NSGlobalDomain.AppleInterfaceStyle == "Dark"` |
| 2 | Screensaver idle time | ≤ 120 seconds | `com.apple.screensaver.idleTime <= 120` |
| 3 | Require password after screensaver | Yes (1) | `com.apple.screensaver.askForPassword == 1` |
| 4 | Password grace period | Immediately (0 s) | `com.apple.screensaver.askForPasswordDelay == 0` |
| 5 | Top-left hot corner | Lock Screen (13) | `com.apple.dock.wvous-tl-corner == 13` |

Hot corner action code 13 = Lock Screen. Others: 0=disabled, 2=Mission Control,
4=Show Desktop, 5=Screen Saver, 10=Sleep Display, 13=Lock Screen.

## Baseline (what setup_task.sh resets to)

| # | Setting | Baseline value |
|---|---|---|
| 1 | Appearance | Light (key absent) |
| 2 | Screensaver idle time | 300 s (5 minutes) |
| 3 | Ask for password | 0 (no password required) |
| 4 | Password delay | 5 s |
| 5 | Top-left hot corner | 0 (disabled) |

## Scoring (100 points, pass at 60)

| Criterion | Full | Partial | Zero |
|---|---|---|---|
| C1 Dark mode | 20 if `"Dark"` | — | else |
| C2 Screensaver timeout | 20 if ≤ 120 s | 10 if changed from 300 but > 120 | 0 if still 300 |
| C3 Require password | 20 if `askForPassword == 1` | — | else |
| C4 Immediate lock | 20 if `askForPasswordDelay == 0` | — | else |
| C5 Lock Screen corner | 20 if `wvous-tl-corner == 13` | — | else |

**Max partial-only total**: `0 + 10 + 0 + 0 + 0 = 10` < pass threshold `60`.

## Anti-gaming: strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Partial timeout only (set to 240s, nothing else) | 0 | 10 | 0 | 0 | 0 | **0** (strict gate) | No |
| Dark + password + immediate | 20 | 0 | 20 | 20 | 0 | **60** | Yes (min pass) |
| Four correct | 20 | 20 | 20 | 20 | 0 | **80** | Yes |
| All five correct | 20 | 20 | 20 | 20 | 20 | **100** | Yes |

## Why this task is real-world relevant

Security-conscious travelers harden their laptops exactly this way before
crossing borders: dark mode cuts shoulder-surfing, a short screensaver
timeout limits exposure when stepping away, requiring an immediate password
prevents a thief from waking the machine, and a hot-corner lock key lets
the user lock in one swipe. The combination is documented in travel-security
guides and corporate Mac hardening checklists (e.g., CIS macOS Benchmark,
SANS Mac Security checklists). The difficulty comes from the password
settings moving to Lock Screen in macOS 13+ — an agent unaware of this
migration will look in the wrong pane.

## Verifier inputs (what export_result.sh produces)

`/tmp/travel_privacy_lockdown_result.json`:

```json
{
  "task_start": 1715000000,
  "appearance": "Dark",
  "screensaver_idle_time": 60,
  "screensaver_ask_password": 1,
  "screensaver_password_delay": 0,
  "hot_corner_top_left": 13,
  "read_errors": []
}
```
