# Abdominal Aorta Measurement (`aorta_measurement@1`)

## Overview

This task evaluates the agent's ability to locate an anatomical structure, perform a measurement, and provide a clinical assessment. It's a focused task testing measurement tools and clinical reasoning.

## Rationale

**Why this task is valuable:**
- Tests anatomical landmark identification
- Requires precise measurement using ruler tools
- Involves clinical classification based on measurements
- Common clinical workflow for vascular assessment

**Real-world Context:** A radiologist is screening a patient for abdominal aortic aneurysm (AAA), a potentially life-threatening condition. Accurate measurement determines management.

## Task Description

**Goal:** Find the abdominal aorta, measure its maximum diameter, and classify it clinically.

**Starting State:** 3D Slicer is open with an abdominal CT scan loaded.

**Expected Actions:**
1. Navigate to the abdominal region of the CT scan
2. Locate the abdominal aorta (large vessel anterior to spine)
3. Scroll through to find the widest point of the aorta
4. Use the Markups ruler tool to measure the maximum outer diameter
5. Note the vertebral level (L1-L5) where the maximum is found
6. Classify the finding:
   - Normal: < 30mm
   - Ectatic (dilated): 30-35mm
   - Aneurysmal: > 35mm
7. Save the measurement markup
8. Create a JSON report with findings

**Final State:**
- Measurement saved at `~/Documents/SlicerData/AMOS/agent_measurement.mrk.json`
- Report saved at `~/Documents/SlicerData/AMOS/aorta_report.json`

## Verification Strategy

### Primary Verification: Measurement Accuracy

- Compare agent's diameter measurement to ground truth
- Acceptable error: <= 5mm

### Secondary Verification: Clinical Assessment

- Classification correctness (Normal/Ectatic/Aneurysmal)
- Vertebral level accuracy (within 1 level)

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Diameter Accuracy | 35 | Within 5mm of ground truth |
| Classification Correct | 25 | Correct clinical category |
| Measurement Placed | 15 | Ruler markup exists |
| Vertebral Level | 10 | Correct or within 1 level |
| Report Completeness | 15 | JSON with all required fields |
| **Total** | **100** | |

**Pass Threshold:** 60 points with Diameter Accuracy achieved

## Data Source

**Dataset:** AMOS (Abdominal Multi-Organ Segmentation)
- Source: https://amos22.grand-challenge.org/
- Real clinical CT scans with organ annotations
- Includes aorta segmentation for ground truth
