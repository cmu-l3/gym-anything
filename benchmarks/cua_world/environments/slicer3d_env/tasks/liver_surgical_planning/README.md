# Liver Surgical Planning (`liver_surgical_planning@1`)

## Overview

This task evaluates the agent's ability to perform multi-structure segmentation for surgical planning. It requires segmenting the liver, tumors, and vasculature, then analyzing spatial relationships.

## Rationale

**Why this task is valuable:**
- Tests complex multi-label segmentation
- Requires understanding of anatomical relationships
- Involves quantitative analysis (volume, distance measurements)
- Directly relevant to surgical oncology workflows

**Real-world Context:** A hepatobiliary surgeon needs to plan a liver resection. They need to know tumor volumes, locations relative to major vessels, and whether tumors invade critical structures.

## Task Description

**Goal:** Segment liver anatomy and tumors, measure tumor volume, and assess vascular involvement.

**Starting State:** 3D Slicer is open with an abdominal CT scan loaded showing a liver with tumor(s).

**Expected Actions:**
1. Segment the liver parenchyma using Segment Editor
2. Segment all visible liver tumors as a separate label
3. Segment the portal vein (main vessel entering the liver)
4. Use segment statistics to measure tumor volume
5. Measure the minimum distance between tumor and portal vein
6. Assess whether any tumor directly contacts the portal vein
7. Save the multi-label segmentation
8. Create a JSON surgical planning report

**Final State:**
- Segmentation saved at `~/Documents/SlicerData/IRCADb/agent_segmentation.nii.gz`
  - Label 1 = liver, Label 2 = tumor, Label 3 = portal vein
- Report saved at `~/Documents/SlicerData/IRCADb/surgical_report.json`

## Verification Strategy

### Primary Verification: Segmentation Metrics

Dice coefficient for each structure:
- Liver (high threshold - should be accurate)
- Tumor (medium threshold - harder to delineate)
- Portal vein (medium threshold - small structure)

### Secondary Verification: Clinical Report Accuracy

- Tumor volume within acceptable range
- Tumor count correct
- Tumor-to-vessel distance accurate
- Vascular invasion assessment correct

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Dice Liver | 20 | >= 0.85 threshold |
| Dice Tumor | 20 | >= 0.50 threshold |
| Dice Portal Vein | 10 | >= 0.40 threshold |
| Tumor Volume Accuracy | 10 | Within 30% of ground truth |
| Tumor Count Correct | 10 | Correct number of tumors |
| Distance Accuracy | 15 | Min distance within 5mm |
| Invasion Assessment | 10 | Correct yes/no for vascular contact |
| Report Completeness | 5 | JSON with all required fields |
| **Total** | **100** | |

**Pass Threshold:** 60 points with Dice Liver >= 0.7

## Data Source

**Dataset:** 3D-IRCADb (3D Image Reconstruction for Comparison of Algorithm Database)
- Source: https://www.ircad.fr/research/data-sets/liver-segmentation-3d-ircadb-01/
- Real clinical CT scans with expert multi-structure annotations
- French Research Institute Against Digestive Cancer
