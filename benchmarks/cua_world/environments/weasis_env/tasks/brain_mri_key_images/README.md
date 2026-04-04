# brain_mri_key_images

**Occupation**: Radiologic Technologist
**Industry**: Hospital Neuroradiology Department
**Difficulty**: very_hard
**Max Steps**: 75
**Timeout**: 600 seconds

## Task Description

A Radiologic Technologist prepares a brain MRI study for clinical record inclusion by selecting and exporting "key images" per the department's standard neuroradiology protocol. This requires loading the MRI series, applying a brain window preset, navigating to three specific anatomical levels, exporting each as a separate PNG, and documenting the selection in a summary file.

## Clinical Context

Key image selection is a fundamental workflow in radiology departments. After a study is acquired, a technologist or radiologist marks representative images at anatomically significant levels for inclusion in the patient's electronic health record, picture archiving and communication system (PACS), and radiology report. The brain MRI key image protocol typically requires vertex (superior cortex), basal ganglia/thalamus, and posterior fossa/cerebellum levels — the three tiers that give a radiologist rapid overview of the entire brain.

The brain soft tissue window (W:80 L:40) is the standard display window for evaluating gray-white matter differentiation, edema, and infarct in brain MRI.

## Required Steps

1. Load brain MRI from `/home/ga/DICOM/studies/brain_mri/`
2. Apply brain window (W:80, L:40)
3. Navigate to vertex/high convexity level; export as `key_image_01.png`
4. Navigate to basal ganglia/thalamus level; export as `key_image_02.png`
5. Navigate to posterior fossa/cerebellum level; export as `key_image_03.png`
6. Save all three images to `/home/ga/DICOM/exports/key_images/`
7. Write `/home/ga/DICOM/exports/key_image_summary.txt` with:
   - Anatomical level for each image
   - Slice number/position used
   - Window settings applied

## Scoring (100 points)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| Key images exported with correct names | 45 | 15 pts per image (key_image_01/02/03.png, new, ≥20KB) |
| 3+ new PNGs in exports (any naming) | 20 | Fallback: catches alternate filenames |
| Summary file exists with content | 20 | File new, ≥30 chars |
| Anatomical levels documented in summary | 15 | vertex/basal ganglia/cerebellum keywords |

**Pass threshold**: 60 points

### Partial credit rules

- Correct images but very small (<20KB): 8/15 per image
- 2 images instead of 3: 13/20 on the count criterion
- Summary too short: 10/20
- Summary has anatomy but missing window/slice info: 10/15

## What Makes This Hard

1. **Multi-image export workflow**: The agent must export three separate images, not just one — requiring three separate export actions with distinct save paths
2. **Anatomical navigation**: The agent must understand enough neuroradiology to navigate to vertex (near top of scan), basal ganglia (mid-brain), and posterior fossa (bottom of scan) — three very different slice positions
3. **Window application before export**: The brain window (W:80 L:40) must be applied; default DICOM display may show a much wider window — the agent must find and change the W/L settings
4. **File naming discipline**: Files must be named key_image_01/02/03.png in the correct subdirectory — the agent must manage file paths carefully across three operations
5. **Summary completeness**: The text summary must document anatomical level, slice position, AND window setting — three distinct pieces of information per image
6. **Scroll position awareness**: Agents tend to export from whichever slice is currently visible; correctly selecting three different anatomical levels requires deliberate navigation through the slice stack

## Data Source

- Brain MRI: rubomedical.com MR DICOM sample (dicom_viewer_0003.zip)
  — Copied to `/home/ga/DICOM/studies/brain_mri/` by `setup_task.sh`
  — Real (non-synthetic) DICOM dataset acquired on a clinical MRI scanner

## Verification Files

- `/tmp/brain_mri_key_images_result.json` — written by `export_result.sh`
- `/home/ga/DICOM/exports/key_images/key_image_01.png` — vertex level key image
- `/home/ga/DICOM/exports/key_images/key_image_02.png` — basal ganglia level key image
- `/home/ga/DICOM/exports/key_images/key_image_03.png` — posterior fossa level key image
- `/home/ga/DICOM/exports/key_image_summary.txt` — protocol documentation
