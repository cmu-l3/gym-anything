# Task: Cross-System Patient Data Completeness

**Difficulty**: very_hard
**Occupation**: Health Informatics Specialist / VistA System Analyst
**Environment**: VistA VEHU

## Overview

Find the single patient with the highest composite clinical data volume across all four VistA clinical globals, and compile a comprehensive clinical profile. This is the most complex task in the set — it requires cross-referencing four independent globals simultaneously.

## Technical Details

Globals used:
- `^PS(55,DFN,"P",*)` — outpatient prescriptions (3 pts each)
- `^GMR(120.5,IEN,0)` — vital signs (1 pt each)
- `^GMRD(120.8,IEN,0)` — allergies (2 pts each)
- `^AUPNPROB(IEN,0)` — problem list (2 pts each)
- `^DPT(DFN,0)` — demographics (piece 1 = name, piece 2 = DOB, piece 3 = sex)

Composite score formula:
```
composite = rx_count*3 + vital_count + allergy_count*2 + problem_count*2
```

## Required Output

File: `/home/ga/Desktop/patient_profile.txt`

Must contain:
1. Header: "COMPREHENSIVE PATIENT PROFILE..."
2. Patient identification: name, DFN, DOB, sex
3. Counts for all 4 clinical domains
4. Composite data completeness score
5. Clinical narrative (3+ sentences)

## Verification

Scoring:
- Container running: 10 pts
- File created during task: 20 pts
- File has content (>300 chars): 10 pts
- Correct top-composite patient identified: 35 pts
- 3+ clinical domains covered: 15 pts
- Clinical narrative present: 10 pts

Pass threshold: 60 points
