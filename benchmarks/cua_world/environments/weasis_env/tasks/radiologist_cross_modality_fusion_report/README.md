# Task: radiologist_cross_modality_fusion_report

## Overview

**Difficulty**: Very Hard
**Occupation**: Radiologist
**Clinical Scenario**: Cross-modality CT vs MR imaging correlation and comparison

A radiologist must load and compare two different imaging modalities (CT and MRI)
of the same patient, find corresponding anatomy across both, make comparable
measurements, calculate the inter-modality measurement difference, and write
a comparative report discussing the relative strengths of each modality.

## Task Requirements

The agent must:
1. Open BOTH CT (`/home/ga/DICOM/studies/crossmod_ct/`) and MR (`/home/ga/DICOM/studies/crossmod_mr/`) datasets
2. Arrange for simultaneous viewing (split layout or tabs)
3. On CT: apply soft tissue window, navigate to identifiable anatomy, measure and annotate
4. On MR: find corresponding anatomy, apply MR W/L, measure the same structure, annotate
5. Calculate percentage difference between modality measurements
6. On CT: switch to bone window, measure a bony landmark
7. Export CT view as `/home/ga/DICOM/exports/ct_crossmod.png`
8. Export MR view as `/home/ga/DICOM/exports/mr_crossmod.png`
9. Write comparative report to `/home/ga/DICOM/exports/crossmodality_report.txt`

## Verification Criteria (100 points)

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| PNG exports (2) | 25 | At least 2 new PNGs, each >= 15KB |
| Report file | 15 | TXT exists, modified after task start, >= 100 chars |
| Both modalities in report | 25 | Report mentions both "CT" and "MR"/"MRI" with measurements |
| Measurements | 20 | Report contains >= 3 distinct numerical measurements |
| Comparative commentary | 15 | Report contains comparative language (advantage/superior/better/resolution) |

**Pass threshold**: 60/100

## What Makes This Hard

- Must load TWO separate DICOM datasets into Weasis simultaneously
- Must navigate between modalities and find corresponding anatomy (cross-reference)
- Must apply THREE different W/L presets (CT soft tissue, CT bone, MR)
- Must make comparable measurements on two different modalities
- Must calculate a derived metric (percentage difference)
- Must write comparative commentary requiring domain knowledge
- Combines: dual-dataset loading + cross-modality correlation + 3 W/L presets + calculation + comparative analysis

## Data

**Sources**: Rubomedical.com CT and MR scan samples (real clinical DICOM, publicly shared)
**CT Location**: `/home/ga/DICOM/studies/crossmod_ct/`
**MR Location**: `/home/ga/DICOM/studies/crossmod_mr/`

## Schema Reference

Result JSON path: `/tmp/radiologist_crossmod_result.json`
