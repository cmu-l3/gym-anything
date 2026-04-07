# Stability Analysis and Repair

## Overview
A competition rocket has been flagged as potentially unstable. The fins have been reduced to 15mm height (from 76mm), which destroys the rocket's stability margin. The agent must diagnose the instability, correct it, verify via simulation, and write a stability report.

## Domain Context
Rocket stability depends on the relationship between center of gravity (CG) and center of pressure (CP). When fins are too small, CP moves forward of CG, causing the rocket to tumble. This is a critical safety issue that any rocketry safety officer would need to identify and fix.

## Source Data
- **Base rocket**: `dual_parachute_deployment.ork` — a real high-power rocket design with dual-deploy recovery
- **Injected fault**: Trapezoidal fin set height reduced from 76mm to 15mm

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Fin height restored | 35 | Fin height >= 50mm |
| Simulation re-run | 25 | At least one simulation has 'uptodate' status |
| Stable flight | 20 | Ground hit velocity <= 8 m/s |
| Stability report | 20 | Meaningful report at expected path |
| **Pass threshold** | **60** | |

## Verification Strategy
Verifier uses `copy_from_env` to pull the `.ork` file, parses ZIP+XML to check fin dimensions, simulation status, and flight data. Report is checked for existence and content keywords.

## Edge Cases
- Agent may add new fins instead of modifying existing ones — verifier checks max fin height across all fin sets
- Agent may write report in different format — verifier accepts any text file at the expected path
