# Task: neurologist_mri_ventricle_morphometry

## Overview

**Difficulty**: Very Hard
**Occupation**: Neurologist
**Clinical Scenario**: Normal pressure hydrocephalus (NPH) assessment with Evans index

A neurologist evaluates a brain MRI for ventriculomegaly using the Evans index —
a quantitative ratio of frontal horn width to biparietal diameter. The agent must
navigate to specific neuroanatomical levels, make four separate measurements at
three different slice levels, calculate a derived index, and make a clinical
determination.

## Task Requirements

The agent must:
1. Open the MR series from `/home/ga/DICOM/studies/brain_mri_nph/`
2. Apply appropriate brain window/level settings
3. Navigate to the axial slice showing the widest frontal horns and measure:
   - Maximum frontal horn width (outer wall to outer wall)
   - Maximum inner biparietal diameter at the same level
4. Calculate Evans index (frontal horn width / biparietal diameter)
5. Navigate inferiorly to measure the third ventricle width
6. Navigate to temporal horns and measure the wider temporal horn width
7. Annotate each measurement with its anatomical label
8. Export annotated measurement slice to `/home/ga/DICOM/exports/evans_index_measurement.png`
9. Write a structured report to `/home/ga/DICOM/exports/nph_assessment_report.txt`

## Verification Criteria (100 points)

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| Export image | 20 | PNG exists, modified after task start, size >= 20KB |
| Report file | 15 | TXT exists, modified after task start, >= 50 chars |
| Evans index | 30 | Report contains a decimal 0.15-0.60 and mentions Evans |
| Multiple measurements | 20 | Report contains >= 3 distinct mm measurements (1-200mm) |
| Clinical determination | 15 | Report mentions ventriculomegaly/hydrocephalus/NPH/normal |

**Pass threshold**: 60/100

## What Makes This Hard

- Must navigate to 3 different axial levels (frontal horns, third ventricle, temporal horns)
- Must make 4 separate measurements at specific neuroanatomical landmarks
- Must calculate a derived metric (Evans index = ratio of two measurements)
- Must make a clinical determination based on the calculated ratio
- Requires knowledge of brain MR anatomy and NPH diagnostic criteria
- Combines: MR-specific W/L + multi-level navigation + measurement × 4 + calculation + clinical judgment + export + report

## Data

**Source**: Rubomedical.com MR brain scan sample (real clinical DICOM, publicly shared)
**Location**: `/home/ga/DICOM/studies/brain_mri_nph/`

## Schema Reference

Result JSON path: `/tmp/neurologist_ventricle_result.json`
