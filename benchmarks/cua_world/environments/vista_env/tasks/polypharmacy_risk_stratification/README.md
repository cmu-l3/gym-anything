# Task: Polypharmacy Risk Stratification

**Difficulty**: very_hard
**Occupation**: Clinical Pharmacist / Clinical Nurse Specialist
**Environment**: VistA VEHU (Veterans Health Information Systems and Technology Architecture)

## Overview

You are a clinical pharmacist conducting a polypharmacy safety audit. Identify the 3 patients with the most active outpatient prescriptions in the VistA database and produce a ranked risk report.

## Technical Details

- **Primary global**: `^PS(55,DFN,"P",RxIEN)` — outpatient prescriptions per patient
- **Secondary global**: `^DPT(DFN,0)` — patient demographics (piece 1 = name)
- **Interface**: YDBGui Global Viewer or Octo SQL at the YDBGui URL

## Required Output

File: `/home/ga/Desktop/polypharmacy_report.txt`

Must contain:
1. Ranked list (#1, #2, #3) of patients by prescription count
2. Patient name, DFN, and prescription count for each
3. Clinical polypharmacy risk notes

## Verification

The verifier queries `^PS(55)` directly at evaluation time to compute the ground truth prescription counts, then checks the output file for correct patient names and counts.

Scoring:
- Container running: 10 pts
- File created during task: 20 pts
- File has content: 10 pts
- Top patient correctly identified: 30 pts
- 2nd and 3rd patients identified: 20 pts
- Accurate prescription count: 10 pts

Pass threshold: 60 points
