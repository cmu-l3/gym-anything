# Task: Document Clinical Encounter

## Overview

**Difficulty**: Very Hard
**Estimated Steps**: 30-45
**Domain Knowledge Required**: Clinical documentation, SOAP note format, ICD-10/SNOMED coding, vital signs interpretation

## Clinical Scenario

You are a healthcare provider who has just finished examining a patient presenting with symptoms of an upper respiratory infection. You need to document the complete clinical encounter including vitals, history, examination findings, assessment, and plan.

**Patient**: Karyn Metz (DOB: 1991-07-31)
**Visit Type**: Office Visit - Sick Visit
**Chief Complaint**: "Cough and runny nose for 5 days"

### Clinical Details to Document

**Vital Signs** (obtained by nurse):
- Blood Pressure: 118/76 mmHg
- Heart Rate: 72 bpm
- Temperature: 99.1°F (37.3°C) - low-grade fever
- Respiratory Rate: 16 breaths/min
- Oxygen Saturation: 98% on room air
- Weight: 145 lbs (65.8 kg)
- Height: 5'6" (167.6 cm)

**History of Present Illness (HPI)**:
- 32-year-old female presents with 5-day history of cough and nasal congestion
- Cough is nonproductive, worse at night
- Associated with clear rhinorrhea and mild sore throat
- Denies fever >100.4°F, shortness of breath, or chest pain
- No sick contacts known
- Has tried over-the-counter decongestants with minimal relief

**Physical Examination Findings**:
- General: Alert, oriented, appears mildly uncomfortable but not in distress
- HEENT:
  - Nasal mucosa erythematous with clear discharge
  - Pharynx mildly erythematous, no exudates
  - TMs clear bilaterally
- Lungs: Clear to auscultation bilaterally, no wheezes or crackles
- Heart: Regular rate and rhythm, no murmurs

**Assessment**:
- Acute upper respiratory infection (common cold)
- ICD-10: J06.9 (Acute upper respiratory infection, unspecified)
- SNOMED: 54150009 (Upper respiratory infection)

**Plan**:
1. Supportive care - rest and fluids
2. OTC symptomatic treatment:
   - Acetaminophen or ibuprofen for discomfort
   - Guaifenesin for cough
   - Pseudoephedrine or phenylephrine for congestion
3. Return precautions: seek care if fever >101°F, worsening symptoms, difficulty breathing, or symptoms lasting >10 days
4. No antibiotics indicated (viral etiology)

## Task Description

1. **Log in** to OpenEMR (admin/pass)
2. **Search for and open** patient Karyn Metz's chart
3. **Create a new encounter**:
   - Date: Today
   - Facility: Default clinic
   - Visit Category: Office Visit
   - Reason: Sick visit - respiratory symptoms
4. **Document vital signs** (may be in separate vitals form)
5. **Create clinical note** with:
   - Chief Complaint
   - History of Present Illness
   - Physical Examination
   - Assessment/Diagnosis (with ICD-10 code J06.9)
   - Plan
6. **Add diagnosis** to the encounter (J06.9 or equivalent)
7. **Save and close** the encounter

## Success Criteria

The task is considered successful if:

1. **New encounter exists** for patient Karyn Metz (pid = 9)
2. **Encounter date** is today or within last 24 hours
3. **Vitals documented** with at least:
   - Blood pressure (systolic 110-130, diastolic 70-85)
   - Temperature (98-100°F range)
4. **Diagnosis attached** containing:
   - "respiratory" OR "URI" OR "J06" in diagnosis field
5. **Clinical note present** containing keywords:
   - "cough" AND ("runny nose" OR "rhinorrhea" OR "congestion")

## Verification Method

The verifier will:
1. Query `form_encounter` for new encounter with pid=9 and today's date
2. Query `form_vitals` linked to encounter for vital signs
3. Query `billing` or `lists` for diagnosis codes attached to encounter
4. Query clinical note forms for required documentation elements
5. Verify encounter was created after task start time

## Database Schema Reference

```sql
-- Encounter table
SELECT id, date, reason, pid, encounter, facility_id
FROM form_encounter
WHERE pid = 9
ORDER BY date DESC LIMIT 1;

-- Vitals linked to encounter
SELECT * FROM form_vitals
WHERE pid = 9
ORDER BY date DESC LIMIT 1;

-- Diagnosis codes (may be in billing or lists)
SELECT * FROM billing
WHERE pid = 9 AND encounter = <encounter_id>;

-- Or check encounter-linked diagnosis
SELECT * FROM lists
WHERE pid = 9 AND type = 'medical_problem'
AND begdate = CURDATE();

-- Patient verification
SELECT pid, fname, lname, DOB FROM patient_data WHERE pid = 9;
```

## Ground Truth Data

**Patient Details** (from sample_patients.sql):
- pid: 9
- Name: Karyn Metz
- DOB: 1991-07-31 (32 years old)
- Sex: Female
- Address: 181 Feest Passage Suite 64, Medfield, MA 02052
- Marital Status: Married

**Expected Vitals**:
| Vital | Value | Units |
|-------|-------|-------|
| BP Systolic | 118 | mmHg |
| BP Diastolic | 76 | mmHg |
| Heart Rate | 72 | bpm |
| Temperature | 99.1 | °F |
| Respiratory Rate | 16 | /min |
| O2 Saturation | 98 | % |
| Weight | 145 | lbs |
| Height | 66 | inches |

**Expected Diagnosis**:
- ICD-10: J06.9
- Description: Acute upper respiratory infection, unspecified
- SNOMED: 54150009

## Why This Task is Complex

1. **Multi-component documentation**: Encounter, vitals, note, and diagnosis are separate forms
2. **Data entry volume**: Many fields across multiple screens
3. **Clinical accuracy**: Values must be realistic and internally consistent
4. **Form navigation**: OpenEMR has multiple ways to enter clinical data
5. **Coding knowledge**: Must select appropriate ICD-10/SNOMED diagnosis
6. **Structured vs. free-text**: Mix of structured data entry and narrative documentation
7. **Time sensitivity**: Encounter date must match task execution date
8. **Workflow understanding**: Must follow proper clinical documentation workflow

## OpenEMR Navigation Path

### Option 1: Create encounter first, then forms
1. Login → Dashboard
2. Patient → Finder (search "Karyn Metz")
3. Patient Summary → Encounters → Add New Encounter
4. Fill encounter basics (date, reason, facility)
5. Save encounter
6. Within encounter: Add Forms → Vitals
7. Enter vital signs → Save
8. Add Forms → Clinical Note or SOAP Note
9. Enter documentation → Save
10. Add Diagnosis via Fees or Problem list

### Option 2: Fee Sheet workflow
1. After creating encounter
2. Fee Sheet → Add diagnosis codes
3. This links ICD-10 to encounter for billing

## Clinical Documentation Standards

The note should follow SOAP format:
- **S**ubjective: Chief complaint, HPI, ROS
- **O**bjective: Vitals, physical exam findings
- **A**ssessment: Diagnosis with clinical reasoning
- **P**lan: Treatment, patient education, follow-up

## Edge Cases to Consider

- OpenEMR version differences in form layouts
- Some installations may not have all form types enabled
- Vitals may be in separate module vs. within encounter
- Diagnosis coding may be in billing vs. assessment section
- Character limits on free-text fields

## Realistic Medical Rationale

This task mirrors the most fundamental clinical workflow:
- Every patient visit requires a documented encounter
- Complete documentation is required for:
  - Legal medical record
  - Continuity of care
  - Billing and reimbursement
  - Quality reporting
- SOAP format is universal standard
- Vital signs are essential objective data
- Diagnosis coding (ICD-10) required for insurance claims
- Plan must be actionable and include return precautions

## Quality Measures

Good clinical documentation includes:
- Pertinent positives AND negatives (what the patient does/doesn't have)
- Quantitative data (exact vital signs, not "normal")
- Specific timeline (5 days, not "several days")
- Medical decision-making rationale (why no antibiotics)
- Clear follow-up instructions
