# Task: sync_wake_time_to_circadian_schedule

## Overview

Configure f.lux to match a circadian-friendly schedule based on real astronomical data for Pittsburgh, PA, while simultaneously fixing two incorrectly-enabled telemetry/update settings.

## Goal

Three independent pref-key changes in `~/Library/Preferences/org.herf.Flux.plist`:

1. **wakeTime** — set to 315 (5:15 AM), computed as:
   - Pittsburgh civil twilight July 15 = 6:02 AM
   - Offset = 6:02 − 0:45 = 5:17 AM
   - Nearest 15-minute f.lux increment: 5:15 AM = **315 minutes from midnight**
2. **SUEnableAutomaticChecks** — set to `false`
3. **SUSendProfileInfo** — set to `false`

Do NOT modify any other existing keys (lat, lng, place, SUHasLaunchedBefore).

## Baseline State (seeded by setup_task.sh)

| Key | Baseline | Target |
|-----|----------|--------|
| wakeTime | 480 (8:00 AM) | **315** (5:15 AM) |
| SUEnableAutomaticChecks | true | **false** |
| SUSendProfileInfo | true | **false** |
| lat | 40.4406 | preserved |
| lng | −79.9959 | preserved |

## Scoring (100 pts, pass at 85)

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1 plist gate | 10 | plist exists and parses |
| C2 wakeTime exact | 60 | wakeTime == 315 |
| C2 wakeTime ±15 min | 30 | wakeTime ∈ {300, 330} |
| C2 wakeTime ±30 min | 10 | wakeTime ∈ {285, 345} |
| C3 SUEnableAutomaticChecks | 15 | value == false |
| C4 SUSendProfileInfo | 15 | value == false |

**Max partial without any full criterion:** 10+30+15+15 = 70 < 85 → cannot pass on partial credit alone.

## Strategy Enumeration

| Agent approach | wakeTime | C3 | C4 | Total | Outcome |
|----------------|----------|----|----|----|---------|
| Correct all three | 315→60 | 15 | 15 | 100 | PASS |
| Correct wakeTime + one SU | 315→60 | 15 | 0 | 85 | PASS |
| Correct wakeTime only | 315→60 | 0 | 0 | 70 | FAIL |
| Close wakeTime (300) + both SU | ±15→30 | 15 | 15 | 70 | FAIL |
| Close wakeTime only | ±15→30 | 0 | 0 | 40 | FAIL |
| Both SU only (no wakeTime change) | 0 | 15 | 15 | 40 | FAIL |
| Wrong wakeTime + everything else | 0 | 15 | 15 | 40 | FAIL |
| Do nothing | 0 | 0 | 0 | 10 | FAIL |

## Implementation Notes

- `wakeTime` is written by all three completion paths: `defaults write org.herf.Flux wakeTime -int 315`, PlistBuddy, or GUI stepper (32 down-clicks from 480→315, each click = 15 min)
- `SUEnableAutomaticChecks` and `SUSendProfileInfo` are standard Sparkle pref keys with bool type
- After any `defaults write`, run `killall cfprefsd` to flush cache
- The verifier reads the plist directly via `plistlib`, not `defaults read`, so any write method works

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task spec, scoring metadata |
| `setup_task.sh` | Seeds challenge baseline, records /tmp/initial_* |
| `export_result.sh` | Quits Flux, flushes cfprefsd, writes result JSON |
| `verifier.py` | Multi-criterion scoring with wrong-target gate |
