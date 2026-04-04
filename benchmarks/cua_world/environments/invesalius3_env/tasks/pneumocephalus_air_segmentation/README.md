# Task: pneumocephalus_air_segmentation

## Overview

**Professional Context**: Trauma radiology — documenting pneumocephalus (intracranial air) and paranasal sinus airspace distribution from cranial CT.

Pneumocephalus refers to the presence of air within the cranial vault, which occurs following head trauma, neurosurgery, barotrauma, or skull base fractures. Accurate segmentation and measurement of intracranial air pockets is critical for assessing injury severity and monitoring treatment response. Paranasal sinuses (frontal, ethmoid, maxillary, sphenoid) also appear as air-filled cavities on CT and must be distinguished from pathological pneumocephalus.

**Occupational Category**: Healthcare Practitioners and Technical / Radiologists

**Why Radiologists Use InVesalius**: CT interpretation and 3D reconstruction from DICOM data for clinical reporting and surgical planning.

---

## Goal

The agent must:
1. Create a segmentation mask for air spaces (HU max ≤ -200 HU)
2. Generate a 3D surface from the air mask and export as STL
3. Create a soft tissue/brain parenchyma mask (HU range near 0: min ≥ -200, max ≥ 50)
4. Place ≥4 linear measurements of air pocket or sinus dimensions
5. Save the complete project to /home/ga/Documents/air_analysis/pneumocephalus_study.inv3

---

## What Makes This Hard

This task deliberately inverts the Hounsfield Unit logic from all bone/tissue tasks:

- **Existing tasks**: Create masks with HU min ≥ 226 (bone) or HU near 0 (soft tissue)
- **This task**: Create air mask with HU max ≤ -200 — the agent must reason about the *opposite* end of the HU spectrum
- **Dual mask requirement**: Both air (negative HU) and soft tissue (near-zero HU) masks must coexist in the same project
- **Small-scale measurements**: Air pockets and sinuses are smaller structures than cranial vault dimensions; the agent must navigate to relevant slices
- **Novel workflow**: No existing task in this environment uses negative HU thresholding

**Litmus test**: A competent InVesalius user who has only done bone segmentation tasks would need to stop and think — the workflow is conceptually reversed. The agent must understand the HU scale and correctly set a *maximum* threshold rather than a minimum.

---

## Starting State

- InVesalius 3 running with CT Cranium DICOM pre-loaded
- Output directory `/home/ga/Documents/air_analysis/` created
- Radiology request form at `/home/ga/Documents/air_analysis/radiology_request.txt` providing clinical context
- No pre-existing STL or .inv3 output files

---

## Verification Strategy

### Criterion 1: Project file saved (20 pts)
- `/home/ga/Documents/air_analysis/pneumocephalus_study.inv3` exists and is parseable as gzipped tar

### Criterion 2: Air space mask with correct HU range (25 pts)
- In `.inv3` masks: at least one mask with `threshold_range[1]` ≤ -200 HU
- This confirms the agent used negative HU thresholding (not just any mask)

### Criterion 3: Soft tissue mask (brain parenchyma) present (20 pts)
- In `.inv3` masks: at least one mask with `threshold_range[0]` ≥ -200 HU AND `threshold_range[1]` ≥ 50 HU
- Confirms two distinct tissue types were segmented

### Criterion 4: STL file exported and valid (20 pts)
- `/home/ga/Documents/air_analysis/air_spaces.stl` exists
- Valid binary or ASCII STL format

### Criterion 5: At least 4 measurements (15 pts)
- `measurements.plist` in `.inv3` contains ≥ 4 entries

**Pass threshold**: 65 points

---

## .inv3 Schema Reference

```
pneumocephalus_study.inv3  (gzipped tar)
├── main.plist             # masks dict, surfaces dict, window_width
├── mask_0.plist           # threshold_range [min_hu, max_hu], name
├── mask_1.plist           # threshold_range [min_hu, max_hu], name
└── measurements.plist     # {index: {value: float_mm, ...}}
```

For this task:
- Air mask: `threshold_range[1]` (max) ≤ -200
- Soft tissue mask: `threshold_range[0]` (min) ≥ -200 AND `threshold_range[1]` ≥ 50

---

## Expected CT Values (CT Cranium 0051)

- Air-filled paranasal sinuses (frontal, ethmoid, sphenoid): -1000 to -900 HU
- Expected sinus dimensions: 10–50 mm
- Measurement range: 5–80 mm for sinus/air cavity dimensions
- Air mask surface: scattered cavities, much smaller triangle count than bone surface

---

## Edge Cases

- ASCII STL is accepted (some InVesalius versions export ASCII by default for small meshes)
- The air mask may produce a very fragmented or small surface — that is correct
- Measurements of sinus dimensions < 50 mm are expected (unlike cranial vault measurements)
- Window/level does not need to be changed (the verifier does not check window_width for this task)
