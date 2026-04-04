# Adrenal Incidentaloma Characterization (`adrenal_incidentaloma@1`)

## Overview

This task evaluates the agent's ability to identify, measure, and characterize an adrenal incidentaloma (incidentally discovered adrenal mass) following ACR Incidental Findings Committee guidelines. This tests anatomical localization of small structures, dual measurement techniques (size and density), and clinical decision-making.

## Rationale

**Why this task is valuable:**
- Tests anatomical localization of small, paired organs (adrenal glands are only ~4cm and sit atop the kidneys)
- Requires precise linear measurement using ruler tools
- Requires HU density measurement using ROI placement (different skill than linear measurement)
- Involves multi-parameter clinical classification (size AND density determine risk)
- Extremely common real-world scenario: adrenal incidentalomas found in 4-7% of all abdominal CT scans

**Real-world Context:** A 58-year-old patient underwent a CT scan for vague abdominal discomfort. The scan reveals an incidental finding on one adrenal gland. The radiologist must characterize this nodule to determine if it's a benign lipid-rich adenoma (safe to ignore) or requires further workup for potential malignancy.

## Task Description

**Goal:** Locate the adrenal glands, identify the adrenal nodule, measure its maximum diameter and HU density, and classify it according to ACR Incidental Findings Committee guidelines.

**Starting State:** 3D Slicer is open with a non-contrast abdominal CT scan loaded. The scan contains an adrenal nodule.

**Expected Actions:**
1. Navigate through the CT scan to locate the adrenal glands (small triangular/Y-shaped structures superior-medial to each kidney)
2. Identify which adrenal gland contains the nodule (left or right)
3. Scroll to find the slice showing the maximum cross-sectional diameter of the nodule
4. Use the Markups ruler tool to measure the maximum diameter of the nodule in millimeters
5. Place a circular/elliptical ROI within the homogeneous central portion of the nodule (avoiding edges)
6. Record the mean HU density from the ROI
7. Classify the nodule according to ACR Incidental Findings Committee criteria:
   - **Benign Adenoma (No Follow-up):** Size < 10 mm AND any HU, OR Size < 40 mm AND HU ≤ 10
   - **Likely Benign (Optional Follow-up):** Size 10-40 mm AND HU 11-30
   - **Indeterminate (Recommend Washout CT/MRI):** Size 10-40 mm AND HU > 30
   - **Concerning (Recommend Further Imaging/Biopsy):** Size ≥ 40 mm regardless of HU
8. Save the measurement markup and create a JSON report with all findings

**Final State:**
- Size measurement saved at `~/Documents/SlicerData/Adrenal/nodule_measurement.mrk.json`
- Density ROI saved at `~/Documents/SlicerData/Adrenal/density_roi.mrk.json`
- Clinical report saved at `~/Documents/SlicerData/Adrenal/adrenal_report.json` containing:
  - `laterality`: "left" or "right"
  - `size_mm`: measured diameter in mm
  - `density_hu`: measured HU density
  - `classification`: one of "benign_adenoma", "likely_benign", "indeterminate", "concerning"
  - `recommendation`: clinical recommendation string

## Verification Strategy

### Primary Verification: Measurement Accuracy (File-based)

Compare agent measurements to ground truth:

1. **Size Measurement:**
   - Extract diameter from agent's markup file
   - Compare to ground truth nodule diameter
   - Acceptable error: ≤ 3mm

2. **Density Measurement:**
   - Extract mean HU from agent's ROI
   - Compare to ground truth mean HU of nodule
   - Acceptable error: ≤ 15 HU (accounts for ROI placement variation)

3. **Laterality:**
   - Verify agent correctly identified left vs right adrenal

### Secondary Verification: Clinical Classification

- Check that the classification matches what the measurements indicate per ACR criteria
- Classification must be internally consistent with reported measurements

### Anti-Gaming Checks

1. **Timestamp verification:** Markup files must be created after task start
2. **Measurement plausibility:** Size must be within realistic range (5-60mm), HU within CT range (-100 to +100 for soft tissue)
3. **Do-nothing detection:** If no measurements exist, score is 0

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Nodule Located | 10 | Measurement exists in correct anatomical region |
| Laterality Correct | 10 | Correctly identified left or right adrenal |
| Size Accuracy | 25 | Within 3mm of ground truth diameter |
| Density Accuracy | 25 | Within 15 HU of ground truth density |
| Classification Correct | 20 | Correct ACR category based on measurements |
| Report Complete | 10 | JSON contains all required fields |
| **Total** | **100** | |

**Pass Threshold:** 60 points with Size Accuracy achieved

## Data Source

**Dataset:** Synthetic abdominal CT with anatomically-placed adrenal nodule

The data preparation script creates:
- A realistic abdominal CT volume with proper anatomy
- Anatomically correct adrenal gland positions (superior-medial to kidneys)
- A synthetic adrenal nodule with controlled properties:
  - Known diameter (ground truth)
  - Known HU density (ground truth)
  - Realistic nodule appearance

**Nodule characteristics are randomized within clinical ranges:**
- Size: 14-42mm diameter
- Density: -8 to +48 HU (covers lipid-rich adenoma through indeterminate)
- Laterality: randomly left or right

## Clinical Background

**ACR Incidental Findings Committee Recommendations (2017):**

For adrenal nodules on non-contrast CT:
- **≤ 10 HU:** Lipid-rich adenoma, benign. No follow-up needed if < 4cm.
- **11-30 HU:** Low-lipid adenoma possible. Consider follow-up or characterization if > 1cm.
- **> 30 HU:** Indeterminate. Recommend adrenal protocol CT or MRI for characterization.
- **≥ 4 cm:** Size alone raises concern. Further imaging and possible biopsy recommended.

This task tests the agent's ability to apply these evidence-based guidelines to make appropriate clinical recommendations.