# Task: radtech_ct_multiwindow_pathology_survey

## Overview

**Difficulty**: Very Hard
**Occupation**: Radiologic Technologist
**Clinical Scenario**: Multi-window CT quality survey for systematic pathology review

A radiologic technologist must perform a complete multi-window survey of a CT scan,
applying four distinct window/level presets, measuring a diagnostically relevant
structure at each, annotating findings, and exporting annotated views — all requiring
knowledge of which anatomical structures are best visualized at each window preset.

## Task Requirements

The agent must:
1. Open the CT series from `/home/ga/DICOM/studies/multiwindow_ct/`
2. Apply FOUR different window/level presets and for each:
   - Navigate to a diagnostically relevant slice
   - Place a measurement on an appropriate anatomical structure
   - Add a text annotation labeling the structure
   - Export the annotated view as a separate PNG to `/home/ga/DICOM/exports/`
3. Write a comprehensive multi-window survey report to
   `/home/ga/DICOM/exports/multiwindow_survey_report.txt`

Required window presets:
- Lung window (W:1500, L:-500)
- Bone window (W:2000, L:300)
- Soft tissue window (W:350, L:50)
- Mediastinal window (W:400, L:40)

## Verification Criteria (100 points)

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| PNG exports | 30 | At least 3 PNG files exist in exports/, modified after task start, each ≥ 20KB |
| Report file | 20 | TXT exists, modified after task start, ≥ 100 chars |
| Window values in report | 25 | Report mentions at least 3 of the 4 window presets (W/L values or names) |
| Measurements in report | 25 | Report contains at least 3 distinct numerical measurements (10-300mm range) |

**Pass threshold**: 60/100

## What Makes This Hard

- Agent must apply FOUR different window/level presets in sequence (not told exact values)
- Must know which anatomy is best visualized at each preset (domain knowledge)
- Must cycle through 4 complete iterations of: change W/L → navigate → measure → annotate → export
- Must keep track of which windows and structures have been done
- Must produce 4 separate PNG exports with distinct filenames
- Combines: W/L expertise × 4 + measurement placement × 4 + annotation × 4 + export × 4 + report

## Data

**Source**: Rubomedical.com CT scan sample (real clinical DICOM, publicly shared)
**Location**: `/home/ga/DICOM/studies/multiwindow_ct/`
**Content**: Multi-slice CT scan

## Schema Reference

Result JSON path: `/tmp/radtech_multiwindow_result.json`
