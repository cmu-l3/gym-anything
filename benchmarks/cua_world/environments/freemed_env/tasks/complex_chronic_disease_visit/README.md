# complex_chronic_disease_visit

## Task Overview

**Role**: Nurse Practitioner / Physician Assistant
**Difficulty**: Hard
**Timeout**: 600 seconds (10 minutes)
**Max Steps**: 80

A Nurse Practitioner must complete clinical documentation for a complex follow-up visit in FreeMED. The patient Dwight Dach has been identified with two new chronic conditions during today's visit. This task requires navigating to four distinct sections of the FreeMED EMR system and completing a multi-component clinical encounter.

## Clinical Scenario

Patient **Dwight Dach** (DOB: 1998-03-21, male, ID 6) presents as a 27-year-old for a routine visit. During the encounter, elevated blood pressure readings and fasting glucose results confirm two new diagnoses. The NP must document all components of this encounter before the patient leaves.

## Required Actions (4 independent subtasks)

1. **Problem List — 2 Diagnoses**
   - Essential Hypertension: ICD-9 code `401.9`, onset `2025-03-15`
   - Prediabetes: ICD-9 code `790.29`, onset `2025-03-15`

2. **Vital Signs**
   - BP: 142/88 mmHg
   - HR: 82 bpm
   - Temperature: 98.6°F
   - Weight: 198 lbs
   - Height: 70 inches

3. **Prescription**
   - Drug: Lisinopril 10mg
   - Quantity: 30 tablets
   - Dosage: 1 tablet daily
   - Refills: 2

4. **Clinical Progress Note**
   - Must reference both hypertension and prediabetes/diabetes
   - Must mention treatment plan (Lisinopril)

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Hypertension diagnosis (ICD 401.9) in problem list | 20 | `current_problems` table |
| Prediabetes diagnosis (ICD 790.29) in problem list | 20 | `current_problems` table |
| Vital signs recorded with correct values (±tolerance) | 25 | `vitals` table |
| Lisinopril prescription with correct dose/quantity/refills | 20 | `medications` table |
| Clinical note mentioning hypertension AND diabetes/prediabetes | 15 | `pnotes` table |
| **Total** | **100** | |

**Pass threshold**: ≥ 70 points

## Ground Truth

- Patient ID: 6 (Dwight Dach)
- Hypertension ICD: 401.9
- Prediabetes ICD: 790.29
- BP systolic: 142 (±5)
- BP diastolic: 88 (±5)
- HR: 82 (±5)
- Temperature: 98.6 (±0.5°F)
- Weight: 198 (±3 lbs)
- Height: 70 (±1 inch)
- Drug: Lisinopril (case-insensitive match)
- Dose: 10mg
- Quantity: 30
- Refills: 2

## Database Schema Reference

```sql
-- Problem list
SELECT problem, problem_code FROM current_problems WHERE ppatient = 6;

-- Vitals
SELECT bp_systolic, bp_diastolic, heart_rate, temperature, weight, height
FROM vitals WHERE patient = 6 ORDER BY id DESC LIMIT 1;

-- Prescriptions
SELECT mdrugs, mdose, mquantity, mrefills FROM medications WHERE mpatient = 6;

-- Clinical notes
SELECT pnotetext FROM pnotes WHERE pnotespat = 6 ORDER BY id DESC LIMIT 1;
```

## FreeMED Navigation (for reference only)

- Problem List: Patient Chart → Problems tab
- Vitals: Patient Chart → Vitals tab
- Medications/Prescriptions: Patient Chart → Medications/Rx tab
- Clinical Notes: Patient Chart → Notes tab or Progress Notes

## Why This Is Hard

The agent must navigate to **four different sections** of the FreeMED interface, each with a different data entry pattern. The agent must discover how to reach each section, enter structured clinical data (ICD codes, medication details), and write a free-text clinical note — all for the same patient, in a single session.
