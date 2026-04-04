# multimodality_comparison

**Occupation**: PM&R Physician (Physical Medicine & Rehabilitation)
**Difficulty**: very_hard
**Max Steps**: 90
**Timeout**: 720 seconds

## Task Description

A PM&R physician must perform a cross-modality review of a patient's musculoskeletal imaging to correlate bony and soft tissue findings. This requires loading both a CT scan and an MRI scan simultaneously in Weasis, configuring a side-by-side comparison layout, applying appropriate windowing to each modality, taking measurements on structures visible in each, and producing a written correlation report.

## Clinical Context

Cross-modality comparison is a routine workflow in PM&R and musculoskeletal radiology. CT excels at demonstrating cortical bone, fractures, and calcifications; MRI provides superior soft tissue contrast for evaluating muscles, tendons, ligaments, and marrow edema. A PM&R physician reviewing a patient for rehabilitation planning needs to correlate findings across both modalities to understand the full clinical picture.

## Required Steps

1. Launch Weasis (if not already open)
2. Load the CT series from `/home/ga/DICOM/studies/pmr_ct/`
3. Load the MRI series from `/home/ga/DICOM/studies/pmr_mri/`
4. Configure a 1×2 (side-by-side) split layout so both series are visible simultaneously
5. Apply bone window (W:1500 L:300) to the CT panel
6. Apply soft tissue window (W:400 L:50) to the MRI panel
7. Measure a bony structure visible on CT (e.g., vertebral body width or cortical thickness)
8. Measure the corresponding soft tissue structure on MRI (e.g., paraspinal muscle width)
9. Export the comparison layout view to `/home/ga/DICOM/exports/comparison_view.png`
10. Write a correlation report to `/home/ga/DICOM/exports/comparison_report.txt`
    - Must explicitly mention both CT and MRI modalities
    - Must include at least two distinct numerical measurements (with units)
    - Should note correlation or discordance between modalities

## Scoring (100 points)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| Comparison image exported | 30 | File exists, newer than task start, ≥50KB |
| Report exists with content | 25 | File exists, newer than task start, ≥30 chars |
| Both modalities mentioned | 25 | Report contains "CT" and "MRI"/"MR" (case-insensitive) |
| Numerical measurements | 20 | Report contains ≥2 distinct numbers in measurement range |

**Pass threshold**: 60 points

### Partial credit rules

- Comparison image 20–49KB (too small for side-by-side): 20/30
- Agent exported two separate images instead of one side-by-side: 20/30
- Only one of CT/MRI mentioned in report: 12/25
- Only one measurement in report: 10/20

## What Makes This Hard

1. **Multi-series loading**: Most DICOM viewers require separate open operations for each series; combining them into a single layout requires specific UI actions
2. **Layout configuration**: The 1×2 split layout is not the default; the agent must find and configure the correct layout mode
3. **Dual windowing**: Different W/L presets must be applied to each panel independently without affecting the other
4. **Cross-modality measurement**: The agent must identify anatomically corresponding structures in two different imaging modalities
5. **Large image requirement**: A true side-by-side export of two full DICOM series should produce a file ≥50KB; a small export suggests the agent screenshotted one panel only
6. **Report completeness**: The written report must reference both modalities and include measurements from each — not just a description

## Data Source

- CT scan: rubomedical.com CT DICOM sample (dicom_viewer_0002.zip)
  — Copied to `/home/ga/DICOM/studies/pmr_ct/` by `setup_task.sh`
- MRI scan: rubomedical.com MR DICOM sample (dicom_viewer_0003.zip)
  — Copied to `/home/ga/DICOM/studies/pmr_mri/` by `setup_task.sh`

Both are publicly available, real (non-synthetic) DICOM datasets.

## Verification Files

- `/tmp/multimodality_comparison_result.json` — written by `export_result.sh`
- `/home/ga/DICOM/exports/comparison_view.png` — comparison layout image
- `/home/ga/DICOM/exports/comparison_report.txt` — written correlation report
