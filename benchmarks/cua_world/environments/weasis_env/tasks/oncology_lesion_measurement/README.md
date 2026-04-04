# oncology_lesion_measurement

**Occupation**: Radiologist
**Industry**: Oncology Imaging
**Difficulty**: very_hard
**Max Steps**: 85
**Timeout**: 660 seconds

## Task Description

A Radiologist performs a RECIST 1.1 (Response Evaluation Criteria In Solid Tumors) baseline assessment on a CT scan for an oncology patient. This is the foundational step in tumor response monitoring: identifying target lesions, measuring their longest diameters, computing the Sum of Longest Diameters (SLD), and documenting the baseline for future comparison scans.

## Clinical Context

RECIST 1.1 is the international standard used in clinical oncology trials and practice to evaluate tumor response to treatment. At each assessment (baseline, cycle 2, cycle 4, etc.), the radiologist measures the longest diameter of each designated target lesion in the axial plane. The SLD at baseline establishes the reference denominator; subsequent assessments compare against this to classify Complete Response (CR), Partial Response (PR ≥30% decrease), Stable Disease (SD), or Progressive Disease (PD ≥20% increase).

A correct baseline RECIST report requires:
- At least two distinct lesion measurements in the axial plane
- Millimeter precision for each measurement
- An explicit SLD computation
- A documented baseline assessment statement

## Required Steps

1. Load CT from `/home/ga/DICOM/studies/oncology_ct/`
2. Apply soft tissue window (W:400, L:50)
3. Measure Lesion 1 (longest diameter in axial plane): record location and mm
4. Export CT slice showing Lesion 1 as `/home/ga/DICOM/exports/recist_lesion1.png`
5. Measure Lesion 2 (longest diameter in axial plane): record location and mm
6. Export CT slice showing Lesion 2 as `/home/ga/DICOM/exports/recist_lesion2.png`
7. Write RECIST report to `/home/ga/DICOM/exports/recist_report.txt`:
   - Lesion 1: anatomical location + longest diameter (mm)
   - Lesion 2: anatomical location + longest diameter (mm)
   - SLD = Lesion1 + Lesion2 (in mm)
   - Baseline assessment statement

## Scoring (100 points)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| Lesion screenshots exported | 30 | 15 pts each: recist_lesion1/2.png, new, ≥20KB |
| 2+ new PNGs in exports (any naming) | 15 | Fallback for alternate filenames |
| RECIST report exists with content | 30 | File new, ≥40 chars |
| RECIST quality: SLD + measurements + baseline | 25 | SLD keyword (10) + 2 measurements (10) + baseline statement (5) |

**Pass threshold**: 60 points

### Partial credit rules

- One lesion image correct, one missing: 15/30 on criterion 1
- One new PNG instead of two: 8/15
- Report exists but <40 chars: 10-20/30
- Only one measurement in report: 5/10 on measurement sub-criterion
- SLD not stated: 0/10 on SLD sub-criterion

## What Makes This Hard

1. **RECIST methodology knowledge**: The agent must understand that RECIST requires the longest diameter in the axial plane — not just any measurement on any slice or plane
2. **Two separate measurements**: The agent must identify two distinct anatomical structures, measure each, and save screenshots of each separately — three distinct export actions
3. **Quantitative computation**: The agent must compute SLD = lesion1 + lesion2 and state it explicitly in the report — a mathematical step requiring the agent to use measurement values it just read from the tool
4. **Report structure**: The RECIST report has a specific required structure (per-lesion location + diameter, SLD, baseline statement) that goes beyond free-form description
5. **Lesion discrimination**: The agent must choose structures that are genuinely distinct, not two measurements on the same structure
6. **Window application**: Soft tissue window must be applied before export so the exported images show the correct windowing for clinical use

## Data Source

- CT scan: rubomedical.com CT DICOM sample (dicom_viewer_0002.zip)
  — Copied to `/home/ga/DICOM/studies/oncology_ct/` by `setup_task.sh`
  — Real (non-synthetic) CT DICOM dataset

## Verification Files

- `/tmp/oncology_lesion_measurement_result.json` — written by `export_result.sh`
- `/home/ga/DICOM/exports/recist_lesion1.png` — screenshot showing Lesion 1 measurement
- `/home/ga/DICOM/exports/recist_lesion2.png` — screenshot showing Lesion 2 measurement
- `/home/ga/DICOM/exports/recist_report.txt` — RECIST 1.1 baseline assessment report
