# mpr_kidney_measurement

**Occupation**: Urologist
**Industry**: Urology / Nephrology
**Difficulty**: very_hard
**Max Steps**: 70
**Timeout**: 600 seconds

## Task Description

A Urologist evaluates kidney size from a CT urogram using Weasis's Multi-Planar Reconstruction (MPR) view. The task requires loading the CT series, activating MPR mode, switching to the coronal plane for accurate craniocaudal length measurement, applying a renal soft tissue window, measuring the kidney length, exporting the coronal MPR image, and writing a clinical assessment report.

## Clinical Context

Kidney size assessment is a routine urology measurement. Normal adult kidneys measure approximately 9–12 cm (90–120 mm) in craniocaudal length; values outside this range may indicate conditions such as renal atrophy (<9 cm), compensatory hypertrophy (>13 cm), or hydronephrosis. The coronal MPR view is preferred for craniocaudal length measurement because it shows the entire kidney in a single plane, avoiding the geometric distortion of axial slice measurements.

CT urogram is the standard imaging modality for evaluating the kidneys and collecting system in urology.

## Required Steps

1. Load CT from `/home/ga/DICOM/studies/ct_urogram/`
2. Activate MPR view in Weasis (View menu → Multi-Planar Reconstruction or similar)
3. Select the coronal plane view
4. Apply soft tissue / renal window (W:400 L:50 or equivalent renal preset)
5. Identify the kidney in the coronal view
6. Measure the craniocaudal length using the line measurement tool (from superior to inferior pole)
7. Export coronal MPR view to `/home/ga/DICOM/exports/mpr_renal.png`
8. Write report to `/home/ga/DICOM/exports/renal_report.txt` including:
   - Kidney length measurement in mm
   - Normal/abnormal size assessment

## Scoring (100 points)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| MPR export image | 25 | Exists, newer than task start, ≥30KB |
| Report exists with content | 30 | File new, ≥20 chars |
| Plausible kidney length (50–160mm) | 30 | Measurement in realistic range |
| Clinical assessment keyword | 15 | "normal"/"abnormal"/"enlarged"/"WNL" etc. |

**Pass threshold**: 60 points

### Partial credit rules

- Export image exists but small (<30KB): 15/25
- New PNG found anywhere in exports: 10/25
- Report too short (<20 chars): 15/30
- Kidney length outside 50-160mm but 30-180mm: 15/30
- Measurement found in report text (fallback): 25/30

## What Makes This Hard

1. **MPR activation**: Multi-Planar Reconstruction is not the default view in Weasis — the agent must find and enable it through the menu
2. **Coronal plane selection**: After activating MPR, the agent must switch from the default axial view to the coronal plane
3. **Anatomical identification**: In the coronal view, the agent must correctly identify the kidney and distinguish it from adjacent structures (liver, spleen, psoas muscle)
4. **Proper measurement**: The craniocaudal length must be measured pole-to-pole — not obliquely, not mid-kidney
5. **Window selection**: The renal window (W:400 L:50) must be applied before export for clinically appropriate image display
6. **Assessment requirement**: Beyond just measuring, the agent must provide a clinical interpretation (normal vs. abnormal size) based on the measurement

## Data Source

- CT urogram: rubomedical.com CT DICOM sample (dicom_viewer_0002.zip)
  — Copied to `/home/ga/DICOM/studies/ct_urogram/` by `setup_task.sh`
  — Real (non-synthetic) CT DICOM dataset

## Verification Files

- `/tmp/mpr_kidney_measurement_result.json` — written by `export_result.sh`
- `/home/ga/DICOM/exports/mpr_renal.png` — coronal MPR kidney image
- `/home/ga/DICOM/exports/renal_report.txt` — kidney assessment report
