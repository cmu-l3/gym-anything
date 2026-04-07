# Task: Prescribe Medication for Acute Condition

## Overview

**Difficulty**: Hard
**Estimated Steps**: 20-30
**Domain Knowledge Required**: Pharmacology basics, prescription writing, EHR medication module

## Clinical Scenario

You are a healthcare provider seeing a patient who has presented with an acute upper respiratory infection. After examining the patient, you need to prescribe an appropriate antibiotic and document the encounter properly.

**Patient**: Milo Feil (DOB: 1983-12-12)
**Chief Complaint**: Sore throat, fever for 3 days
**Diagnosis**: Streptococcal pharyngitis (Strep throat)
**History**: Patient has no known drug allergies

### Clinical Context

According to IDSA (Infectious Diseases Society of America) guidelines for Group A Streptococcal Pharyngitis:
- First-line treatment: Penicillin V or Amoxicillin
- Duration: 10 days for oral penicillin/amoxicillin
- Alternative for penicillin allergy: Azithromycin or first-generation cephalosporin

The patient needs a prescription for Amoxicillin to treat strep throat.

## Task Description

1. **Log in** to OpenEMR (admin/pass)
2. **Search for and open** patient Milo Feil's chart
3. **Verify** the patient has no documented drug allergies
4. **Navigate** to the prescription/medication module
5. **Create a new prescription** with the following details:
   - **Drug**: Amoxicillin 500 MG Oral Capsule
   - **Dosage**: 500 mg
   - **Frequency**: Three times daily (TID)
   - **Duration**: 10 days
   - **Quantity**: 30 capsules
   - **Refills**: 0 (no refills for acute infection)
   - **Instructions**: "Take one capsule by mouth three times daily for 10 days. Complete entire course even if feeling better."
6. **Save** the prescription

## Success Criteria

The task is considered successful if:

1. **Prescription exists** for patient Milo Feil (pid = 7)
2. **Drug name** contains "Amoxicillin" (case-insensitive)
3. **Prescription is new** (created after task start time)
4. **Quantity** is between 20-30 (appropriate for 10-day course)
5. **Active status** (not discontinued)
6. **No duplicate** of an existing amoxicillin prescription in last 30 days

## Verification Method

The verifier will:
1. Query `prescriptions` table for new entries matching pid=7
2. Verify drug name matches expected antibiotic
3. Check prescription date is after task start
4. Validate quantity is clinically appropriate
5. Confirm prescription status is active

## Database Schema Reference

```sql
-- Prescriptions table
SELECT id, patient_id, drug, drug_id, quantity, size, unit,
       date_added, date_modified, active, rxnorm_drugcode
FROM prescriptions
WHERE patient_id = 7
AND drug LIKE '%Amoxicillin%'
ORDER BY date_added DESC;

-- Patient verification
SELECT pid, fname, lname, DOB FROM patient_data WHERE pid = 7;

-- Allergy check (should be empty or no penicillin allergy)
SELECT * FROM lists WHERE pid = 7 AND type = 'allergy';
```

## Ground Truth Data

**Patient Details** (from sample_patients.sql):
- pid: 7
- Name: Milo Feil
- DOB: 1983-12-12
- Sex: Male
- Address: 422 Farrell Path Unit 69, Somerville, MA 02143
- Marital Status: Married

**Existing Medical History**:
- Patient has encounters documented in the system
- No documented penicillin allergy (safe to prescribe amoxicillin)

**Standard Amoxicillin Prescription**:
- RxNorm: 308182 (Amoxicillin 250 MG) or 308191 (Amoxicillin 500 MG)
- Common brand names: Amoxil, Trimox
- Standard dose for strep: 500mg TID x 10 days or 1000mg BID x 10 days

## Why This Task is Complex

1. **Safety verification**: Must check allergies before prescribing penicillin-class antibiotic
2. **Drug selection**: Must choose appropriate formulation and strength
3. **Dosage calculation**: Must understand that 500mg TID x 10 days = 30 capsules
4. **Clinical appropriateness**: Prescription must follow clinical guidelines
5. **Multiple form fields**: Drug name, dose, frequency, quantity, instructions, refills
6. **Module navigation**: Must find and use the prescription/medication module
7. **Patient context**: Must ensure prescribing to correct patient

## OpenEMR Navigation Path

1. Login → Dashboard
2. Patient → Finder (search "Milo Feil")
3. Click patient name → Patient Summary
4. Check Medical Problems and Allergies tabs
5. Click "Rx" or navigate to Fee Sheet/Prescriptions
6. Click "Add Prescription" or equivalent
7. Fill prescription form:
   - Search/select drug (Amoxicillin 500 MG)
   - Enter quantity (30)
   - Enter directions/sig
   - Set refills (0)
8. Save prescription

## Alternative Acceptable Prescriptions

The verifier should accept variations that are clinically equivalent:
- Amoxicillin 250 MG, quantity 60 (250mg x 2 TID = 500mg TID)
- Amoxicillin 500 MG, quantity 30 (standard)
- Amoxicillin 875 MG, quantity 20 (875mg BID x 10 days - also guideline-compliant)

## Edge Cases to Consider

- Patient already has a recent amoxicillin prescription (unlikely but should verify new creation)
- Drug search returns multiple amoxicillin formulations (agent must select appropriate one)
- Different EHR versions may have different prescription workflow
- Sig (instructions) field may have character limits

## Realistic Medical Rationale

This task mirrors real clinical workflow where:
- Providers must verify allergies before prescribing
- Antibiotic selection follows evidence-based guidelines
- Prescription details must be complete for pharmacy processing
- 10-day course is standard for strep throat to prevent rheumatic fever
- Patient instructions should emphasize completing full course
- Zero refills appropriate for acute, self-limiting infection

## Contraindications to Document

If the patient HAD a penicillin allergy, appropriate alternatives would be:
- Azithromycin (Z-pack): 500mg day 1, then 250mg days 2-5
- Cephalexin: 500mg BID x 10 days (use with caution if severe penicillin allergy)

This complexity is NOT part of this task but could be a future advanced variant.
