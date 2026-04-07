# Task: debris_compliance_batch

## Domain Context

**Primary occupation**: Atmospheric and Space Scientist (ONETSOC 19-2021.00), specifically Space Debris Compliance Analyst
**Workflow type**: Batch IADC 25-year post-mission disposal compliance analysis

The Inter-Agency Space Debris Coordination Committee (IADC) guidelines require that all LEO satellites deorbit within 25 years after end of mission. Debris compliance analysts must run orbital lifetime predictions for each satellite in their fleet, classify them as compliant or non-compliant, and file reports with national space agencies. Running batch analyses across a fleet manifest is a routine workflow at operators like Planet Labs, SpaceX, OneWeb, and national space agencies.

## Goal

Read the satellite fleet manifest at `~/Desktop/debris_manifest.csv` containing 5 satellites, simulate orbital decay for each under standard moderate solar conditions (JacchiaRoberts, F10.7=150), determine IADC 25-year compliance for each, and produce a compliance report.

## Success Criteria

All 5 satellites must be simulated and classified:
- **SAT_A** (600 km, B*≈0.037 m²/kg): COMPLIANT
- **SAT_B** (1200 km, B*≈0.013 m²/kg): NON_COMPLIANT
- **SAT_C** (500 km, B*≈0.044 m²/kg): COMPLIANT
- **SAT_D** (900 km, B*≈0.013 m²/kg): NON_COMPLIANT
- **SAT_E** (400 km, B*≈0.039 m²/kg): COMPLIANT

Report written to `~/GMAT_output/debris_compliance_report.txt`.

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| script_created | 10 | Script mtime > task start timestamp |
| all_5_satellites | 20 | 5 spacecraft definitions in script |
| drag_configured | 10 | JacchiaRoberts/MSISE atmosphere model |
| report_written | 10 | Report with ≥5 satellite entries |
| sat_a_correct | 10 | SAT_A classified COMPLIANT |
| sat_b_correct | 10 | SAT_B classified NON_COMPLIANT |
| sat_c_correct | 10 | SAT_C classified COMPLIANT |
| sat_d_correct | 10 | SAT_D classified NON_COMPLIANT |
| sat_e_correct | 10 | SAT_E classified COMPLIANT |
| summary_correct | 10 | Summary shows 3 compliant, 2 non-compliant |

**Pass condition**: score ≥ 60 AND ≥4/5 satellites correctly classified.

## Manifest File

`~/Desktop/debris_manifest.csv` contains:

| Satellite | SMA (km) | INC (deg) | Mass (kg) | DragArea (m²) |
|-----------|----------|-----------|-----------|----------------|
| SAT_A | 6971.14 | 98.0 | 120 | 2.0 |
| SAT_B | 7571.14 | 55.0 | 2500 | 15.0 |
| SAT_C | 6871.14 | 97.5 | 80 | 1.5 |
| SAT_D | 7271.14 | 65.0 | 1800 | 12.0 |
| SAT_E | 6771.14 | 98.5 | 45 | 0.8 |

## Orbital Mechanics Reference

**IADC 25-year rule**: Satellite must deorbit (altitude < 120 km) within 25 years of end-of-mission.

**Ballistic coefficient B* = Cd × A / m** (governs decay rate):

At 600 km (F10.7=150): ~16 years lifetime → COMPLIANT
At 1200 km (F10.7=150): >100 years → NON_COMPLIANT
At 500 km (F10.7=150): ~10 years → COMPLIANT
At 900 km (F10.7=150): ~40 years → NON_COMPLIANT
At 400 km (F10.7=150): ~2–3 years → COMPLIANT

**Key discriminator**: Altitude is the dominant factor. The 25-year boundary for typical LEO satellites falls around 700–800 km at solar average.

## Implementation Notes

GMAT approach for compliance check:
1. Set stopping condition: `SC.Earth.Altitude = 120` (deorbit threshold)
2. Also set maximum propagation: `SC.ElapsedDays = 9125` (25 years)
3. Which stopping condition triggers first determines compliance

Alternatively, agent may propagate in steps and check altitude reduction rate, then extrapolate to 25 years — partial credit awarded.

## Edge Cases

- Agent may use separate GMAT scripts per satellite — acceptable
- Agent may estimate lifetime analytically (B* formula) without GMAT simulation — partial credit for correct classification
- Agent may use different stopping altitude (100 km or 150 km) — minor impact on classification
- SAT_B and SAT_D are clearly non-compliant; agent using 25-year propagation will see no significant decay
