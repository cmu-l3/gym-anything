# Task: New Diabetes Patient Workup

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Endocrinology / Primary Care
**Difficulty**: Hard
**Patient**: Bonifacio Caput

## Occupational Context

This task reflects the real workflow of a primary care physician or endocrinologist completing an initial workup for a newly diagnosed Type 2 Diabetes Mellitus (T2DM) patient. Per ADA Standards of Medical Care in Diabetes, the initial visit requires: (1) documenting the diagnosis with ICD-10 coding, (2) performing baseline glycemic testing (HbA1c), (3) documenting drug allergies for safe prescribing, (4) initiating first-line pharmacotherapy (Metformin), and (5) scheduling a glycemic monitoring follow-up in 6–8 weeks.

## Scenario

**Bonifacio Caput** presents to Dr. Cameron Cordara's clinic with recent fasting glucose readings of 142 mg/dL and 138 mg/dL on two separate occasions. The physician confirms Type 2 Diabetes and must complete the full initial diabetes management workup in GNU Health.

## Goal (End State)

The end state must have **all five** of the following in GNU Health for patient Bonifacio Caput:

1. **Active condition record**: Type 2 Diabetes Mellitus, ICD-10 code **E11**, marked as active
2. **Drug allergy documented**: Penicillin allergy recorded for Bonifacio Caput, severity **Severe**, with reaction type indicating **Anaphylaxis** (or allergic reaction)
3. **Lab test order**: HbA1c (GLYCATED HEMOGLOBIN) lab test ordered for Bonifacio Caput — required as baseline glycemic measurement
4. **Prescription**: Metformin (any dose/formulation) prescribed for Bonifacio Caput, with Dr. Cordara as prescriber
5. **Follow-up appointment**: Scheduled with Dr. Cordara within **35 to 60 days** from today (standard T2DM follow-up interval for medication titration)

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Key Clinical Details

- **Patient**: Bonifacio Caput (find in the Patients list)
- **Physician**: Cordara, Cameron
- **Diagnosis code**: E11 (Type 2 Diabetes Mellitus)
- **Allergy**: Penicillin — this must be documented BEFORE prescribing, as it affects antibiotic choices; severity=Severe, reaction=Anaphylaxis or anaphylactic reaction
- **Lab test**: GLYCATED HEMOGLOBIN (HbA1c) — the diabetes monitoring gold standard
- **Medication**: Metformin (first-line T2DM therapy per ADA guidelines) — any dose (500mg, 850mg, or 1000mg), twice or once daily
- **Follow-up**: 35–60 days (to recheck HbA1c response to Metformin)

## Success Criteria

Completion requires all five criteria above, but partial credit is awarded for each:
- 20 pts per criterion = 100 pts total
- Pass threshold: ≥ 70 pts (completing at least 3–4 of the 5 steps)

## Verification Strategy

`export_result.sh` queries:
- gnuhealth_patient_disease for E11 code for Bonifacio Caput
- gnuhealth_patient_allergy for Penicillin allergy record
- gnuhealth_patient_lab_test for HbA1c order (test_type code = 'HBA1C')
- gnuhealth_prescription_order for new Metformin prescription
- gnuhealth_appointment for follow-up appointment in 35-60 day window

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient_disease` | patient, pathology, is_active | Diagnoses (ICD-10) |
| `gnuhealth_pathology` | id, code | ICD-10 code reference |
| `gnuhealth_patient_allergy` | patient, allergen, severity | Drug/food allergies |
| `gnuhealth_lab_test_type` | id, code='HBA1C', name | Lab test catalog |
| `gnuhealth_patient_lab_test` | patient_id, test_type | Lab orders |
| `gnuhealth_prescription_order` | patient, healthprof, date | Prescriptions |
| `gnuhealth_appointment` | patient, healthprof, appointment_date | Appointments |

## Edge Cases

- Metformin search is case-insensitive and matches any Metformin formulation (Glucophage, Fortamet, etc.)
- Allergy search checks `allergen` field for 'penicillin' case-insensitively
- The E11 disease check looks for records created AFTER the baseline snapshot (uses ID > baseline max)
- Follow-up appointment date window: task_start_date + 35 days to task_start_date + 60 days
