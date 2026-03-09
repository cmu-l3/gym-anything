# Task: Hypertension Care Protocol

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Internal Medicine / Chronic Disease Management
**Difficulty**: Hard
**Patient**: Roberto Carlos

## Occupational Context

This task reflects the real workflow of an internist or family physician managing a patient newly diagnosed with essential hypertension in a hospital outpatient setting. In GNU Health, a comprehensive hypertension management protocol requires coordinating across multiple clinical modules: the patient's problem list (conditions), laboratory ordering, pharmacy (prescriptions), and scheduling — exactly mirroring real-world clinical practice guidelines (JNC 8 / ESH/ESC 2023 Hypertension Guidelines).

## Scenario

Patient **Roberto Carlos** has been referred to Dr. Cameron Cordara for elevated blood pressure readings taken at a community screening. Clinical review confirms a new diagnosis of essential hypertension. The physician must initiate a complete management protocol per standard of care.

## Goal (End State)

The end state must have **all four** of the following in the GNU Health database for patient Roberto Carlos:

1. **Active chronic condition record**: Essential Hypertension, ICD-10 code **I10**, marked as active, assigned to Dr. Cordara
2. **Lab test order**: A **Lipid Panel** (or similar cardiovascular risk screening) lab test ordered for Roberto Carlos (to assess CV risk as required per hypertension guidelines)
3. **Prescription**: **Amlodipine 5 mg**, once daily (first-line CCB for hypertension), prescribed by Dr. Cordara, with at minimum a 30-day supply
4. **Follow-up appointment**: Scheduled with Dr. Cordara within **18 to 42 days** from today (to assess medication response per standard protocol)

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Key Clinical Details

- **Patient**: Roberto Carlos (find in the Patients list)
- **Physician**: Cordara, Cameron (the only health professional to use)
- **Diagnosis code**: I10 (Essential Hypertension, primary hypertension)
- **Medication**: Amlodipine 5 mg oral, once daily — a first-line calcium channel blocker
- **Lab test**: Lipid Panel (cardiovascular risk assessment — required for all newly diagnosed hypertensive patients)
- **Follow-up timeframe**: 18–42 days (to check BP response to medication)

## Success Criteria

All four of the following must be true simultaneously:
1. An active I10 disease record exists for Roberto Carlos that was **created after task start**
2. An Amlodipine prescription exists for Roberto Carlos that was **created after task start**
3. A Lipid Panel (or any cardiovascular lab) order exists for Roberto Carlos **created after task start**
4. An appointment exists for Roberto Carlos with Dr. Cordara **between 18 and 42 days** from task start date

Score of 70+ (out of 100) to pass; partial credit is awarded.

## Verification Strategy

`export_result.sh` queries the PostgreSQL database for:
- Baseline counts of patient_disease, prescription_order, lab_test, and appointment records
- New records for Roberto Carlos created since baseline
- ICD-10 code I10 in the disease record
- Amlodipine keyword in prescription data
- Appointment date within the 18–42-day window

`verifier.py` applies multi-criterion scoring based on the exported JSON.

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient` | id, puid, party | Patient records |
| `party_party` | id, name (first), lastname | Patient names |
| `gnuhealth_patient_disease` | patient, pathology, is_active | Diagnoses |
| `gnuhealth_pathology` | id, code, name | ICD-10 codes |
| `gnuhealth_prescription_order` | patient, date, healthprof | Prescriptions |
| `gnuhealth_patient_lab_test` | patient_id, test_type, date_requested | Lab orders |
| `gnuhealth_appointment` | patient, appointment_date, healthprof | Appointments |

## Edge Cases

- Roberto Carlos may have pre-existing conditions — the verifier checks only for **new** records created after task start using ID comparison
- The "wrong target" check fails immediately if the prescription or appointment belongs to a different patient
- Amlodipine search is case-insensitive and allows partial name matches (e.g., "amlodipine besylate")
- Appointment date validation uses a ±1 day tolerance to handle timezone edge cases
