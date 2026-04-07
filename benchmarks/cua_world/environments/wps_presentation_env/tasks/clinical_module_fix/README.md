# Task: clinical_module_fix

**Environment**: wps_presentation_env
**Difficulty**: very_hard
**Occupation**: Health Specialties Teachers (Postsecondary)
**Primary skill tested**: Content contamination detection, slide deletion, medical curriculum quality control

## Overview

A medical school emergency medicine department's ACLS (Adult Advanced Cardiovascular Life Support) lecture deck has been accidentally contaminated with slides from the PALS (Pediatric Advanced Life Support) curriculum. PALS uses fundamentally different drug doses (weight-based epinephrine 0.01 mg/kg vs. fixed adult dose 1 mg), different defibrillation energy levels (2 J/kg vs. adult 200 J), and different compression guidelines.

A course review memo at `/home/ga/Desktop/acls_review_memo.txt` describes the issue in general terms without naming which slides are problematic. The agent must read the memo, understand what PALS content looks like, scan the 22-slide deck, identify the contaminating slides, delete them, and save a corrected copy.

**Original file**: `/home/ga/Documents/ACLS_lecture.pptx` (22 slides — do not modify)
**Output file**: `/home/ga/Documents/ACLS_corrected.pptx` (should have 19 slides)

## What Makes This Very Hard

- The memo describes the issue in general medical terminology without identifying slide numbers
- The agent must distinguish adult ACLS content from pediatric PALS content based on clinical indicators (mg/kg dosing, Broselow tape, 2 J/kg defibrillation doses, etc.)
- PALS slides are interspersed throughout the deck, not grouped together
- The deck contains real clinical content so the agent cannot use simple keyword matching alone

## Contaminating Slides

Three slides contain PALS-specific content (positions are not revealed to the agent):
1. A PALS BLS overview slide with pediatric compression depth differences
2. A pediatric weight-based epinephrine dosing slide (0.01 mg/kg, Broselow tape)
3. A PALS shockable rhythms slide with pediatric defibrillation energy (2 J/kg, 4 J/kg)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Output file ACLS_corrected.pptx exists | 10 |
| Original ACLS_lecture.pptx unchanged (22 slides) | 10 |
| Each PALS slide removed (×3) | 20 each = 60 |
| Output slide count is 18–20 | 20 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Data Sources

- AHA ACLS 2020 Guidelines: Circulation. 2020;142(suppl 2):S366–S468
- Adult epinephrine dose: 1 mg IV/IO every 3–5 min (fixed, not weight-based)
- Pediatric epinephrine dose: 0.01 mg/kg IV/IO (weight-based) — PALS only
- Adult defibrillation: 200 J biphasic (not per-kg dosing) — ACLS 2020
- Pediatric defibrillation: 2 J/kg initial, 4 J/kg subsequent — PALS only
- PARAMEDIC2 Trial (NEJM 2018;379:711-21): epinephrine in adult cardiac arrest
- TTM2 Trial (NEJM 2021;384:2138-2149): targeted temperature management

## Verification Strategy

`export_result.sh` parses the output PPTX and scans every slide for PALS-specific keywords:
- "pals", "pediatric", "weight-based", "broselow", "0.01 mg/kg", "2 j/kg", "5 mg/kg"

Any slide containing these terms is flagged as PALS content remaining. The verifier awards 20 points for each of the 3 original PALS slides that have been successfully removed.
