# new_patient_intake

## Overview

A new patient intake workflow requiring the medical assistant to complete four distinct documentation sections: social history, family history, insurance, and an initial consultation encounter. Tests the agent's ability to navigate across multiple unrelated EHR sections for a single patient.

**Difficulty**: Hard
**Patient**: Hobert Wuckert (PID 11, DOB: 2000-10-27, Male)
**Occupation Context**: Medical Assistant performing new patient intake and chart setup

## Goal

Complete the new patient intake for Hobert Wuckert by:
1. Adding Social History (former smoker quit 2015, social alcohol 2-3/week, no illicit drugs)
2. Adding Family History (Father: T2DM deceased age 72 cardiac; Mother: hypertension living)
3. Adding Insurance (Medicare, Member ID: 1EG4-TE5-MK72, Group: A1234)
4. Creating an initial consultation encounter

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| Social history entered | 20 | `other_history` COUNT >= 1 for pid=11 |
| Family history entered | 20 | `other_history` COUNT >= 2 for pid=11 |
| Insurance added | 30 | `insurance` COUNT >= 1 for pid=11 |
| Encounter created | 30 | `encounters` COUNT >= 1 for pid=11 |
| **Total** | **100** | **Pass threshold: 70** |

## Verification Strategy

- **Baseline Recording**: setup_task.sh cleans all other_history, insurance, encounters for pid=11, records zero baselines
- **Export**: Queries counts from other_history, insurance, encounters tables
- **History verification**: Uses count-based checks; 1 entry = social history present; 2+ entries = both social and family history documented (NOSH stores history items as separate rows in other_history table)
- **Wrong-target rejection**: All DB queries filter by pid=11

## Do-Nothing Test

Initial state: all tables cleaned for pid=11 (0 rows in other_history, insurance, encounters).
Do-nothing score: 0/100 -> passed=False

## Data Source

Patient Hobert Wuckert is a Synthea-generated patient loaded from `data/patients.sql` (PID 11). No additional data download required.

## Schema Reference

- `other_history`: oh_id (auto-increment), pid, eid (0=non-encounter-specific)
- `insurance`: pid, insurance plan fields
- `encounters`: pid, encounter_date

## Edge Cases

- Social history in NOSH is entered as free-text in the "Lifestyle" subsection
- Family history uses NOSH's family tree interface with "Add Family Member" button
- Insurance "Payers" section may use dropdowns for plan type vs. free text for member ID
- The other_history AUTO_INCREMENT bug must be fixed (handled in setup_nosh.sh)
