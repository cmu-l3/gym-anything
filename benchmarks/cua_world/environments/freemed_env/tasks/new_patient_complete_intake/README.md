# new_patient_complete_intake

## Task Overview

**Role**: Medical Assistant / Health Information Specialist
**Difficulty**: Hard
**Timeout**: 600 seconds
**Max Steps**: 80

A Medical Assistant must complete a full new patient intake in FreeMED. This requires first registering the patient with all demographics, then navigating through four different clinical sections to document her complete medical history. This task combines patient registration with multi-domain clinical documentation.

## Clinical Scenario

**Helena Vasquez** (DOB: 1978-08-14, female) is a new patient transferring her care to this clinic. She is a 46-year-old woman with two well-established chronic conditions and a known drug allergy. The Medical Assistant must register her and enter her complete medical history before her first clinical appointment.

## Required Actions (5 independent subtasks)

1. **Register New Patient**
   - First name: Helena
   - Last name: Vasquez
   - Date of birth: 1978-08-14
   - Sex: Female
   - Address: 789 Commonwealth Ave, Boston, MA 02215
   - Phone: 617-555-3892
   - Email: helena.vasquez@email.test

2. **Problem List — 2 Diagnoses**
   - Type 2 Diabetes Mellitus: ICD-9 `250.00`, onset `2019-01-15`
   - Essential Hypertension: ICD-9 `401.9`, onset `2021-06-10`

3. **Prescription**
   - Drug: Metformin 1000mg
   - Quantity: 90 tablets
   - Dosage: 2 tablets daily
   - Refills: 5

4. **Allergy**
   - Allergen: Sulfonamides (or Sulfa drugs / Sulfa)
   - Reaction: skin rash (or rash)
   - Severity: moderate

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Patient Helena Vasquez registered with correct demographics | 25 | `patient` table |
| 2 diagnoses (diabetes + hypertension) added | 25 | `current_problems` table |
| Metformin 1000mg prescription (qty 90, 5 refills) | 25 | `medications` table |
| Sulfonamides allergy documented (moderate, rash) | 25 | `allergies_atomic` table |
| **Total** | **100** | |

**Pass threshold**: ≥ 70 points

## Database Schema Reference

```sql
-- Patient registration
SELECT id, ptfname, ptlname, ptdob, ptsex, ptcity, ptstate, ptzip, pthphone, ptemail
FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez';

-- Problem list (using discovered patient ID)
SELECT problem, problem_code FROM current_problems WHERE ppatient = <id>;

-- Prescriptions
SELECT mdrugs, mdose, mquantity, mrefills FROM medications WHERE mpatient = <id>;

-- Allergies
SELECT allergy, reaction, severity FROM allergies_atomic WHERE patient = <id>;
```

## Why This Is Hard

The agent must: (1) navigate the patient registration workflow and fill a complex demographic form, (2) find the newly registered patient, (3) navigate to four different clinical sections for a brand new patient. Unlike modifying an existing chart, the agent must first CREATE the patient and then locate them before entering any clinical data.
