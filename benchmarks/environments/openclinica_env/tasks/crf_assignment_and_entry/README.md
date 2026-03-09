# Task: CRF Assignment and Data Entry

**ID**: `crf_assignment_and_entry@1`
**Difficulty**: Hard
**Environment**: `openclinica_env@0.1`

## Overview

This task tests the full workflow of setting up and using Case Report Forms (CRFs) in OpenClinica. It covers four distinct clinical data management operations that must be performed in the correct order:

1. **CRF Upload** — Upload a Vital Signs CRF template (XLS file) to create the CRF in the system.
2. **CRF Assignment** — Assign the Vital Signs CRF to two event definitions: Baseline Assessment and Follow-up Visit.
3. **Event Scheduling** — Schedule a Baseline Assessment event for study subject DM-102.
4. **Data Entry** — Enter Vital Signs measurements into the CRF for DM-102's Baseline Assessment and mark it complete.

## Study Context

- **Study**: Phase II Diabetes Trial (`DM-TRIAL-2024`)
- **Login**: root / Admin123!
- **Target Subject**: DM-102 (Male, DOB: 1952-11-07)
- **CRF Template**: `/home/ga/vital_signs_crf.xls` (copied from `/workspace/data/sample_crf.xls` during setup)

## Agent Goals

| Step | Action | Details |
|------|--------|---------|
| 1 | Upload CRF | Upload `/home/ga/vital_signs_crf.xls` as a new CRF called "Vital Signs" |
| 2 | Assign to Baseline | Assign Vital Signs CRF to the "Baseline Assessment" event definition as required |
| 3 | Assign to Follow-up | Assign Vital Signs CRF to the "Follow-up Visit" event definition as required |
| 4 | Schedule event | Schedule Baseline Assessment for DM-102 with start date 2024-02-05 |
| 5 | Enter data | Enter Systolic BP=135, Diastolic BP=88, Heart Rate=78; mark CRF complete |

## Scoring

| Criterion | Points |
|-----------|--------|
| Vital Signs CRF exists in database | 20 |
| CRF assigned to Baseline Assessment | 20 |
| CRF assigned to Follow-up Visit | 15 |
| DM-102 Baseline Assessment event exists | 20 |
| Bonus: event date is 2024-02-05 | +5 |
| event_crf exists (data entry started) | 15 |
| item_data rows present | 5 |
| Bonus: values 135/88 found in item_data | +5 |
| VLM visual check | up to 10 |
| Penalty: no audit log / GUI bypass detected | -20 |
| **Pass threshold** | **70** |

## Setup

The setup script (`setup_task.sh`) performs the following:

- Verifies the DM-TRIAL-2024 study exists.
- Creates the "Baseline Assessment" and "Follow-up Visit" event definitions if not already present.
- Removes any existing Vital Signs CRF (and all dependent records) from the database to ensure a clean state.
- Copies the sample CRF XLS template to `/home/ga/vital_signs_crf.xls`.
- Clears any pre-existing events for DM-102 to ensure a clean scheduling state.
- Launches Firefox, logs in to OpenClinica, and switches the active study to DM-TRIAL-2024.
- Records an audit log baseline and generates a result integrity nonce.

## Verification

The verifier (`verifier.py`) reads the exported result from `/tmp/crf_assignment_and_entry_result.json` and checks:

- Vital Signs CRF exists in the `crf` table.
- The CRF is linked to both event definitions in `event_definition_crf`.
- A `study_event` record exists for DM-102's Baseline Assessment.
- An `event_crf` record exists indicating data entry was started.
- `item_data` contains the expected numeric values (135, 88, 78).
- A VLM (vision language model) inspects the final screenshot for visual evidence of task completion.
- The audit log shows new entries since setup, confirming GUI interaction rather than direct database manipulation.

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task setup: DB cleanup, file copy, browser setup |
| `export_result.sh` | Post-task export: queries DB and writes result JSON |
| `verifier.py` | Programmatic verifier: scores the exported result |
| `README.md` | This documentation |
