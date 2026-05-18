# Task: repair_wrong_wake_time_encoding

## Overview

A unit-encoding error corrupted f.lux's wakeTime: it was set to 28800 (seconds from midnight for 8:00 AM) instead of 480 (minutes from midnight). f.lux uses minutes-from-midnight integers, so 28800 is 20× too large and will break the stepper UI. Repair the error and preserve all other settings.

## Goal

- `wakeTime` → **480** (8:00 AM = 8 × 60 minutes from midnight)
- All other pref keys unchanged

## Baseline State

| Key | Baseline | Target |
|-----|----------|--------|
| wakeTime | **28800** (WRONG) | **480** |
| SUEnableAutomaticChecks | false | preserved |
| SUSendProfileInfo | false | preserved |
| lat / lng / place | Pittsburgh values | preserved |

## Encoding Error Explained

```
Wrong:   28800 = 8 hours × 3600 sec/hour  (seconds from midnight)
Correct:   480 = 8 hours × 60 min/hour    (minutes from midnight, f.lux's format)
```

Valid wakeTime range: 0–1440 (midnight to midnight in 15-min increments). 28800 is out of range.

## Scoring (100 pts, pass at 80)

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1 plist gate | 10 | plist exists and parses |
| C2 wakeTime exact | 60 | wakeTime == 480 |
| C2 wakeTime ±15 min | 30 | wakeTime ∈ {465, 495} |
| C2 wakeTime ±30 min | 10 | wakeTime ∈ {450, 510} |
| C3 SUEnableAutomaticChecks | 15 | preserved false |
| C4 SUSendProfileInfo | 15 | preserved false |

**Max partial without correct wakeTime:** 10+0+15+15 = 40 < 80. AP4 satisfied.

## Strategy Enumeration

| Agent approach | wakeTime | C3+C4 | Total | Outcome |
|----------------|----------|-------|-------|---------|
| `defaults write wakeTime -int 480` (correct + preserve) | 480→60 | 30 | 100 | PASS |
| Same but broke one SU key | 480→60 | 15 | 85 | PASS |
| Same but broke both SU keys | 480→60 | 0 | 70 | FAIL |
| Guessed wrong value (480*60=28800 noop) | 28800 | 30 | 40 | FAIL |
| Set via GUI stepper ≈ ±15 min | 465→30 | 30 | 70 | FAIL |
| Do nothing | 28800 | 30 | 40 | FAIL |
| Modified SU keys but left wakeTime | 28800 | — | 0 | FAIL (gate) |

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task spec, error metadata |
| `setup_task.sh` | Seeds wakeTime=28800 |
| `export_result.sh` | Exports wakeTime + SU key state |
| `verifier.py` | Checks wakeTime == 480 with preservation guards |
