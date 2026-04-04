# Task: hepatitis_b_surveillance_form_entry

## Overview

A disease surveillance coordinator must use three different Epi Info 7 modules in sequence to create a Hepatitis B case surveillance system from scratch:

1. **MakeView** — Design a case report form
2. **Enter** — Enter 8 real case records using the form
3. **Classic Analysis** — Analyze the entered data and produce a report

This is the most complex task in the suite because it requires sequential use of three distinct modules and tests both data entry and analysis capabilities in a single workflow.

## Professional Context

**Primary occupation**: Clinical Data Manager (O*NET importance: 93) / Epidemiologist / Community Health Worker

This workflow represents a real surveillance activity:
- Disease coordinators design surveillance forms in MakeView
- Field staff enter case reports using Enter
- Epidemiologists analyze the accumulated data in Classic Analysis

This is exactly how local/state health departments have used Epi Info 7 for decades to manage notifiable disease surveillance.

## Goal (End State)

Three deliverables must exist:

1. **`C:\Users\Docker\Documents\HepBSurveillance.prj`** — Epi Info project file with CaseReport form containing 11 specified fields
2. **Database with 8 entered case records** — the MDB backing the .prj file must contain 8 Hepatitis B case records with realistic data
3. **`C:\Users\Docker\hepb_analysis.html`** — Classic Analysis output containing FREQ and MEANS analyses of the entered data

## Required Form Fields

The CaseReport form must include these fields (exact names matter for Analysis step):
| Field | Type | Notes |
|-------|------|-------|
| CaseID | Text (10 chars) | Case identifier |
| ReportDate | Date | Date case was reported |
| County | Text (30 chars) | County of residence |
| Sex | Text (10 chars) | Male/Female |
| AgeAtDiagnosis | Number (integer) | Age in years |
| HBsAg_Positive | Yes/No | Hepatitis B surface antigen |
| Anti_HBc_Positive | Yes/No | Hepatitis B core antibody |
| HBeAg_Status | Text (10 chars) | Positive/Negative/Unknown |
| SourceOfInfection | Text (50 chars) | Injection drug use, Sexual contact, etc. |
| VaccinationStatus | Text (20 chars) | Unvaccinated/Partial/Complete |
| ClinicalStatus | Text (20 chars) | Acute/Chronic/Perinatal |

## Required Case Records (8 total)

Enter realistic Hepatitis B case data. Vary the fields across records:
- County: Mix of different counties (e.g., King, Pierce, Snohomish, Clark, Spokane)
- Sex: Mix of Male and Female
- AgeAtDiagnosis: Range from 20s to 60s
- SourceOfInfection: Include at least 3 different sources (injection drug use, sexual contact, unknown, perinatal, healthcare setting)
- VaccinationStatus: Mix of Unvaccinated, Partial, Complete
- ClinicalStatus: Mix of Acute, Chronic

## Workflow Steps

### Step 1: MakeView
```
- Open Epi Info 7 launcher
- Click "Make View" or navigate to MakeView module
- Create new project: C:\Users\Docker\Documents\HepBSurveillance
- Create form named "CaseReport"
- Add all 11 required fields with correct types
- Save the form
```

### Step 2: Enter
```
- Open Enter module
- Open C:\Users\Docker\Documents\HepBSurveillance.prj
- Enter 8 case records with realistic data
- Save all records
```

### Step 3: Classic Analysis
```
READ {C:\Users\Docker\Documents\HepBSurveillance.mdb}:CaseReport
ROUTEOUT "C:\Users\Docker\hepb_analysis.html" REPLACE
FREQ Sex
FREQ County
FREQ SourceOfInfection
FREQ VaccinationStatus
FREQ ClinicalStatus
MEANS AgeAtDiagnosis
ROUTEOUT
```

## Verification Strategy

The verifier checks:
1. **Project file exists and is newly created** (20 pts) — `.prj` file with mtime > task_start
2. **MDB database exists with records** (25 pts) — MDB exists and contains CaseReport table with >= 6 records (using 32-bit PowerShell Jet OLEDB query)
3. **HTML analysis output exists and is newly created** (15 pts)
4. **HTML contains analysis of entered data** (25 pts) — FREQ/MEANS output with Hepatitis B-related field names
5. **HTML file is substantial** (15 pts) — size > 3KB

Pass threshold: 60/100

## Scoring Breakdown

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| PRJ file exists + new | 20 | File mtime > task_start |
| MDB has records (>=6) | 25 | 32-bit PowerShell Jet OLEDB record count |
| HTML exists + new | 15 | File mtime > task_start |
| HTML has HepB analysis content | 25 | Field name keywords + analysis types in HTML |
| HTML is substantial | 15 | File size > 3KB |

## Why This Is Extremely Hard

Unlike single-module tasks, this requires:
1. Knowing how to use MakeView to design a form (not just run Analysis commands)
2. Correctly adding all 11 fields with the right types in MakeView
3. Switching to Enter module and navigating its interface
4. Entering 8 complete records with realistic data
5. Switching to Analysis and running the right READ command (pointing to the form database)
6. Running 5 FREQ + 1 MEANS + ROUTEOUT

Most agents will complete only 1-2 of the 3 modules, earning partial credit.
