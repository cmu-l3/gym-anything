# BraTS Brain Tumor Segmentation (`brats_tumor_segmentation@1`)

## Overview

This task evaluates the agent's ability to perform medical image segmentation using 3D Slicer. The agent must segment a brain tumor from multi-modal MRI data, create a 3D visualization, and report the tumor volume.

## Rationale

**Why this task is valuable:**
- Tests understanding of medical imaging workflows
- Requires multi-step interaction with a complex professional application
- Evaluates spatial reasoning and 3D visualization skills
- Clinically relevant - tumor segmentation is a real-world radiologist task

**Real-world Context:** A radiologist needs to segment a brain tumor for surgical planning. The tumor volume and location affect treatment decisions.

## Task Description

**Goal:** Segment a glioma (brain tumor) from a multi-modal MRI scan, visualize it in 3D, and report the tumor volume.

**Starting State:** 3D Slicer is open with four MRI sequences loaded:
- FLAIR (highlights edema/swelling)
- T1 (anatomical reference)
- T1_Contrast/T1ce (shows enhancing tumor)
- T2 (complementary contrast)

**Expected Actions:**
1. Examine the MRI sequences to identify the tumor region
2. Use the Segment Editor module to create a segmentation
3. Segment the complete tumor (may include enhancing core, non-enhancing core, edema)
4. Create a 3D visualization of the tumor using Volume Rendering or similar
5. Measure the tumor volume using segment statistics
6. Save the segmentation to the specified path
7. Create a report file with the measured volume in mL

**Final State:**
- Segmentation saved at `~/Documents/SlicerData/BraTS/agent_segmentation.nii.gz`
- Report saved at `~/Documents/SlicerData/BraTS/tumor_report.txt` containing volume in mL

## Verification Strategy

### Primary Verification: Segmentation Metrics (File-based)

The verifier computes standard BraTS challenge metrics:

1. **Dice Coefficient** for three tumor regions:
   - Whole Tumor (WT): All tumor labels (1, 2, 4)
   - Tumor Core (TC): Core regions (labels 1, 4)
   - Enhancing Tumor (ET): Label 4 only

2. **Hausdorff Distance (95th percentile)**: Measures boundary accuracy

3. **Volume Accuracy**: Compares predicted vs ground truth tumor volume

### Secondary Verification: Report and Visualization Check

- Checks that tumor volume is reported in the text file
- Verifies the reported volume is within acceptable range of ground truth
- Checks for 3D visualization creation

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Dice Whole Tumor | 25 | >= 0.5 threshold |
| Dice Tumor Core | 15 | >= 0.3 threshold |
| Dice Enhancing | 15 | >= 0.3 threshold |
| Hausdorff Distance | 10 | <= 30mm HD95 |
| Volume Accuracy | 15 | Segmentation volume within 50% |
| Volume Reported | 10 | Report file with volume in mL within 30% |
| 3D Visualization | 10 | Visualization screenshot created |
| **Total** | **100** | |

**Pass Threshold:** 60 points with Dice WT >= 0.5

## Data Source

**Dataset:** BraTS 2021 Challenge (Brain Tumor Segmentation)
- Source: https://www.kaggle.com/datasets/dschettler8845/brats-2021-task1
- Real clinical MRI scans with expert annotations
- Multi-institutional, anonymized patient data
