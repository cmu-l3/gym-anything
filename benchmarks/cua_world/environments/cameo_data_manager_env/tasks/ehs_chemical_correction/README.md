# Task: EHS Chemical Correction

## Overview

An EHS (Extremely Hazardous Substance) designation compliance task requiring deep knowledge of the EPA 40 CFR Part 355 EHS list and Threshold Planning Quantities (TPQs). The agent must identify chemical misclassifications in imported Tier II data and correct them in CAMEO Data Manager.

**Difficulty**: Very Hard
**Domain**: Environmental compliance / EPCRA Section 312 Tier II reporting
**Real workflow**: Compliance officers routinely audit CAMEO records after importing Tier II data from facilities that misclassify substances. Identifying EHS designations requires cross-referencing facility inventory quantities against EPA-published TPQ thresholds.

## Goal

All three chemicals that are EHS substances stored above their TPQ thresholds must have their EHS designation corrected to `true` in CAMEO, and the corrected dataset must be exported as XML.

End state: `C:\Users\Docker\Documents\CAMEO\ehs_corrected.xml` contains corrected Tier II data with all EHS misclassifications fixed.

## Task Description

The Vermont SERC audit notice is at `C:\workspace\data\ehs_audit_report.txt`. It flags Northfield Paper Mill and Essex Wire and Cable for EHS designation review — but does NOT specify which chemicals are wrong.

The agent must:
1. Import `C:\workspace\data\ehs_audit_data.xml` into CAMEO
2. Review the chemical inventory for both facilities
3. Using knowledge of the EPA EHS list (40 CFR Part 355), determine which chemicals require EHS designation based on stored quantities vs. TPQ thresholds
4. Correct the EHS status for each misclassified chemical
5. Export the corrected dataset to `C:\Users\Docker\Documents\CAMEO\ehs_corrected.xml`

## Key Facts for Verification

The following EHS misclassifications exist in the imported data (not revealed to the agent):

| Facility | Chemical | CAS | Current EHS | Correct EHS | TPQ (lbs) | Qty on Site |
|----------|----------|-----|-------------|-------------|-----------|-------------|
| Northfield Paper Mill | Chlorine Dioxide | 10049-04-4 | false | **true** | 10 | 25-40 lbs |
| Essex Wire and Cable | Ammonia, Anhydrous | 7664-41-7 | false | **true** | 500 | 600-800 lbs |
| Essex Wire and Cable | Hydrofluoric Acid | 7664-39-3 | false | **true** | 100 | 150-200 lbs |

Sodium Hypochlorite (7681-52-9) at Northfield Paper Mill is correctly marked EHS=false.

## Verification Strategy

The verifier:
1. Copies `C:\Windows\Temp\ehs_chemical_correction_result.json` (export metadata)
2. Independently copies and parses `C:\Users\Docker\Documents\CAMEO\ehs_corrected.xml`
3. Checks `<ehs>` element for each of the 3 target CAS numbers

### Scoring (100 points total)

| Criterion | Points | Check |
|-----------|--------|-------|
| Chlorine Dioxide (10049-04-4) EHS=true | 35 | XML `<ehs>true</ehs>` for this CAS |
| Ammonia, Anhydrous (7664-41-7) EHS=true | 30 | XML `<ehs>true</ehs>` for this CAS |
| Hydrofluoric Acid (7664-39-3) EHS=true | 35 | XML `<ehs>true</ehs>` for this CAS |

**Pass threshold**: ≥ 70 points
**Wrong facility gate**: Score = 0 if the export XML does not contain "Northfield Paper Mill" or "Essex Wire and Cable"

## Setup State

- CAMEO is launched fresh with no prior data
- The audit report text file is accessible at `C:\workspace\data\ehs_audit_report.txt`
- The Tier II data file is at `C:\workspace\data\ehs_audit_data.xml`
- Task start timestamp is written to `C:\Windows\Temp\ehs_chemical_correction_start.txt`

## Edge Cases

- The agent may not recognize which chemicals are EHS without consulting reference material
- Chlorine Dioxide (TPQ=10 lbs) is easily confused with Chlorine (also EHS, TPQ=10 lbs) — both are present in CAMEO's chemical database
- The agent must distinguish between EHS-list lookup and the checkbox UI in CAMEO
- Sodium Hypochlorite is NOT on the EHS list — if the agent incorrectly marks it EHS=true, it should not gain or lose points (that's not tested)
