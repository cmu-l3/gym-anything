# Lung Nodule Detection & Measurement (`lung_nodule_detection@1`)

## Overview

This task evaluates the agent's ability to detect and characterize lung nodules in a chest CT scan. It requires systematic review of imaging data, spatial marking, and structured reporting.

## Rationale

**Why this task is valuable:**
- Tests systematic image review (scrolling through volumes)
- Requires precise spatial localization (fiducial placement)
- Involves clinical decision-making (nodule characterization)
- Highly relevant - lung cancer screening is a major clinical application

**Real-world Context:** A radiologist is reviewing a lung cancer screening CT and needs to identify and measure all significant nodules for follow-up recommendations.

## Task Description

**Goal:** Find all lung nodules >= 3mm in diameter, mark their locations, and report their characteristics.

**Starting State:** 3D Slicer is open with a chest CT scan loaded. The scan contains multiple lung nodules of varying sizes.

**Expected Actions:**
1. Adjust window/level settings to properly visualize lung parenchyma (lung window: W=1500, L=-600)
2. Systematically scroll through the CT scan to find nodules
3. For each nodule >= 3mm:
   - Place a fiducial marker using the Markups module
   - Estimate the nodule's diameter
   - Identify which lobe it's in (RUL, RML, RLL, LUL, LLL)
4. Create a JSON report with findings
5. Save the fiducial markers to the specified path

**Final State:**
- Fiducial markers saved at `~/Documents/SlicerData/LIDC/agent_fiducials.fcsv`
- Report saved at `~/Documents/SlicerData/LIDC/nodule_report.json`

## Verification Strategy

### Primary Verification: Spatial Matching

The verifier compares agent-placed fiducials against ground truth nodule locations:
- **Recall**: What fraction of actual nodules were found?
- **Precision**: What fraction of agent markings are true nodules?
- Uses spatial tolerance (15mm) for matching

### Secondary Verification: Measurement and Reporting

- Diameter accuracy for matched nodules
- Lobe assignment accuracy
- Report completeness and JSON structure

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Recall (Sensitivity) | 30 | >= 60% of nodules found |
| Precision | 20 | >= 50% of markings are correct |
| Diameter Accuracy | 15 | Measured diameters within tolerance |
| Lobe Accuracy | 10 | Correct lobe assignment |
| Window/Level | 10 | Appropriate lung windowing used |
| Report Completeness | 15 | JSON report with all required fields |
| **Total** | **100** | |

**Pass Threshold:** 50 points with Recall >= 0.5

## Data Source

**Dataset:** LIDC-IDRI (Lung Image Database Consortium)
- Source: The Cancer Imaging Archive (TCIA)
- Real clinical chest CT scans with expert nodule annotations
- Multiple radiologist consensus on nodule locations
