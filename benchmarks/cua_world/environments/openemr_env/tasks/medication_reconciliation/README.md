# Task: Medication Reconciliation

## Overview

**Difficulty**: Very Hard
**Estimated Steps**: 25-40
**Domain Knowledge Required**: Pharmacology, medication safety, drug interactions, clinical workflow

## Clinical Scenario

You are a clinical pharmacist or nurse performing medication reconciliation for a patient who is being admitted to the hospital. The patient brought a list of medications from their home, and you need to compare it against what's documented in the EHR, identify discrepancies, and update the record accordingly.

**Patient**: Edmund Walker (DOB: 1954-05-02)
**Context**: Hospital admission for elective procedure
**Current Status**: Multiple chronic conditions, on several medications

### Patient-Reported Medication List (from home)

The patient states they are currently taking:

1. **Lisinopril 20 mg** - once daily for blood pressure
2. **Metformin 500 mg** - twice daily for diabetes
3. **Atorvastatin 40 mg** - once daily at bedtime for cholesterol
4. **Aspirin 81 mg** - once daily for heart protection
5. **Omeprazole 20 mg** - once daily for acid reflux

### Medications in EHR (OpenEMR)

The EHR shows different medications - this is the discrepancy to identify and reconcile.

## Task Description

1. **Log in** to OpenEMR (admin/pass)
2. **Search for and open** patient Edmund Walker's chart
3. **Review current medications** in the EHR
4. **Compare** against the patient-reported list (provided above)
5. **Identify discrepancies**:
   - Medications in EHR not reported by patient
   - Medications reported by patient not in EHR
   - Dose differences
   - Frequency differences
6. **Update the EHR** to reflect the accurate current medication list:
   - Add missing medications (Lisinopril, Metformin, Atorvastatin, Aspirin, Omeprazole)
   - Discontinue medications no longer being taken
   - Correct any dose/frequency errors
7. **Document** a medication reconciliation note

## Success Criteria

The task is considered successful if:

1. **At least 3 new medications added** for patient Edmund Walker (pid = 25)
2. **Medications include** at least 2 of:
   - A blood pressure medication (Lisinopril, ACE inhibitor)
   - A diabetes medication (Metformin)
   - A statin (Atorvastatin)
   - Aspirin
   - A PPI (Omeprazole)
3. **Doses are reasonable** (within expected ranges for each drug)
4. **New prescriptions created after** task start time

## Verification Method

The verifier will:
1. Query `prescriptions` table for entries with patient_id=25
2. Count prescriptions added after task start time
3. Check for specific medication classes by drug name matching
4. Verify dose fields contain reasonable values
5. Confirm at least 3 of the 5 target medications are present

## Database Schema Reference

```sql
-- Current medications before task
SELECT id, drug, dosage, quantity, form, route, date_added, active
FROM prescriptions
WHERE patient_id = 25
ORDER BY date_added DESC;

-- Patient verification
SELECT pid, fname, lname, DOB FROM patient_data WHERE pid = 25;

-- After task: verify new medications
SELECT drug, dosage, date_added
FROM prescriptions
WHERE patient_id = 25
AND drug REGEXP 'Lisinopril|Metformin|Atorvastatin|Aspirin|Omeprazole'
AND date_added > '[TASK_START_TIME]';
```

## Ground Truth Data

**Patient Details** (from sample_patients.sql):
- pid: 25
- Name: Edmund Walker
- DOB: 1954-05-02 (age ~71)
- Sex: Male
- Address: 383 Crooks Camp, Norwell, MA
- Marital Status: Married

**Target Medication List** (what should be in EHR after reconciliation):

| Medication | Dose | Frequency | Indication |
|------------|------|-----------|------------|
| Lisinopril | 20 mg | Daily | Hypertension |
| Metformin | 500 mg | BID | Type 2 Diabetes |
| Atorvastatin | 40 mg | QHS (at bedtime) | Hyperlipidemia |
| Aspirin | 81 mg | Daily | Cardiovascular protection |
| Omeprazole | 20 mg | Daily | GERD prophylaxis |

**Drug Reference Information**:

| Drug | RxNorm | Class |
|------|--------|-------|
| Lisinopril 20 MG | 314076 | ACE Inhibitor |
| Metformin 500 MG | 860975 | Biguanide |
| Atorvastatin 40 MG | 617312 | Statin |
| Aspirin 81 MG | 243670 | Antiplatelet |
| Omeprazole 20 MG | 198053 | PPI |

## Why This Task is Complex

1. **Comparison task**: Must compare two lists and identify differences
2. **Multiple medications**: 5+ medications to potentially add/modify
3. **Clinical judgment**: Must recognize drug classes and appropriate dosing
4. **Workflow complexity**: Adding multiple prescriptions requires repetitive form completion
5. **Data accuracy**: Doses, frequencies must be entered correctly
6. **Safety implications**: Medication reconciliation is a patient safety critical process
7. **Documentation**: Should document the reconciliation process

## OpenEMR Navigation Path

1. Login → Dashboard
2. Patient → Finder (search "Edmund Walker")
3. Patient Summary → Medications tab
4. Review existing medications
5. For each new medication:
   - Click "Add Prescription" or Rx button
   - Search/select drug
   - Enter dose, frequency, quantity
   - Save
6. Optionally discontinue outdated medications
7. Document reconciliation in encounter note

## Medication Reconciliation Best Practices

According to Joint Commission National Patient Safety Goals:

1. **Obtain list**: Get current medication list from all sources
2. **Compare**: Identify discrepancies between lists
3. **Resolve**: Determine which medications patient should be taking
4. **Document**: Update medical record with reconciled list
5. **Communicate**: Share updated list with patient and care team

## Common Discrepancy Types

- **Omission**: Patient taking medication not in EHR
- **Commission**: EHR has medication patient is not taking
- **Dose difference**: Same drug, different dose
- **Frequency difference**: Same drug, different schedule
- **Duplication**: Two drugs in same class (therapeutic duplication)
- **Interaction**: Drug-drug interaction identified during reconciliation

## Drug-Drug Interactions to Note

The target medication list has no major interactions, but worth noting:
- Aspirin + ACE inhibitor: May reduce ACE inhibitor effectiveness (minor)
- Metformin: Monitor renal function (relevant for 71-year-old)
- All medications appropriate for this patient's age and conditions

## Edge Cases to Consider

- Patient may have existing medications that should remain
- Some medications may need to be discontinued, not just added
- Drug search may return multiple formulations (must select correct one)
- Dosing units vary (mg, mcg, tablets, etc.)
- Frequency terminology varies (QD, daily, once daily, etc.)

## Realistic Medical Rationale

Medication reconciliation is:
- **Required** by Joint Commission for hospital accreditation
- **Critical** at all care transitions (admission, transfer, discharge)
- **Protective** against medication errors (cause of 20% adverse drug events)
- **Time-consuming** but essential nursing/pharmacy function
- **Documented** as part of admission assessment

## Patient Safety Context

Medication errors during care transitions:
- 60% of patients have at least one medication discrepancy at admission
- 33% of discrepancies are potentially harmful
- Proper reconciliation reduces adverse drug events by 70%

This task tests an agent's ability to perform this safety-critical function accurately.

## Alternative Success Paths

The task can succeed via:
1. **Add all 5 medications** individually (most thorough)
2. **Add at least 3** of the key medications (minimum passing)
3. **Modify existing** if medications present but with wrong doses

## Future Enhancements

Advanced variants of this task could include:
- Identifying drug-drug interactions
- Recognizing therapeutic duplications
- Adjusting doses for renal function
- Documenting reason for each medication
- Generating patient-friendly medication list
