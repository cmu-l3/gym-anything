# Task: dual_tissue_segmentation

## Overview

A radiologist needs to compare bone and soft-tissue structures in a single CT Cranium study using InVesalius. This requires creating two separate segmentation masks with different Hounsfield Unit thresholds, and saving the project so both masks are preserved for later review.

## Professional Context

Radiologists and physical medicine physicians use InVesalius multi-mask workflows to simultaneously visualize different tissue types (e.g., cortical bone vs. brain parenchyma) for differential diagnosis and treatment planning. Saving the project ensures reproducibility for team review sessions.

## Goal

Create two segmentation masks in InVesalius and save the project to `/home/ga/Documents/tissue_comparison.inv3`:
1. A **bone mask** using an appropriate bone threshold (e.g., Bone preset: 226–3071 HU)
2. A **soft tissue mask** using an appropriate soft tissue threshold (e.g., Soft Tissue preset: −700 to 225 HU, or Muscle Tissue preset: −5 to 135 HU)

## Required Steps (not told to agent)

1. Confirm the CT Cranium scan is loaded
2. Create first mask using a bone-appropriate threshold (min HU ≥ 150, max HU ≥ 1000)
3. Create a second mask using a different threshold appropriate for soft tissue (max HU ≤ 300)
4. Navigate to File > Save As and save project to /home/ga/Documents/tissue_comparison.inv3

## Success Criteria

- `/home/ga/Documents/tissue_comparison.inv3` exists and is a valid InVesalius project (gzipped tar)
- Contains at least 2 masks
- At least one mask has a threshold range consistent with bone (min_HU ≥ 150, max_HU ≥ 1000)
- At least one mask has a threshold range consistent with soft tissue (max_HU ≤ 300)

## Verification Strategy

The export_result.sh parses the .inv3 tarfile, reads each mask_X.plist, and records:
- Number of masks
- Threshold range of each mask
- Whether a bone-range and soft-tissue-range mask both exist

## Ground Truth Data

- CT Cranium dataset: 108 slices, spacing 0.957×0.957×1.5 mm
- Bone preset in InVesalius: 226–3071 HU
- Soft Tissue preset: −700–225 HU
- Muscle Tissue (Adult): −5–135 HU

## Edge Cases

- Agent may use any bone-appropriate preset (Compact Bone, Spongial Bone, etc.) — all accepted as long as max_HU ≥ 1000
- Agent may use any soft-tissue preset — accepted as long as max_HU ≤ 300
- Project may be saved with Ctrl+S if a previous save path exists — accepted
