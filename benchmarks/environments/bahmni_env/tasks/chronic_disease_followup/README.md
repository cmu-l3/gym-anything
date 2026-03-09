# Task: Chronic Disease Follow-up Consultation

## Domain Context

Chronic disease management is one of the most common workflows in primary care and district hospital outpatient departments across sub-Saharan Africa and South Asia — the primary markets for Bahmni HIS. A clinical officer managing patients with Type 2 Diabetes mellitus (T2DM) and Essential Hypertension (HTN) must conduct structured follow-up consultations: recording vital signs to monitor disease control, documenting coded diagnoses, prescribing or renewing medications, and writing a clinical note. This is a core workflow that any Bahmni-trained clinician performs dozens of times per day.

## Goal

Complete a full chronic disease management follow-up consultation in Bahmni for Mohammed Al-Rashidi (BAH000022). By the end of the task, the following must exist in the system as part of his active OPD visit:

1. **Vital signs recorded** — at minimum blood pressure (systolic and diastolic), pulse rate, and at least one of weight or temperature
2. **At least two coded diagnoses** — one corresponding to Type 2 Diabetes mellitus and one to Essential Hypertension (or equivalent ICD-coded conditions)
3. **At least two drug prescriptions** — one medication appropriate for diabetes management (e.g., Metformin) and one for hypertension management (e.g., Amlodipine, Enalapril, or similar antihypertensive)
4. **A clinical note** — free-text clinical documentation of sufficient length (≥100 characters) saved in the consultation

## Success Criteria

| Criterion | Points | Verifier Check |
|-----------|--------|----------------|
| Vitals recorded (BP + pulse + at least one other) | 25 | OpenMRS obs query for systolic/diastolic/pulse concepts |
| Two diagnoses documented (T2DM + HTN category) | 25 | OpenMRS patientdiagnoses or encounter diagnoses query |
| Two drug orders saved | 25 | OpenMRS drug orders query for the encounter |
| Clinical note present (≥100 chars) | 15 | OpenMRS obs text concept or encounter notes |
| All data linked to correct patient (BAH000022) | 10 | Wrong-patient gate returns score=0 |
| **Pass threshold** | **70** | Score ≥ 70 |

## Verification Strategy

1. `export_result.sh` queries OpenMRS REST API and MySQL to extract:
   - Patient UUID verification
   - All encounters created after task start timestamp
   - Observations (vitals) in those encounters
   - Diagnoses attached to those encounters
   - Drug orders in those encounters
   - Any note-type observations

2. `verifier.py` checks:
   - FIRST: patient identifier matches BAH000022 → score=0 if wrong
   - Then: scores each independent criterion

## Schema Reference

Key OpenMRS tables and REST endpoints used:
- `encounter` — clinical visits/encounters
- `obs` — observations (vitals, notes, results)
- `encounter_diagnosis` — diagnoses coded to encounters
- `drug_order` — prescriptions
- REST: `/openmrs/ws/rest/v1/encounter?patient={uuid}&v=full`
- REST: `/openmrs/ws/rest/v1/order?patient={uuid}&t=drugorder&v=full`
- REST: `/openmrs/ws/rest/v1/obs?patient={uuid}&v=full`

CIEL concept UUIDs for vitals:
- Systolic BP: `5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Diastolic BP: `5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Pulse: `5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Weight (kg): `5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Temperature (C): `5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`

## Starting State

- Mohammed Al-Rashidi (BAH000022) exists in the system, created in setup
- He has a single prior encounter (demographic registration visit) but NO current OPD consultation
- No vitals, diagnoses, or prescriptions in the system for him
- An active OPD visit is started for him in setup_task.sh
- The browser is open to the Bahmni login page

## Edge Cases

- Agent must navigate to the correct patient — the system has 21+ patients
- The agent must identify that T2DM and HTN are the conditions to manage (given only in the task description)
- Drug names may vary (Metformin/Glibenclamide for DM; Amlodipine/Enalapril/Lisinopril for HTN)
- Verifier uses broad keyword matching for drug names to accommodate reasonable alternatives
