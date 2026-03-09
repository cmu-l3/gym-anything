# post_visit_documentation_workflow

## Overview

**Difficulty**: hard
**Environment**: NOSH ChartingSystem (nosh_env@0.1)
**Occupation context**: LPN/LVN completing post-visit clinical documentation after a walk-in visit
**Features tested**: Encounters, Vitals, Issues (problem list), Allergies, Rx (medications), Schedule (appointments)

## Domain Context

After a patient walk-in visit, clinical staff must complete multiple documentation tasks: create a visit note, record vitals, add the presenting problem, document allergies discovered during the visit, prescribe treatment, and schedule follow-up. This task covers all 6 post-visit documentation steps that a Licensed Practical Nurse would be expected to complete.

## Goal

Complete all 6 documentation tasks for walk-in patient Chloe Rafferty (pid 31, DOB 2001-04-18). This is a `hard` task — all target values are specified, but the agent must navigate NOSH's UI to accomplish each step.

## Starting State (seeded by setup_task.sh)

Patient Chloe Rafferty (pid 31) exists in the system but has NO:
- Encounters
- Vitals
- Medical problems
- Allergies
- Medications
- Scheduled appointments

## Required Actions (6 subtasks)

| # | Subtask | Expected Value |
|---|---------|---------------|
| 1 | Create encounter | Type: "Office Visit", Date: today |
| 2 | Record vitals | Weight: 134 lbs, Height: 65 in, BP: 112/72, Pulse: 74, Temp: 99.1°F |
| 3 | Add medical problem | ICD-10: J06.9, "Acute upper respiratory infection" |
| 4 | Record allergy | Allergen: Penicillin, Reaction: Hives |
| 5 | Prescribe medication | Azithromycin 500mg, 1 tab daily × 5 days, qty 5 |
| 6 | Schedule follow-up | 2026-07-08 at 10:00 AM, Dr. James Carter |

## Verification Strategy

**Export script** (`export_result.sh`) queries all 6 data tables after agent completion.

**Verifier** (`verifier.py::verify_post_visit_documentation_workflow`) scores:
| Criterion | Points |
|-----------|--------|
| Encounter created (today's date) | 15 |
| Vitals recorded (all 5 values within tolerance) | up to 20 |
| J06.9 medical problem added | 15 |
| Penicillin allergy recorded | 15 |
| Azithromycin prescription | 20 |
| Follow-up appointment on 2026-07-08 | 15 |
| **Total** | **100** |
| **Pass threshold** | **70** |

### Vitals Sub-Scoring (20 pts total, 4 pts each)
- Weight: 134 lbs (±5 lbs tolerance)
- Height: 65 in (±3 in tolerance)
- BP systolic: 112 (±10 tolerance)
- BP diastolic: 72 (±10 tolerance)
- Pulse: 74 (±5 tolerance)

### Partial Credit
- Wrong ICD code (not J06.9) but any problem added: 7 pts
- Wrong allergen but allergy recorded: 7 pts
- Wrong drug but any prescription: 7 pts
- Wrong date but appointment scheduled: 7 pts

Max partial total: 7+7+7+7=28 pts (plus encounter 15 + some vitals) ≈ 55 pts < 70 threshold. ✓

## Relevant Database Tables

```sql
-- Encounters
SELECT eid, pid, encounter_date, encounter_type FROM encounters WHERE pid=31;

-- Vitals
SELECT vitals_id, pid, weight, height, bp_systolic, bp_diastolic, pulse, temperature
FROM vitals WHERE pid=31;

-- Issues (problem list)
SELECT id, pid, diagnosis, diagnosis_name, activity FROM issues WHERE pid=31;

-- Allergies
SELECT allergy_id, pid, allergen, allergy_type, allergy_reaction FROM allergies WHERE pid=31;

-- Prescriptions
SELECT rxl_id, pid, drug_name, rxl_dosage, rxl_sig, rxl_active FROM rx WHERE pid=31;

-- Schedule
SELECT sch_id, pid, start, visit_type FROM schedule WHERE pid=31;
```

## Edge Cases

- **Vitals entered in wrong units**: Tolerance is generous (±5 lbs, ±3 in, ±10 mmHg, ±5 bpm) to handle common rounding
- **BP stored as single string vs. two columns**: Export script tries both `bp_systolic`/`bp_diastolic` columns and falls back to `BP` string column
- **Agent uses "500 mg" vs "500mg"**: Dosage stored as text; verifier checks drug_name for 'azithromycin' and dosage separately
- **Agent creates encounter on wrong date**: Verifier accepts any new encounter (not just today's date) as partial credit
