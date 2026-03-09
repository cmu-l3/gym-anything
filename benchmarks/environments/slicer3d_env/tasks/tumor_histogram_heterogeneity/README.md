# Tumor Histogram Heterogeneity Analysis (`tumor_histogram_heterogeneity@1`)

## Overview

This task evaluates the agent's ability to perform quantitative image analysis by computing intensity histogram statistics within a tumor region. The agent must extract heterogeneity metrics from a brain tumor, which are prognostic biomarkers used in neuro-oncology research and clinical decision-making.

## Rationale

**Why this task is valuable:**
- Tests use of Slicer's statistical analysis tools (Segment Statistics module)
- Requires understanding of image intensity distributions
- Involves quantitative biomarker extraction beyond simple volume
- Clinically relevant - tumor heterogeneity correlates with grade and prognosis
- Tests data export and reporting capabilities

**Real-world Context:** A neuro-oncology researcher is analyzing MRI scans from a clinical trial. They need to extract radiomic features from each patient's tumor to build a predictive model. Tumor heterogeneity (measured by intensity variation) has been shown to correlate with tumor grade, genetic markers, and patient survival. The researcher needs standardized heterogeneity metrics extracted and documented for each case.

## Task Description

**Goal:** Compute intensity histogram statistics within a brain tumor region and classify the tumor's heterogeneity level.

**Starting State:** 3D Slicer is open with:
- BraTS brain MRI T1-contrast (T1ce) sequence loaded
- A pre-existing tumor segmentation available for loading

**Expected Actions:**
1. Load the tumor segmentation from `~/Documents/SlicerData/BraTS/<SAMPLE_ID>_tumor_seg.nii.gz`
2. Navigate to the Segment Statistics module (under Quantification category)
3. Select the T1ce volume as the scalar volume input
4. Select the tumor segmentation as the input segmentation
5. Enable histogram statistics computation
6. Run the statistics computation
7. Record the following metrics from the tumor region:
   - Mean intensity
   - Standard Deviation (SD)
   - Minimum and Maximum intensity
8. Calculate the heterogeneity classification:
   - **Homogeneous**: CV < 20%
   - **Mildly Heterogeneous**: CV 20-35%
   - **Moderately Heterogeneous**: CV 35-50%
   - **Highly Heterogeneous**: CV > 50%
9. Export the statistics table to CSV
10. Create a JSON report with the heterogeneity assessment

**Final State:**
- Statistics CSV saved at `~/Documents/SlicerData/BraTS/tumor_statistics.csv`
- Heterogeneity report saved at `~/Documents/SlicerData/BraTS/heterogeneity_report.json` containing: