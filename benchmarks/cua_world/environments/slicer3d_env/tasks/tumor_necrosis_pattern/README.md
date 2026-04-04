# Tumor Necrosis and Enhancement Pattern Analysis (`tumor_necrosis_pattern@1`)

## Overview

This task evaluates the agent's ability to analyze internal tumor characteristics on contrast-enhanced MRI, specifically assessing the pattern of enhancement and extent of necrosis within a brain tumor. The agent must quantify enhancing vs. non-enhancing tumor components and classify the enhancement pattern—a key component of tumor characterization with direct prognostic implications.

## Rationale

**Why this task is valuable:**
- Tests interpretation of contrast enhancement patterns on MRI
- Requires multi-sequence comparison (T1 pre-contrast vs T1ce post-contrast)
- Involves quantitative assessment of distinct tumor components
- Clinically critical for tumor grading and treatment planning
- Exercises precise segmentation skills with internal tumor boundaries

**Real-world Context:** A neuro-oncologist is evaluating a newly diagnosed brain tumor to determine optimal treatment strategy. High-grade gliomas typically show significant necrosis and ring-enhancement, while lower-grade tumors often enhance minimally. The necrosis-to-tumor ratio and enhancement pattern directly influence prognosis estimates and guide decisions about surgery, radiation, and chemotherapy intensity.

## Task Description

**Goal:** Analyze a brain tumor's internal characteristics by separately quantifying the enhancing and necrotic/non-enhancing components, computing the necrosis ratio, and classifying the overall enhancement pattern.

**Starting State:** 3D Slicer is open with BraTS multi-modal MRI data loaded:
- T1ce_Contrast (post-gadolinium contrast, shows enhancing tumor)
- T1_PreContrast (pre-contrast anatomical reference)
- FLAIR (highlights edema and non-enhancing tumor)
- T2 (complementary soft tissue contrast)

**Expected Actions:**
1. Compare T1ce and T1 sequences to identify enhancing regions
2. Use Segment Editor to create TWO segments:
   - "Enhancing_Tumor" (bright on T1ce relative to T1)
   - "Necrotic_Core" (dark non-enhancing central region on T1ce)
3. Use Segment Statistics to measure volumes in mL
4. Calculate necrosis ratio: necrotic_volume / (enhancing + necrotic)
5. Classify enhancement pattern (Ring-enhancing, Solid, Heterogeneous, Non-enhancing)
6. Save segmentation and create JSON report

**Final State:**
- Segmentation at `~/Documents/SlicerData/BraTS/enhancement_segmentation.nii.gz`
- Report at `~/Documents/SlicerData/BraTS/necrosis_report.json`

## Verification Strategy

### Primary Verification: Component Volumes
- Compare agent's enhancing and necrotic volumes to ground truth
- BraTS labels: enhancing (label 4), non-enhancing core (label 1)

### Secondary Verification: Pattern Classification
- Verify enhancement pattern matches ground truth characteristics

### Anti-Gaming Measures
- Segmentation file timestamp must be after task start
- Must have 2 distinct non-zero labels
- Segments must overlap with actual tumor region (>50%)

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Enhancing Volume Accuracy | 25 | Within 40% of ground truth |
| Necrotic Volume Accuracy | 25 | Within 40% of ground truth |
| Necrosis Ratio Accuracy | 15 | Within ±0.15 absolute |
| Pattern Classification | 20 | Correct enhancement pattern |
| Report Completeness | 10 | JSON with all required fields |
| Segmentation Quality | 5 | Overlaps with tumor region |
| **Total** | **100** | |

**Pass Threshold:** 60 points with at least one volume criterion achieving accuracy threshold

## Data Source

**Dataset:** BraTS 2021 Challenge (Brain Tumor Segmentation)
- Source: https://www.kaggle.com/datasets/dschettler8845/brats-2021-task1
- Real clinical multi-modal MRI from multiple institutions
- Expert-annotated ground truth with distinct labels for enhancing (4) and non-enhancing core (1)

## Clinical Context

Enhancement patterns and necrosis extent are critical prognostic indicators:

- **Ring-enhancing (GBM)**: Peripheral rim with necrotic center indicates rapid growth outstripping blood supply
- **Solid**: Homogeneous enhancement suggests intact vasculature
- **Non-enhancing**: Minimal enhancement may indicate lower-grade tumor
- **Necrosis ratio**: Higher ratios correlate with worse prognosis and treatment resistance