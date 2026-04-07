# Task: Perioperative Appendectomy Management

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Acute Care Surgery / General Surgery
**Difficulty**: Very Hard
**Patient**: Luna

## Occupational Context

This task reflects the clinical workflow of a general surgeon managing a patient with acute appendicitis requiring emergent surgical intervention. In real-world practice, the surgeon must coordinate across multiple EHR modules — documenting the surgical diagnosis, ordering pre-operative laboratory workup, prescribing perioperative antibiotic prophylaxis, performing a clinical evaluation with operative findings, and scheduling post-discharge follow-up — all within a compressed timeframe typical of acute surgical cases.

## Scenario

Patient **Luna** presented to the emergency department with acute right lower quadrant abdominal pain, fever (38.5°C), rebound tenderness at McBurney's point, and elevated inflammatory markers. Clinical assessment and imaging confirm **acute appendicitis**. As the attending surgeon, you must now complete the full perioperative management protocol in the GNU Health system before proceeding to the operating room.

The clinical picture is clear, but the EHR documentation must be comprehensive: the appendicitis diagnosis must be formally recorded, pre-operative labs must be ordered to clear the patient for anesthesia, perioperative antibiotics must be prescribed per surgical prophylaxis guidelines, a clinical evaluation must document the surgical findings and vital signs, and a post-operative follow-up must be arranged for wound check and pathology review.

## Goal (End State)

The end state must have **all five** of the following documented in the GNU Health database for patient Luna:

1. **Acute appendicitis diagnosis**: ICD-10 code **K35** (or subcodes K35.2, K35.3, K35.80, K35.89) as an active condition
2. **Clinical evaluation**: A documented encounter with fever (temperature ≥ 38.0°C) and tachycardia (heart rate ≥ 100 bpm) reflecting the acute presentation
3. **Pre-operative laboratory workup**: At least **3** lab test orders — the standard pre-op panel includes CBC, CMP/BMP, and Coagulation/PT-INR
4. **Perioperative antibiotic prescription**: Ceftriaxone, Metronidazole, or Piperacillin-Tazobactam (standard surgical prophylaxis for appendicitis)
5. **Post-discharge follow-up appointment**: Scheduled **7–14 days** from today for wound check and pathology review

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Key Clinical Details

- **Patient**: Luna (single name — find in the Patients list)
- **Diagnosis**: Acute appendicitis, ICD-10 K35 (K35.80 = unspecified acute appendicitis without abscess)
- **Clinical findings**: Fever ≥ 38.0°C, tachycardia ≥ 100 bpm, RLQ tenderness
- **Pre-op labs**: CBC, CMP (or BMP), Coagulation panel (PT/INR) — minimum 3 lab orders
- **Antibiotic**: Ceftriaxone 2g IV (or Metronidazole 500mg IV, or Piperacillin-Tazobactam 4.5g IV)
- **Follow-up**: 7–14 days post-surgery for wound check and pathology review

## Success Criteria

All five criteria must be met simultaneously for full score:
1. An active K35.x appendicitis disease record exists for Luna **created after task start**
2. A clinical evaluation exists for Luna with temperature ≥ 38.0°C AND heart rate ≥ 100 bpm
3. At least 3 new lab test orders exist for Luna **created after task start**
4. A prescription containing Ceftriaxone, Metronidazole, or Piperacillin exists for Luna **created after task start**
5. A follow-up appointment exists for Luna **7–14 days** from task start date

Score of 70+ (out of 100) to pass; partial credit is awarded.

## Verification Strategy

`export_result.sh` queries PostgreSQL for new records matching each criterion using baseline max-ID comparison. `verifier.py` applies multi-criterion scoring (5 × 20 pts) with partial credit for near-matches.

## Contamination Note

Setup pre-seeds a K29.x gastritis diagnosis on Roberto Carlos as a distractor. The verifier checks that all records belong to Luna (wrong-target = score 0).

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient` | id, puid, party | Patient records |
| `party_party` | id, name, lastname | Patient names |
| `gnuhealth_patient_disease` | patient, pathology, is_active | Diagnoses |
| `gnuhealth_pathology` | id, code, name | ICD-10 codes |
| `gnuhealth_patient_evaluation` | patient, temperature, heart_rate | Clinical encounters |
| `gnuhealth_patient_lab_test` | patient_id, test_type | Lab orders |
| `gnuhealth_prescription_order` | patient, healthprof | Prescriptions |
| `gnuhealth_appointment` | patient, appointment_date | Appointments |

## Edge Cases

- Luna has only a first name (no lastname) — patient search must handle this
- The K35 code has multiple subcodes; any K35.x subcode is accepted
- Antibiotic name matching is case-insensitive and allows partial matches
- Pre-existing records from other tasks are excluded via baseline max-ID filtering
