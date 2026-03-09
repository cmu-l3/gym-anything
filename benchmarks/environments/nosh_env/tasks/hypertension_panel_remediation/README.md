# hypertension_panel_remediation

## Overview

**Difficulty**: very_hard
**Environment**: NOSH ChartingSystem (nosh_env@0.1)
**Occupation context**: Registered Nurse / Advanced Practice Nurse conducting a panel QI audit
**Features tested**: Problem list (issues), Medication management (rx), Encounter documentation

## Domain Context

Hillside Family Medicine runs periodic quality improvement initiatives. A common initiative is ensuring all hypertensive patients have appropriate pharmacotherapy. This task simulates a real clinical workflow: the nurse reviews all patients flagged with a hypertension diagnosis, checks their medication list, and prescribes treatment for those who lack it.

## Goal

The agent must complete this without being told which patients are untreated or which medication to use:

1. **Discover** which patients have Essential Hypertension (I10) in their problem list AND have no antihypertensive on their active medication list
2. **Prescribe** an appropriate first-line antihypertensive for each untreated patient
3. **Document** the intervention with an encounter note for each treated patient

## Starting State (seeded by setup_task.sh)

| PID | Name | DOB | Condition | Medications |
|-----|------|-----|-----------|-------------|
| 22 | Eleanor Whitfield | 1962-03-15 | I10 (active) | None |
| 23 | Russell Hartley | 1955-08-22 | I10 (active) | None |
| 24 | Margaret Toomey | 1958-11-07 | I10 (active) | None |
| 25 | Bernard Keane | 1960-04-30 | I10 (active) | Lisinopril 10mg (noise) |
| 26 | Dolores Vance | 1963-09-12 | I10 (active) | Amlodipine 5mg (noise) |

The agent must identify pids 22, 23, 24 as untreated and pids 25, 26 as already treated.

## Success Criteria

The task is complete when:
1. Each untreated patient (pids 22, 23, 24) has at least one active antihypertensive medication
2. At least one encounter note was created for the treated patients

## Verification Strategy

**Export script** (`export_result.sh`) queries:
- Baseline rx counts for each patient (recorded before agent acts)
- Current active rx counts for pids 22, 23, 24
- Whether any antihypertensive class drug is present (amlodipine, lisinopril, losartan, metoprolol, atenolol, hydrochlorothiazide, valsartan, ramipril, enalapril)
- Current encounter counts vs. baseline

**Verifier** (`verifier.py::verify_hypertension_panel_remediation`) scores:
| Criterion | Points |
|-----------|--------|
| Antihypertensive prescribed for Eleanor Whitfield (pid 22) | 25 |
| Antihypertensive prescribed for Russell Hartley (pid 23) | 25 |
| Antihypertensive prescribed for Margaret Toomey (pid 24) | 25 |
| At least 1 encounter created for treated patients | 25 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Partial Credit Structure

- Full 25 pts per prescription (binary — did the agent add an antihypertensive?)
- 25/17/8 pts for 3/2/1 encounter notes created

Max partial score without any criterion fully met = 0 (no partial credit at sub-criterion level for prescriptions). Pass threshold of 60 > 0. ✓

## Relevant Database Tables

```sql
-- Check problem list
SELECT pid, diagnosis, diagnosis_name, activity FROM issues WHERE pid IN (22,23,24,25,26);

-- Check active medications
SELECT pid, drug_name, rxl_active FROM rx WHERE pid IN (22,23,24,25,26) AND rxl_active='y';

-- Check encounters
SELECT pid, encounter_date FROM encounters WHERE pid IN (22,23,24,25,26);
```

## Edge Cases

- **Agent prescribes duplicate for noise patients**: Verifier only checks pids 22-24; extra meds on 25/26 don't deduct points but are not rewarded
- **Agent prescribes a non-standard antihypertensive**: Verifier accepts any of 9 major antihypertensive classes
- **Agent creates encounters for all patients including noise**: Only encounters for pids 22-24 count toward score

## Anti-Gaming Notes

- Baseline counts recorded after cleanup, before agent acts
- Verifier checks for NEW rx (curr_count > init_count) as secondary signal in case exact drug-name matching fails
- Agent cannot gain points by modifying noise patients (25, 26)
