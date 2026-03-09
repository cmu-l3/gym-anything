# oc_complex_intake — Complex Patient Transfer Intake

## Overview

**Difficulty**: Hard
**Occupation**: Clinical Data Manager
**Environment**: OpenClinic GA Hospital Information System

A multi-step patient intake workflow for a new transfer patient. The agent must complete all 5 steps of the clinical onboarding process for Amara Nwosu, a patient arriving from a regional hospital with existing chronic conditions.

## Domain Context

Clinical data managers process patient transfers by entering all required demographic and clinical data into the hospital's HIS. This involves patient registration (administrative), clinical encounter creation, medication reconciliation, lab order placement, and scheduling — each in a different module of the EHR system.

## Task Setup (Starting State)

Amara Nwosu does NOT exist in the system at task start (setup_task.sh removes any prior entries). The agent must create the entire patient record from scratch.

| Required Data | Value |
|---|---|
| First Name | AMARA |
| Last Name | NWOSU |
| Date of Birth | 1972-04-19 |
| Gender | Female (F) |
| Country | NG (Nigeria) |
| Diagnoses | Type 2 Diabetes + Hypertension |

Required medications to add as chronic:

| Medication | Product ID | Dosage |
|---|---|---|
| Metformin 500mg | 9002 | 1 tablet twice daily |
| Amlodipine 5mg | 9004 | 1 tablet once daily |

Required lab tests to order:

| Test | Lab Code |
|---|---|
| HbA1c | HBA1C |
| Creatinine | CREAT |

## Expected End State

After task completion:
- Amara Nwosu registered in `ocadmin_dbo.adminview` with DOB=1972-04-19, gender=F
- At least 1 health record in `openclinic_dbo.healthrecord` for her patient ID
- Both Metformin (9002) and Amlodipine (9004) in `oc_chronicmedications` for her patient ID
- HBA1C and CREAT orders in `requestedlabanalyses` placed after task start timestamp
- At least 1 appointment in `oc_planning` for her patient ID

## Scoring

| Criterion | Points | Condition |
|---|---|---|
| C1: Patient registered with correct demographics | 20 | Amara found, DOB=1972-04-19, gender=F |
| C2: Clinical encounter created | 20 | health record count >= 1 |
| C3: Both chronic medications added | 20 | Metformin AND Amlodipine present (10 pts if only one) |
| C4: Both labs ordered after task start | 20 | HBA1C AND CREAT ordered (10 pts if only one) |
| C5: Follow-up appointment scheduled | 20 | appointment count >= 1 |

**Pass threshold**: 60/100 (at least 3 complete steps)
**Do-nothing state**: 0/100 (Amara not registered → all criteria fail) → `passed=False`

## Verification Strategy

- `setup_task.sh` records task start timestamp to `/tmp/complex_intake_start_ts`
- `export_result.sh` queries both `ocadmin_dbo` and `openclinic_dbo` for Amara's intake state
- New lab orders are detected by comparing `requestdatetime >= start_dt`
- Result written to `/tmp/oc_complex_intake_result.json`
- `verifier.py` copies JSON via `copy_from_env`, evaluates five criteria with partial credit

## Key Database Tables

- `ocadmin_dbo.adminview` — patient demographics (firstname, lastname, dateofbirth, sex, personid)
- `openclinic_dbo.healthrecord` — clinical encounter records (personId)
- `openclinic_dbo.oc_chronicmedications` — chronic medications (OC_CHRONICMED_PATIENTID, OC_CHRONICMED_PRODUCTID)
- `openclinic_dbo.requestedlabanalyses` — lab test orders (patientid, analysiscode, requestdatetime)
- `openclinic_dbo.oc_planning` — appointments (OC_PLANNING_PATIENTID)
- `openclinic_dbo.oc_products` — medication catalog (OC_PRODUCT_OBJECTID, OC_PRODUCT_NAME)

## Why This Is Hard

- Requires navigating 4 distinct modules: Patient Registration, Clinical, Lab, Planning
- Demographics must be entered precisely (DOB format, gender code, country code)
- Medications must be found in the product catalog by name (Metformin, Amlodipine)
- Lab codes (HBA1C, CREAT) must be searched/selected from a large list
- No cross-module navigation hints provided in the task description
- All 5 steps required; partial completion < pass threshold
