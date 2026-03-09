# Task: urologist_dicom_metadata_audit

## Overview

**Difficulty**: Very Hard
**Occupation**: Urologist
**Clinical Scenario**: DICOM metadata audit and correction for patient safety

A urologist receives CT DICOM files with corrupted metadata from a faulty import.
Several header tags are incorrect — the agent must discover which tags are wrong,
correct them using available tools, and document the corrections. This task uses
the error injection pattern: `setup_task.sh` corrupts specific DICOM tags, and
the agent must diagnose and repair them without being told which tags are wrong.

## Task Requirements

The agent must:
1. Inspect DICOM headers in `/home/ga/DICOM/studies/renal_audit/`
2. Discover which metadata tags have incorrect values
3. Correct the erroneous tags using pydicom, dcmodify, or Weasis
4. Write an audit report to `/home/ga/DICOM/exports/metadata_audit_report.txt`

## Injected Errors (ground truth, not given to agent)

| Tag | Wrong Value | Correct Value |
|-----|-------------|---------------|
| PatientSex (0010,0040) | F | M |
| BodyPartExamined (0018,0015) | HEAD | ABDOMEN |
| ReferringPhysicianName (0008,0090) | (empty) | Dr. Smith |

## Verification Criteria (100 points)

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| Report file | 15 | TXT exists, modified after task start, >= 50 chars |
| PatientSex corrected | 25 | DICOM files have PatientSex = M |
| BodyPartExamined corrected | 25 | DICOM files have BodyPartExamined = ABDOMEN |
| ReferringPhysician corrected | 20 | DICOM files have non-empty ReferringPhysicianName |
| Audit documentation | 15 | Report mentions at least 2 of the corrected tags |

**Pass threshold**: 60/100

## What Makes This Hard

- Agent must DISCOVER which tags are wrong (error injection — not told which fields)
- Must use DICOM header inspection tools (not image viewing tools)
- Must edit DICOM metadata (different skill from viewing images)
- Must verify corrections are applied across all files
- Completely different workflow from measurement/export tasks
- Requires understanding of DICOM tag semantics and patient safety implications

## Data

**Source**: Rubomedical.com CT scan sample with programmatically injected metadata errors
**Location**: `/home/ga/DICOM/studies/renal_audit/`

## Schema Reference

Result JSON path: `/tmp/urologist_metadata_audit_result.json`
