# Task: allergist_series_contamination_cleanup

## Overview

**Difficulty**: Very Hard
**Occupation**: Allergist/Immunologist
**Clinical Scenario**: Series contamination cleanup for clinical presentation

An allergist prepares a chest CT series for presentation but discovers that MR brain
images have been accidentally mixed in during a PACS migration. The agent must use
DICOM header inspection to classify each file, identify the contaminants by modality
and patient information, remove them, and document the cleanup. This task uses the
contamination injection pattern from task_creation_notes.

## Task Requirements

The agent must:
1. Inspect DICOM files in `/home/ga/DICOM/studies/airway_series/`
2. Identify which files are contaminants (wrong modality, different patient)
3. Remove or quarantine the contaminating files to `/home/ga/DICOM/quarantine/`
4. Verify remaining files are all consistent CT images
5. Write report to `/home/ga/DICOM/exports/contamination_report.txt`

## Injected Contaminants (ground truth, not given to agent)

4 MR brain DICOM files mixed into a CT chest directory. They differ from legitimate
files in: Modality (MR vs CT), PatientName/ID, StudyDescription.

## Verification Criteria (100 points)

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| Contaminants removed | 35 | At least 3 of the 4 MR files no longer in target directory |
| CT files preserved | 20 | Original CT file count minus contaminant count still present |
| Report file | 15 | TXT exists, modified after task start, >= 50 chars |
| Report content | 15 | Report mentions modality difference (CT vs MR) |
| Quarantine/cleanup documented | 15 | Report mentions number of files removed |

**Pass threshold**: 55/100 (lower per contamination injection guidelines)

## What Makes This Hard

- Agent must classify files by DICOM metadata, not by visual appearance
- Must distinguish CT from MR files (domain knowledge of imaging modalities)
- Must NOT delete legitimate CT files (precision matters)
- Completely different workflow from measurement/annotation tasks
- Requires file management operations (delete/move) in addition to DICOM inspection
- Uses contamination injection: agent must apply domain knowledge to classify items

## Data

**CT Source**: Rubomedical.com CT scan sample
**MR Source**: Rubomedical.com MR brain sample (injected as contaminants)
**Location**: `/home/ga/DICOM/studies/airway_series/`

## Schema Reference

Result JSON path: `/tmp/allergist_contamination_result.json`
