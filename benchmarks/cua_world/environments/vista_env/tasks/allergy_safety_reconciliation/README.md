# Task: Allergy Safety Reconciliation

**Difficulty**: very_hard
**Occupation**: Medication Safety Coordinator / Clinical Pharmacist
**Environment**: VistA VEHU

## Overview

Cross-reference the allergy documentation system and the pharmacy records system in VistA to identify patients who appear in BOTH. Rank these patients by combined allergy + prescription burden (combined_score = allergy_count + rx_count) and produce a drug-allergy reconciliation report.

## Technical Details

This task requires working across TWO separate VistA globals:
- **Allergy data**: `^GMRD(120.8,IEN,0)` — each IEN is one allergy record; piece 1 = patient DFN
- **Pharmacy data**: `^PS(55,DFN,"P",RxIEN)` — outpatient prescriptions keyed by patient DFN
- **Demographics**: `^DPT(DFN,0)` — patient demographics (piece 1 = name)

The agent must identify DFNs present in BOTH globals (set intersection), then compute combined scores.

## Required Output

File: `/home/ga/Desktop/allergy_safety_report.txt`

Must contain:
1. Total count of patients found in BOTH allergy and pharmacy records
2. Top 5 patients ranked by combined allergy + prescription count
3. Patient name, identifier, allergy count, prescription count, and combined score for each
4. Risk designations: High Risk (combined > 15), Medium Risk (8-15), Low Risk (< 8)
5. Recommended action for the highest-risk patient

## Verification

Scoring:
- Container running: 10 pts
- File created during task: 20 pts
- File has content: 10 pts
- Top combined-risk patient identified: 35 pts
- Intersection count present in file: 15 pts
- Risk designation language present: 10 pts

Pass threshold: 60 points
