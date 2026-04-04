# Task: ct_cardiac_measurements

## Overview

**Difficulty**: Very Hard
**Occupation**: Hospitalist
**Clinical Scenario**: Cardiothoracic ratio assessment for cardiomegaly screening

A hospitalist evaluates a chest CT for cardiomegaly using the cardiothoracic ratio (CTR).
The agent must apply cardiac imaging window settings, navigate to the correct axial level,
place measurements using Weasis measurement tools, export annotated images, and write
a clinical report — all requiring knowledge of cardiology imaging protocols.

## Task Requirements

The agent must:
1. Open the CT series from `/home/ga/DICOM/studies/chest_ct/`
2. Apply appropriate cardiac window/level settings (W:400, L:40 or equivalent)
3. Navigate to the axial slice with the maximum transverse cardiac diameter
4. Place a line measurement across the widest cardiac diameter
5. Place a second line measurement across the widest inner thoracic diameter at the same level
6. Export the annotated slice to `/home/ga/DICOM/exports/cardiac_analysis.png`
7. Write a report to `/home/ga/DICOM/exports/cardiac_report.txt` containing:
   - Cardiac width (mm)
   - Thoracic width (mm)
   - Calculated CTR (cardiac/thoracic as a decimal)

## Verification Criteria (100 points)

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| Export image | 25 | PNG exists, modified after task start, size ≥ 30KB |
| Report file | 30 | TXT exists, modified after task start, ≥ 20 chars |
| CTR value | 30 | Report contains decimal 0.25–0.80 |
| Measurements | 15 | Report contains ≥ 2 distinct numerical values (40–300 range) |

**Pass threshold**: 60/100

## What Makes This Hard

- Agent must know cardiac imaging window settings (not told which values to use)
- Must scroll through CT slices to find the maximum cardiac diameter level
- Must use Weasis measurement tools to place two separate line measurements
- Must compute and record CTR from two measurements
- Must export both annotated image and structured text report
- Combines: W/L adjustment + measurement placement + image export + text report writing

## Data

**Source**: Rubomedical.com CT scan sample (real clinical DICOM, publicly shared)
**Location**: `/home/ga/DICOM/studies/chest_ct/`
**Content**: Multi-slice CT scan with chest/abdominal content

## Schema Reference

Result JSON path: `/tmp/ct_cardiac_measurements_result.json`

```json
{
  "task_start": <unix_timestamp>,
  "image_exists": <bool>,
  "image_is_new": <bool>,
  "image_size_kb": <int>,
  "report_exists": <bool>,
  "report_is_new": <bool>,
  "report_size_bytes": <int>,
  "ctr_value_found": "<decimal string>",
  "cardiac_width_mm": "<number string>",
  "any_new_png_exports": "<comma-separated paths>"
}
```
