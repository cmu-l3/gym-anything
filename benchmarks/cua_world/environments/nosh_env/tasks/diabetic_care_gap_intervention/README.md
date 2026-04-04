# diabetic_care_gap_intervention

## Overview

**Difficulty**: very_hard
**Environment**: NOSH ChartingSystem (nosh_env@0.1)
**Occupation context**: Advanced Practice Psychiatric Nurse / Registered Nurse conducting a chronic disease QI audit
**Features tested**: Issues (problem list discovery), Immunizations, Encounters

## Domain Context

Diabetes care guidelines (ADA standards) specify annual preventive care requirements for Type 2 diabetic patients, including annual influenza vaccination and at minimum annual clinical follow-up. This task simulates a real panel management workflow where a nurse audits their diabetic patient panel for care gaps and closes them.

## Goal

The agent must (without being told which patients have gaps or which specific vaccines are missing):

1. **Identify** all patients with Type 2 Diabetes Mellitus diagnosis (E11.9)
2. **Audit** each diabetic patient's preventive care records for the recommended annual requirements
3. **Close care gaps** for patients who are overdue:
   - Record any missing recommended vaccine(s) in NOSH
   - Create an encounter note documenting the care gap review
4. **Do not duplicate** care for patients who are already meeting all guidelines

## Starting State (seeded by setup_task.sh)

| PID | Name | DOB | Has T2DM | Recent Flu Vaccine | Recent Encounter | Status |
|-----|------|-----|----------|-------------------|-----------------|--------|
| 36 | Sandra Pratt | 1958-11-22 | E11.9 | No | No (last: Jun 2023) | **CARE GAP** |
| 37 | Gregory Holt | 1952-06-17 | E11.9 | No | No (last: Sep 2023) | **CARE GAP** |
| 38 | Wendy Kaufman | 1960-03-08 | E11.9 | No | No (last: Nov 2023) | **CARE GAP** |
| 39 | Donald Peck | 1955-09-14 | E11.9 | Yes (Oct 2024) | Yes (Dec 2024) | Up to date (noise) |
| 40 | Irene Foley | 1963-07-25 | E11.9 | Yes (Nov 2024) | Yes (Jan 2025) | Up to date (noise) |

All 5 patients have the E11.9 diagnosis. The agent must discover that pids 36, 37, 38 have care gaps while 39 and 40 do not.

## Success Criteria

The task is complete when:
1. Pids 36, 37, 38 each have a new influenza vaccine recorded in NOSH
2. Pids 36, 37, 38 each have a new encounter note

## Verification Strategy

**Export script** (`export_result.sh`) queries:
- Baseline immunization and encounter counts (before agent acts)
- Current immunization counts for pids 36, 37, 38
- Whether influenza vaccine specifically appears (checks for 'influenza'/'flu' in name or CVX 141/150/88)
- Encounter counts vs. baseline

**Verifier** (`verifier.py::verify_diabetic_care_gap_intervention`) scores:
| Criterion | Points |
|-----------|--------|
| Flu vaccine recorded for Sandra Pratt (pid 36) | 20 |
| Encounter note created for pid 36 | 10 |
| Flu vaccine recorded for Gregory Holt (pid 37) | 20 |
| Encounter note created for pid 37 | 10 |
| Flu vaccine recorded for Wendy Kaufman (pid 38) | 20 |
| Encounter note created for pid 38 | 10 |
| All 3 patients vaccinated (bonus) | 10 |
| **Total (with bonus)** | **100** |
| **Pass threshold** | **60** |

## Partial Credit Structure

- Binary per-patient: flu vaccine (20 pts) and encounter (10 pts)
- Max partial (2/3 patients complete, no bonus): 2×30=60 pts → barely passes
- Bonus requires all 3 flu vaccines administered

Max without bonus = 90 pts (3 complete patients, no bonus). Threshold = 60. ✓

## Relevant Database Tables

```sql
-- Find all T2DM patients
SELECT pid, diagnosis, diagnosis_name, activity FROM issues WHERE diagnosis LIKE 'E11%';

-- Check immunization history (look for flu vaccines in 2024/2025)
SELECT pid, imm_immunization, imm_date FROM immunizations
WHERE pid IN (36,37,38,39,40) ORDER BY pid, imm_date DESC;

-- Check recent encounters
SELECT pid, encounter_date FROM encounters
WHERE pid IN (36,37,38,39,40) ORDER BY pid, encounter_date DESC;
```

## Edge Cases

- **Agent adds non-flu vaccine**: Any new immunization entry counts as "new_vaccine_added" for partial credit; full credit only for influenza-specific vaccines
- **Agent vaccinates noise patients (39, 40)**: These are tracked but not penalized in scoring; noise patients' flu counts are reported for reference
- **Agent creates encounter only, no vaccine**: 10 pts per encounter without vaccine pts for that patient
- **Agent cannot find the problem list**: All 5 patients have E11.9 seeded in issues table — visible from problem list in NOSH patient chart

## Anti-Gaming Notes

- Baseline immunization and encounter counts recorded after setup cleanup
- Flu vaccine detection uses both name-matching and CVX code matching
- Care-gap patients have OLD (>12 month) encounters to make the gap visible; these don't satisfy the "recent encounter" requirement used in scoring (which checks for new encounters relative to baseline)
