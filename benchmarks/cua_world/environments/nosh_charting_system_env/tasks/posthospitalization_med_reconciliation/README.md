# posthospitalization_med_reconciliation

## Overview

A post-hospitalization medication reconciliation workflow where the nurse care coordinator must discontinue two pre-admission medications and replace them with dose-adjusted versions from the hospital discharge summary. Requires both medication management (discontinue + add) and encounter documentation.

**Difficulty**: Very Hard
**Patient**: Sherill Botsford (PID 10, DOB: 1995-01-24, Female)
**Occupation Context**: Nurse Care Coordinator performing post-discharge medication reconciliation

## Goal

Complete medication reconciliation for Sherill Botsford following hospitalization for hypertensive crisis:
1. Discontinue Lisinopril 5mg (pre-admission dose)
2. Discontinue Amlodipine 5mg (pre-admission dose)
3. Add Lisinopril 10mg daily (discharge dose)
4. Add Amlodipine 10mg daily (discharge dose)
5. Create a medication reconciliation encounter

## Seeded State (Contamination-Injection Pattern)

setup_task.sh seeds two active medications that represent pre-admission doses:
- Lisinopril 5mg daily (active, started 90 days ago)
- Amlodipine 5mg daily (active, started 90 days ago)

The agent must identify these as the pre-admission medications and discontinue them, then add the higher-dose replacements.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| Lisinopril 5mg discontinued | 25 | `rx_list` Lisinopril with dosage < 8, rxl_date_inactive set |
| Amlodipine 5mg discontinued | 25 | `rx_list` Amlodipine with dosage < 8, rxl_date_inactive set |
| Lisinopril 10mg added (active) | 20 | `rx_list` Lisinopril with dosage >= 8, rxl_date_inactive NULL |
| Amlodipine 10mg added (active) | 20 | `rx_list` Amlodipine with dosage >= 8, rxl_date_inactive NULL |
| Encounter created | 10 | `encounters` table COUNT > baseline for pid=10 |
| **Total** | **100** | **Pass threshold: 70** |

## Verification Strategy

- **Baseline Recording**: setup_task.sh records initial encounter count to `/tmp/phmr_init_enc.txt`
- **Export**: Queries for discontinued (rxl_date_inactive set) and active (rxl_date_inactive NULL) medications by dose ranges
- **Dose matching**: Uses CAST(rxl_dosage AS DECIMAL) < 8 for 5mg, >= 8 for 10mg (tolerates minor formatting differences)

## Do-Nothing Test

Initial state: Lisinopril 5mg and Amlodipine 5mg both active, no encounters.
Do-nothing score: 0/100 (no discontinuations, no new meds, no encounter) -> passed=False

## Edge Cases

- Agent might try to edit existing medication dose instead of discontinue + add new — export checks for distinct records
- NOSH stores dosage as text in rxl_dosage column; CAST handles numeric comparison
- Agent must navigate to Medications/Rx section to see existing meds before acting
