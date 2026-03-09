# specialist_referral_workup

## Task Overview

**Role**: Physician Assistant / Nurse Practitioner
**Difficulty**: Hard
**Timeout**: 600 seconds
**Max Steps**: 80

A Physician Assistant must complete full clinical documentation for a neurological workup encounter and initiate a specialist referral. This task requires navigating to five distinct sections of FreeMED: problem list, allergies, prescriptions, clinical notes, and referrals.

## Clinical Scenario

**Kelle Crist** (DOB: 2002-10-18, female, ID 9) is a 22-year-old presenting with recurring migraines with visual aura. After the neurological exam, the PA decides to initiate a neurology referral and prescribe abortive therapy. During the encounter, the patient discloses a new Aspirin allergy that needs to be documented.

## Required Actions (5 independent subtasks)

1. **Problem List — Diagnosis**
   - Migraine with aura: ICD-9 `346.00`, onset `2024-06-01`

2. **Allergy Documentation**
   - Allergen: Aspirin
   - Reaction: angioedema
   - Severity: severe

3. **Prescription — Abortive Migraine Therapy**
   - Drug: Sumatriptan 50mg
   - Quantity: 9 tablets
   - Dosage: take 1 tablet at onset of migraine, may repeat in 2 hours
   - Refills: 0

4. **Clinical Progress Note**
   - Must mention migraine/neuro findings and referral decision

5. **Specialist Referral**
   - Specialty: Neurology
   - Provider: Dr. Patricia Nguyen
   - Reason: migraines with visual aura (or similar)
   - Date: 2025-04-10

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Migraine diagnosis (ICD 346.00) in problem list | 20 | `current_problems` table |
| Aspirin allergy documented (angioedema, severe) | 20 | `allergies_atomic` table |
| Sumatriptan 50mg prescription (qty 9, 0 refills) | 20 | `medications` table |
| Clinical note with migraine/neuro content | 20 | `pnotes` table |
| Neurology referral created (Nguyen, 2025-04-10) | 20 | `referrals` table |
| **Total** | **100** | |

**Pass threshold**: ≥ 70 points

## Database Schema Reference

```sql
-- Problem list
SELECT problem, problem_code FROM current_problems WHERE ppatient = 9;

-- Allergies
SELECT allergy, reaction, severity FROM allergies_atomic WHERE patient = 9;

-- Prescriptions
SELECT mdrugs, mdose, mquantity, mrefills FROM medications WHERE mpatient = 9;

-- Clinical notes
SELECT pnotetext FROM pnotes WHERE pnotespat = 9 ORDER BY id DESC LIMIT 1;

-- Referrals
SELECT referral_to, specialty, reason, referral_date FROM referrals WHERE patient = 9;
```

## Why This Is Hard

This task requires navigating to **five completely different sections** of FreeMED: the problem list, allergy module, prescription writer, clinical notes editor, and the referral module. Each section has a different UI. The agent must document a coherent clinical encounter across all five without losing context about the patient.
