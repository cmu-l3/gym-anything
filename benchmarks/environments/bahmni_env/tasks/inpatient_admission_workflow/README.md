# Task: Inpatient Admission Workflow

## Domain Context

Inpatient admission is a multi-step clinical workflow that requires coordination between the front desk (registration), clinical staff (assessment), and the documentation system. In district hospitals using Bahmni across sub-Saharan Africa, a medical officer or clinical officer managing an emergency admission must open an inpatient visit (distinct from the usual OPD visit), record the full set of presenting vital signs, document diagnoses, prescribe initial medications, and write an admission note — all within the first hour of admission. This task reflects the realistic complexity of an emergency admission workflow where multiple modules of Bahmni must be navigated in sequence.

## Goal

Complete a full inpatient admission for Valentina Torres (BAH000023) presenting with suspected Community-Acquired Pneumonia. By end of task:

1. **Inpatient visit started** — encounter of inpatient or admission type created in the system
2. **Four vital sign types recorded** — temperature, respiratory rate, oxygen saturation (SpO2), and blood pressure (or pulse as substitute)
3. **Two coded diagnoses** — Pneumonia (or equivalent) + one additional relevant diagnosis
4. **Two medications prescribed** — appropriate for pneumonia (antibiotic + one other medication)
5. **Admission note written** — ≥150 characters

## Success Criteria

| Criterion | Points | Verifier Check |
|-----------|--------|----------------|
| Inpatient/admission encounter created | 20 | Encounter type query (inpatient/emergency/admission) |
| Respiratory vitals recorded (temp + RR/SpO2 + BP/pulse) | 25 | OpenMRS obs for respiratory/fever concepts |
| Two diagnoses including Pneumonia | 25 | encounter_diagnosis with pneumonia concept |
| Two medications prescribed | 20 | Drug orders count >= 2 |
| Admission note ≥150 chars | 10 | Text obs length |
| **Pass threshold** | **70** | Score ≥ 70 |

## Verification Strategy

1. `setup_task.sh` creates patient BAH000023 (Valentina Torres), records baseline state (no encounters, no orders, no obs), launches browser.

2. `export_result.sh` queries:
   - All encounters by type
   - All observations for respiratory vitals (temperature, RR, SpO2, BP)
   - All diagnoses from encounter_diagnosis table
   - All drug orders
   - Text observations for clinical note

3. `verifier.py` checks each criterion independently with the wrong-target gate as the first check.

## Schema Reference

CIEL concept UUIDs for respiratory vitals:
- Temperature: `5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Respiratory Rate: `5242AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Oxygen Saturation: `5092AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Systolic BP: `5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Diastolic BP: `5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Pulse: `5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`

MySQL tables:
- `encounter` with `encounter_type` → find inpatient encounter types
- `encounter_diagnosis` → coded diagnoses per encounter
- `orders` → drug prescriptions

## Starting State

- Valentina Torres (BAH000023) is created in setup_task.sh as a new patient
- No visits, encounters, observations, diagnoses, or drug orders exist
- Browser opened to Bahmni login page

## Edge Cases

- Agent must search for Valentina Torres by name or identifier BAH000023
- Inpatient visit type may be called "IPD", "Inpatient", "Admission", or "Emergency" in the Bahmni UI
- Oxygen saturation (SpO2) may appear as "Pulse oximetry" in the Bahmni UI
- Respiratory rate may be labeled as "Breaths per minute"
- Verifier accepts temperature OR respiratory rate as respiratory vitals (flexible)
