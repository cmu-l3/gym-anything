# Task: Polypharmacy Deprescribing Review

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Geriatric Medicine / Clinical Pharmacy
**Difficulty**: Very Hard
**Patient**: Roberto Carlos

## Occupational Context

This task reflects the clinical workflow of a geriatric clinical pharmacist conducting a medication reconciliation following a fall in an elderly patient. Falls are the leading cause of injury-related morbidity in older adults, and antihypertensive medications — particularly ACE inhibitors — are a well-documented risk factor for orthostatic hypotension leading to falls. The pharmacist must document the fall injury, identify the offending medication, record the adverse drug reaction, prescribe a safer alternative, order post-fall laboratory workup, and arrange follow-up. This requires navigating conditions, allergies/adverse reactions, prescriptions, labs, and scheduling modules.

## Scenario

**Roberto Carlos**, a 68-year-old male with known hypertension, was found on the floor at home after a syncopal episode. Emergency services brought him to the hospital. Initial assessment reveals orthostatic hypotension likely secondary to his current ACE inhibitor (Enalapril) therapy. He sustained a contusion to the right hip but no fracture on imaging.

As the clinical pharmacist, you must complete the medication safety review: document the fall-related injury diagnosis, record the ACE inhibitor adverse drug reaction in his allergy/adverse reaction profile, prescribe a safer antihypertensive alternative (an ARB such as Losartan, or a calcium channel blocker), order appropriate post-fall laboratory studies, and schedule a medication review follow-up.

## Goal (End State)

All five of the following must be documented in GNU Health for Roberto Carlos:

1. **Fall-related injury diagnosis**: ICD-10 W-code (W01, W06, W10, W18, W19) or S-code (contusion/injury) — an active condition record
2. **ACE inhibitor adverse drug reaction**: An allergy/adverse reaction record documenting Enalapril (or generic ACE inhibitor) as the causative agent
3. **Safer antihypertensive prescription**: A new prescription for a non-ACE-inhibitor antihypertensive (ARB like Losartan, CCB like Amlodipine, or thiazide diuretic)
4. **Post-fall laboratory workup**: At least **2** lab orders (CBC to check for anemia/bleeding, BMP/CMP for metabolic/renal status)
5. **Medication review follow-up**: Appointment scheduled **7–21 days** from today

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Success Criteria

Score of 70+ (out of 100) to pass. Each criterion is worth 20 points with partial credit.

## Contamination Note

Setup pre-seeds an ACE inhibitor allergy record on Ana Betz (wrong patient) as a distractor. The verifier validates all records belong to Roberto Carlos.

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient_disease` | patient, pathology, is_active | Fall diagnosis |
| `gnuhealth_pathology` | id, code, name | ICD-10 codes |
| `gnuhealth_patient_allergy` | patient, allergen, severity | Adverse reactions |
| `gnuhealth_prescription_order` | patient, healthprof | Prescriptions |
| `gnuhealth_patient_lab_test` | patient_id, test_type | Lab orders |
| `gnuhealth_appointment` | patient, appointment_date | Follow-up |
