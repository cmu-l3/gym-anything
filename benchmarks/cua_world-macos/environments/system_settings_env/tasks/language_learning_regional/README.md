# language_learning_regional

A System Settings task. The agent must reconfigure macOS for a user who
has started learning French and wants their computer to reinforce the
language and cultural conventions: add French as a preferred language,
switch to metric units and Celsius, enable 24-hour clock, and set the
week to start on Monday (European convention).

The task requires navigating **General → Language & Region** and
**Control Center → Clock Options** — two separate panes. The language
array is ordered (French must appear, though it need not be first).
The first-day-of-week setting is stored as a plist dictionary
`{gregorian = N;}`, which is less visible in the UI than a simple toggle.

## Required settings

| # | Setting | Target value | `defaults` domain & key |
|---|---|---|---|
| 1 | Add French language | Present in AppleLanguages | `NSGlobalDomain.AppleLanguages` contains any `"fr*"` entry |
| 2 | Measurement units | Metric (Centimeters) | `NSGlobalDomain.AppleMeasurementUnits == "Centimeters"` |
| 3 | Temperature unit | Celsius | `NSGlobalDomain.AppleTemperatureUnit == "Celsius"` |
| 4 | 24-hour clock | Enabled | `DateFormat` has `HH`, or `ShowAMPM == 0`, or `AppleICUForce24HourTime == 1` |
| 5 | First day of week | Monday (2) | `NSGlobalDomain.AppleFirstWeekday.gregorian == 2` |

Apple calendar week codes: 1=Sunday, 2=Monday, 7=Saturday.

## Baseline (what setup_task.sh resets to)

| # | Setting | Baseline value |
|---|---|---|
| 1 | Languages | `["en-US"]` only |
| 2 | Measurement | Inches |
| 3 | Temperature | Fahrenheit |
| 4 | Clock format | 12-hour (`h:mm a` pattern) |
| 5 | First day of week | Sunday (gregorian=1) |

## Scoring (100 points, pass at 60)

All criteria are binary (no partial tiers — locale settings either match or they don't):

| Criterion | Full | Zero |
|---|---|---|
| C1 French language | 20 if any `fr*` in AppleLanguages | else |
| C2 Metric units | 20 if `"Centimeters"` | else |
| C3 Celsius | 20 if `"Celsius"` | else |
| C4 24-hour clock | 20 if derived `clock_is_24h` | else |
| C5 Monday start | 20 if `gregorian == 2` | else |

**Max partial-only total**: `0` < pass threshold `60`. No partial credit
tiers — partial credit would be misleading for locale settings where the
value is either correct or wrong.

## Anti-gaming: strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Wrong region (set to Spanish, not French) | 0 | 20 | 20 | 0 | 0 | **0** (strict gate) | No |
| Three correct | 20 | 20 | 20 | 0 | 0 | **60** | Yes (min pass) |
| Four correct | 20 | 20 | 20 | 20 | 0 | **80** | Yes |
| All five correct | 20 | 20 | 20 | 20 | 20 | **100** | Yes |

## Why this task is real-world relevant

Language learners routinely reconfigure their systems into their target
language and cultural conventions as an immersion technique. The specific
combination (French + metric + Celsius + 24h + Monday-first) maps exactly
to French/European locale conventions. The first-day-of-week setting is
particularly obscure: it lives inside a nested plist dict and many agents
will not discover it via the Language & Region UI without knowing to look.

## Verifier inputs (what export_result.sh produces)

`/tmp/language_learning_regional_result.json`:

```json
{
  "task_start": 1715000000,
  "has_french_language": true,
  "measurement_units": "Centimeters",
  "temperature_unit": "Celsius",
  "clock_is_24h": true,
  "clock_date_format": "EEE MMM d  HH:mm",
  "first_weekday_gregorian": 2,
  "read_errors": []
}
```

The export script reads `AppleLanguages` via a subprocess call (to handle
the array format) and checks each token for an `fr` prefix. The
`first_weekday_gregorian` is read from the raw plist via `plistlib`
(with a regex-on-`defaults`-output fallback).
