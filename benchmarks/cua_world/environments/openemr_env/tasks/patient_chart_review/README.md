# Task: Patient Chart Review and Summary

## Overview

**Difficulty**: Hard
**Estimated Steps**: 15-25
**Domain Knowledge Required**: Medical record review, chronic disease management, medication knowledge

## Clinical Scenario

You are a healthcare provider preparing for a patient's upcoming appointment. The patient has multiple chronic conditions and you need to review their chart and create a pre-visit summary to prepare for the encounter.

**Patient**: Mariana Hane (DOB: 1978-06-24)
**Purpose**: Pre-visit planning for chronic disease management

### Clinical Context

This patient has a complex medical history with multiple chronic conditions requiring ongoing management. A thorough chart review before the visit helps:
- Identify gaps in care
- Review medication adherence patterns
- Check for overdue screenings or tests
- Prepare discussion points for the visit

## Task Description

1. **Log in** to OpenEMR (admin/pass)
2. **Search for and open** patient Mariana Hane's chart
3. **Review and document** (in a text file saved to the desktop):
   - **Demographics**: Full name, DOB, age, address, phone
   - **Active Problems**: List all current medical conditions with dates
   - **Current Medications**: List all active prescriptions with doses
   - **Allergies**: Document any allergies or "No Known Allergies"
   - **Recent Encounters**: Last 3 visit dates and reasons
   - **Care Gaps**: Identify any chronic conditions without recent follow-up

4. **Save summary** to `/home/ga/Desktop/patient_summary.txt`

## Required Output Format

The summary file must contain structured information:

```
PATIENT CHART REVIEW SUMMARY
============================
Date of Review: [Today's Date]
Prepared By: [Provider]

PATIENT DEMOGRAPHICS
--------------------
Name: [Full Name]
DOB: [Date of Birth]
Age: [Calculated Age]
Sex: [M/F]
Address: [Full Address]
Phone: [Phone Number]

ACTIVE MEDICAL PROBLEMS
-----------------------
1. [Condition] - Diagnosed: [Date]
2. [Condition] - Diagnosed: [Date]
...

CURRENT MEDICATIONS
-------------------
1. [Drug Name] [Dose] - [Frequency]
2. [Drug Name] [Dose] - [Frequency]
...

ALLERGIES
---------
[List allergies or "No Known Drug Allergies (NKDA)"]

RECENT ENCOUNTERS
-----------------
1. [Date] - [Visit Type/Reason]
2. [Date] - [Visit Type/Reason]
3. [Date] - [Visit Type/Reason]

CARE RECOMMENDATIONS
--------------------
[Based on conditions and last visits, identify any care gaps]
```

## Success Criteria

The task is considered successful if:

1. **Summary file exists** at `/home/ga/Desktop/patient_summary.txt`
2. **Patient correctly identified**: Name contains "Mariana" AND "Hane"
3. **DOB correct**: Contains "1978-06-24" or "June 24, 1978"
4. **At least 1 medical problem** listed
5. **At least 1 medication** listed
6. **File is substantial**: At least 500 characters (not a stub)

## Verification Method

The verifier will:
1. Copy `/home/ga/Desktop/patient_summary.txt` from environment
2. Parse file contents for required sections
3. Verify patient identifiers match expected values
4. Check that medical data extracted matches database
5. Validate file length meets minimum threshold

## Database Schema Reference

```sql
-- Patient demographics
SELECT pid, fname, lname, DOB, sex, street, city, state,
       postal_code, phone_home, phone_cell
FROM patient_data WHERE lname = 'Hane';

-- Medical problems
SELECT title, diagnosis, begdate, enddate, outcome
FROM lists
WHERE pid = 11 AND type = 'medical_problem';

-- Medications
SELECT drug, drug_id, dosage, quantity, date_added, active
FROM prescriptions
WHERE patient_id = 11 AND active = 1;

-- Allergies
SELECT title, diagnosis, begdate
FROM lists
WHERE pid = 11 AND type = 'allergy';

-- Recent encounters
SELECT date, reason, encounter
FROM form_encounter
WHERE pid = 11
ORDER BY date DESC LIMIT 5;
```

## Ground Truth Data

**Patient Details** (from sample_patients.sql):
- pid: 11
- Name: Mariana Hane
- DOB: 1978-06-24 (age ~47)
- Sex: Female
- Address: 999 Kuhn Forge, Lowell, MA 01851
- Phone: (555) 555-XXXX
- Marital Status: Married

**Expected Medical Conditions**:
Based on Synthea data patterns, this patient likely has:
- Hypertension (common in this age group)
- Possibly hyperlipidemia
- Check for prediabetes/obesity

**Expected Medications**:
- Antihypertensive (if hypertension present)
- Possibly statin (if hyperlipidemia)

**Note**: Exact conditions depend on what was loaded from Synthea conversion. The verifier should flexibly check that SOME medical data was extracted, not specific conditions.

## Why This Task is Complex

1. **Information synthesis**: Must gather data from multiple EHR sections
2. **Navigation across modules**: Demographics, problems, medications, encounters are separate areas
3. **External output**: Must create a properly formatted text file
4. **Clinical reasoning**: Identifying care gaps requires understanding chronic disease management
5. **Data extraction accuracy**: Must correctly transcribe medical information
6. **Formatting requirements**: Output must be structured and readable
7. **Age calculation**: Must correctly calculate age from DOB

## OpenEMR Navigation Path

1. Login → Dashboard
2. Patient → Finder (search "Mariana Hane")
3. Patient Summary page shows overview
4. **Demographics tab**: Personal information
5. **Medical Problems tab**: Active conditions
6. **Medications tab**: Current prescriptions
7. **Allergies tab**: Drug/environmental allergies
8. **Encounters tab** or **History**: Past visits

For creating the file:
- May need to open text editor (gedit, xed, etc.)
- Or use Firefox to access a notes area
- Or navigate to file manager to create file

## Clinical Significance

Pre-visit chart review is critical for:
- **Efficient visits**: Provider prepared with key information
- **Safety**: Review medications for interactions
- **Quality**: Identify overdue screenings
- **Patient satisfaction**: Shows provider knows their history
- **Care coordination**: Identify specialist referrals, pending tests

## Care Gap Examples

Common care gaps to identify:
- Hypertensive patient without BP check in >6 months
- Diabetic patient without HbA1c in >3 months
- Patient over 50 without colonoscopy documentation
- Female patient without mammogram per guidelines
- Missing annual wellness visit

## Edge Cases to Consider

- Patient may have minimal chart data (new patient)
- Some sections may be empty (no allergies, no recent encounters)
- How to handle "No data" gracefully in summary
- File save location must be accessible
- Text editor availability varies by system configuration
- Character encoding for special characters in names/addresses

## Alternative Approaches

The task can be completed via:
1. **Manual transcription**: View each section, type into text file
2. **Copy-paste**: Select text from EHR, paste into editor
3. **Print preview**: Some EHR systems have summary print functions
4. **Export function**: Check if OpenEMR has patient summary export

## Realistic Medical Rationale

This task reflects standard practice in:
- **Primary Care**: Complex patients need visit preparation
- **Care Transitions**: New providers need chart orientation
- **Specialist Referrals**: Summary accompanies referral requests
- **Care Coordination**: Nurses prepare summaries for physicians
- **Quality Improvement**: Chart audits identify care gaps
