# Recovery System Descent Analysis

## Overview
A competition rocket's parachutes have been replaced with undersized versions (main: 1067mm→254mm, drogue: 305mm→76mm), resulting in dangerously fast descent rates. The agent must diagnose the unsafe recovery configuration, resize the parachutes appropriately, verify through simulation, and write a descent analysis report.

## Domain Context
Recovery system sizing is critical for rocket safety. The main parachute must provide descent rates <=5 m/s for safe landing, and the drogue must slow descent enough for main deployment. Undersized parachutes result in high ground hit velocities that can cause injury or property damage.

## Source Data
- **Base rocket**: `dual_parachute_deployment.ork` — real dual-deploy rocket with "Elliptical 42" main and "Apex 12" Drouge" drogue
- **Injected fault**: Main diameter shrunk from 1067mm to 254mm, drogue from 305mm to 76mm
- **Note**: The .ork file spells drogue as "Drouge" — verifier handles both spellings

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Main parachute sized | 25 | Main diameter >= 700mm |
| Drogue parachute sized | 25 | Drogue diameter >= 220mm |
| Safe descent verified | 25 | Ground hit velocity <= 6.5 m/s in uptodate sim |
| Simulation re-run | 15 | At least one uptodate simulation |
| Descent report | 10 | Meaningful report at expected path |
| **Pass threshold** | **60** | |

## Verification Strategy
Verifier parses `.ork` ZIP+XML to check parachute diameters (by name matching for drogue vs main), simulation status, and ground hit velocity from flight data.
