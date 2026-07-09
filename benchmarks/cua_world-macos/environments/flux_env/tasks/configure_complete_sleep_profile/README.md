# Task: configure_complete_sleep_profile

## Overview

Three independent f.lux preference changes that together form a complete sleep-optimized profile. Each requires a different action or discovery method, and all three must be set correctly to pass.

## Goal

| Setting | Baseline | Target |
|---------|----------|--------|
| `wakeTime` | 600 (10:00 AM) | **390** (6:30 AM) |
| Bedtime K temp | default/unknown | **1900K** (Candle) |
| `SUEnableAutomaticChecks` | true | **false** |
| `SUSendProfileInfo` | false | preserved |

## Required Actions

1. **wakeTime = 390** — compute 6:30 AM in minutes from midnight (6×60+30=390) and write to plist.
2. **Bedtime K = 1900K** — discover the pref key via plist diff before/after UI interaction, then set to 1900.
3. **SUEnableAutomaticChecks = false** — direct pref write.

## Scoring (100 pts, pass at 80)

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1 plist gate | 10 | plist + KV dumps valid |
| C2 wakeTime exact | 35 | wakeTime == 390 |
| C2 wakeTime ±15 min | 20 | wakeTime ∈ {375, 405} |
| C2 wakeTime ±30 min | 10 | wakeTime ∈ {360, 420} |
| C3 Bedtime K exact | 30 | K ∈ [1850, 1950] |
| C3 Bedtime K close | 15 | K ∈ [1700, 2100] |
| C3 Bedtime K direction | 5 | K ∈ [1500, 2300] |
| C4 SUEnableAutomaticChecks | 25 | == false |

**Max partial (no full credit on any):** 10+20+15+0 = 45 < 80 ✓.

## Strategy Enumeration

| Approach | C2 | C3 | C4 | Total | Outcome |
|----------|----|----|----|----|---------|
| All three correct | 35 | 30 | 25 | 100 | PASS |
| Close wakeTime + exact K + SU | 20 | 30 | 25 | 85 | PASS |
| Exact wakeTime + close K + SU | 35 | 15 | 25 | 85 | PASS |
| Exact wakeTime + exact K (no SU fix) | 35 | 30 | 0 | 75 | FAIL |
| Just wakeTime + SU (no K) | 35 | 0 | 25 | 70 | FAIL |
| Just wakeTime | 35 | 0 | 0 | 45 | FAIL |
| Just SU fix | 0 | 0 | 25 | 35 | FAIL |
| Do nothing | 0 | 0 | 0 | 10 | FAIL |

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task spec |
| `setup_task.sh` | Seeds baseline + /tmp/initial_plist_kv.json |
| `export_result.sh` | /tmp/final_plist_kv.json + scalars |
| `verifier.py` | Three-criterion scoring with K-diff detection |
