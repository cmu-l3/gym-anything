# Segmentation Quality Control (`segmentation_qc@1`)

## Overview

This task evaluates the agent's ability to review and correct an AI-generated segmentation. It tests error detection, precise editing, and quality assessment skills.

## Rationale

**Why this task is valuable:**
- Tests critical evaluation of automated outputs
- Requires understanding of segmentation quality
- Involves precise correction of errors
- Reflects real clinical AI workflow - humans review AI results

**Real-world Context:** An AI system generated a tumor segmentation, but radiologists must verify and correct it before clinical use. The agent acts as a QC reviewer.

## Task Description

**Goal:** Review an AI-generated brain tumor segmentation, identify errors, correct them, and document the corrections.

**Starting State:** 3D Slicer is open with:
- Brain MRI sequences loaded (FLAIR, T1, T1ce, T2)
- Pre-existing AI segmentation loaded (contains intentional errors)

**Error Types to Find:**
- **Under-segmentation**: Tumor regions not included in the segmentation
- **Over-segmentation**: Non-tumor regions incorrectly marked as tumor
- **Boundary errors**: Edges that don't match the actual tumor boundary

**Expected Actions:**
1. Load and examine the AI segmentation overlaid on MRI
2. Scroll through all slices comparing segmentation to actual tumor
3. Identify regions of under-segmentation (missed tumor)
4. Identify regions of over-segmentation (false positives)
5. Use Segment Editor tools to correct errors:
   - Paint/Draw to add missed regions
   - Erase to remove false positives
   - Smoothing to fix boundary issues
6. Save the corrected segmentation
7. Create a QC report documenting what was corrected

**Final State:**
- Corrected segmentation at `~/Documents/SlicerData/BraTS/corrected_segmentation.nii.gz`
- QC report at `~/Documents/SlicerData/BraTS/qc_report.json`

## Verification Strategy

### Primary Verification: Improvement Metrics

Compare corrected segmentation to ground truth:
- **Dice Improvement**: Corrected should be better than original AI
- **Final Dice Quality**: Corrected should achieve good overlap

### Secondary Verification: Error Detection

- Did agent fix under-segmented regions?
- Did agent fix over-segmented regions?
- Did agent preserve correct regions (not break what was working)?

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Dice Improvement | 25 | Corrected Dice > Original Dice |
| Final Dice Quality | 20 | Corrected Dice >= 0.80 |
| Under-seg Fixed | 15 | >= 50% of missed regions added |
| Over-seg Fixed | 15 | >= 50% of false positives removed |
| Preservation | 10 | >= 95% of correct regions kept |
| Report Completeness | 15 | JSON documenting corrections |
| **Total** | **100** | |

**Pass Threshold:** 60 points with Dice Improvement achieved

## Data Source

**Dataset:** BraTS 2021 Challenge
- Source: https://www.kaggle.com/datasets/dschettler8845/brats-2021-task1
- Real clinical brain MRI with expert tumor annotations
- AI segmentation is intentionally degraded version of ground truth
