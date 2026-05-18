# Task: full_preference_audit_and_repair

## Overview

Three independent pref keys in `org.herf.Flux.plist` have drifted from their correct values. Audit the plist, identify all three deviations, and repair them in a single pass without disturbing the preserved location and launch settings.

## Goal

| Key | Drifted Baseline | Correct Target |
|-----|-----------------|----------------|
| `wakeTime` | **1440** (midnight) | **480** (8:00 AM) |
| `SUEnableAutomaticChecks` | **true** | **false** |
| `SUSendProfileInfo` | **true** | **false** |
| `lat` / `lng` / `place` | Pittsburgh (correct) | preserved |
| `SUHasLaunchedBefore` | true | preserved |

## Why This Is Hard

1. Three independent changes — agents often fix one or two but miss the third.
2. `wakeTime = 1440` represents midnight (24:00 in minutes), but doesn't look obviously wrong to an agent that doesn't know the valid range.
3. The task description provides target values, but the agent must read the plist to confirm all three are wrong before acting — a one-shot "write all three" without audit could mistakenly overwrite correct values.
4. After fixing, the agent must verify the complete state, not just assume the writes worked.

## Scoring (100 pts, pass at 85)

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1 plist gate | 10 | plist exists and parses |
| C2 wakeTime exact | 40 | wakeTime == 480 |
| C2 wakeTime ±30 min | 20 | wakeTime ∈ {450, 510} |
| C3 SUEnableAutomaticChecks | 25 | == false |
| C4 SUSendProfileInfo | 25 | == false |

**Pass 85 requires:** exact wakeTime (480) + both SU keys fixed.
- Max partial (±30 wakeTime + both SU): 10+20+25+25 = 80 < 85 ✓ AP4 satisfied.
- Exact wakeTime + one SU: 10+40+25+0 = 75 < 85 → fails.

## Strategy Enumeration

| Agent approach | C2 | C3 | C4 | Total | Outcome |
|----------------|----|----|----|----|---------|
| Fix all three | 40 | 25 | 25 | 100 | PASS |
| Fix wakeTime + SUEnable | 40 | 25 | 0 | 75 | FAIL |
| Fix wakeTime + SUSend | 40 | 0 | 25 | 75 | FAIL |
| Fix both SU, miss wakeTime | 0 | 25 | 25 | 60 | FAIL |
| Fix only wakeTime | 40 | 0 | 0 | 50 | FAIL |
| Close wakeTime (±30) + both SU | 20 | 25 | 25 | 80 | FAIL |
| Do nothing | 0 | 0 | 0 | 10 | FAIL |
| Audit correctly, write wrong lat | — | — | — | 0 | FAIL (gate) |

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task spec |
| `setup_task.sh` | Seeds all three drifted values |
| `export_result.sh` | Reads wakeTime + SU keys + preserves check |
| `verifier.py` | Three-criterion scoring, pass at 85 |
