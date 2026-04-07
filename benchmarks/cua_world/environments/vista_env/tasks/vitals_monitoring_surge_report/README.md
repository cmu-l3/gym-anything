# Task: Vitals Monitoring Surge Report

**Difficulty**: very_hard
**Occupation**: Critical Care Nurse / Charge Nurse
**Environment**: VistA VEHU

## Overview

Identify the 5 patients with the most vital sign recordings in `^GMR(120.5)` as a monitoring intensity review for an ICU step-down unit.

## Technical Details

- **Primary global**: `^GMR(120.5,IEN,0)` — each IEN is one vital measurement; piece 1 = patient DFN
- **Secondary global**: `^DPT(DFN,0)` — patient demographics (piece 1 = name)

## Required Output

File: `/home/ga/Desktop/vitals_monitoring_report.txt`

Must contain:
1. Top 5 patients ranked by vital sign count
2. Patient name, DFN, and count for each
3. Total number of vital sign entries in the database

## Verification

Scoring:
- Container running: 10 pts
- File created during task: 20 pts
- File has content: 10 pts
- Top patient identified: 30 pts
- 2nd and 3rd patients identified: 15 pts
- Total count accurate: 15 pts

Pass threshold: 60 points
