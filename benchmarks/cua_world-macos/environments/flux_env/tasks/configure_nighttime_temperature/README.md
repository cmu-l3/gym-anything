# Task: configure_nighttime_temperature

## Overview

Set f.lux's Bedtime (Night) color temperature to 1900K. The pref key name controlling this setting is not published — the agent must discover it by probing the plist before and after a test UI interaction.

## Goal

A key in `~/Library/Preferences/org.herf.Flux.plist` that controls the Bedtime/Night color temperature must change to integer value **1900** (Kelvin). The exact key name is unknown; the verifier uses a diff-based approach.

The Bedtime slider is in the f.lux preferences window. 1900K corresponds to the "Candle" preset. Do not change wakeTime or any Sparkle keys.

## Baseline State (seeded by setup_task.sh)

| Key | Baseline |
|-----|----------|
| wakeTime | 480 (preserved) |
| SUEnableAutomaticChecks | false (preserved) |
| SUSendProfileInfo | false (preserved) |
| Bedtime K key | unknown / default (to be changed to 1900) |

## Discovery Paths

The agent can discover the Bedtime K key name by:
1. Run `defaults read org.herf.Flux` → note current keys
2. Open preferences window, drag Bedtime slider to Candle (1900K)
3. Run `defaults read org.herf.Flux` again → diff shows the new/changed key
4. Then set that key to 1900 via `defaults write` OR leave the UI at 1900K

## Scoring (100 pts, pass at 75)

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1 plist gate | 10 | plist exists, both KV dumps load |
| C2 K exact | 70 | changed K value ∈ [1850, 1950] |
| C2 K close | 50 | changed K value ∈ [1700, 2100] |
| C2 K direction | 20 | changed K value ∈ [1500, 2300] |
| C3 wakeTime preserved | 10 | wakeTime == 480 |
| C4 SUSendProfileInfo preserved | 10 | still false |

**Max partial (C2=20, C3+C4=20):** 10+20+10+10 = 50 < 75 → AP4 satisfied.

## Strategy Enumeration

| Approach | K value | Result |
|----------|---------|--------|
| GUI slider → Candle (1900K) | 1900 | PASS (100) |
| defaults write with correct key = 1900 | 1900 | PASS (100) |
| GUI slider near-Candle (~1800K) | 1800 | PASS (80) |
| defaults write with wrong K = 2000 | 2000 | PASS (80) |
| Slider at Halogen (2700K) | 2700 | FAIL (20) |
| No K change at all | — | FAIL (30) |
| wakeTime changed instead of K | — | FAIL (gate=0) |

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task spec |
| `setup_task.sh` | Seeds baseline + captures /tmp/initial_plist_kv.json |
| `export_result.sh` | Captures /tmp/final_plist_kv.json + scalars |
| `verifier.py` | Key-name-agnostic diff-based K detection |
