# Task: boolean_mask_operations

## Overview

Cancellous bone isolation via boolean mask subtraction in InVesalius 3. This task reflects a research workflow used by bone morphologists and orthopedic biomechanics researchers to isolate trabecular bone compartments from cortical bone in CT imaging.

## Domain Context

Physical medicine physicians and bone morphologists study the trabecular (cancellous/spongy) bone microarchitecture to assess osteoporosis, implant anchoring sites, and fracture risk. The cranial vault contains a layer of cancellous bone (diploë) sandwiched between the inner and outer cortical tables. Isolating this layer requires subtracting the cortical bone mask from the full bone mask using boolean operations — a feature in InVesalius for mask-level set operations.

## Goal

Given a loaded CT Cranium DICOM series, produce an isolated cancellous bone surface:
1. Create a compact bone mask (HU range ~662–1988) — cortical bone only
2. Create a full bone mask (HU range ~226–3071) — all bone tissue
3. Apply boolean subtraction (full bone MINUS compact bone) to isolate cancellous bone
4. Generate 3D surface from the cancellous bone result mask
5. Export cancellous bone surface to `/home/ga/Documents/cancellous_study/cancellous_bone.stl`
6. Save project (3 masks: compact, full, and cancellous result) to `/home/ga/Documents/cancellous_study/bone_analysis.inv3`

## Starting State

- InVesalius 3 running with CT Cranium pre-loaded
- `/home/ga/Documents/cancellous_study/` directory already created
- No existing output files — clean workspace

## Agent Workflow (what must be discovered)

1. Create compact bone mask using threshold segmentation
2. Create full bone mask using threshold segmentation
3. Navigate to the boolean operations feature (typically under Tools or via mask context menu)
4. Select subtraction operation: full bone minus compact bone
5. Generate surface from the resulting cancellous mask
6. Export the cancellous surface as STL
7. Save the project

The agent must discover: where boolean operations are in the UI, which operand order produces the desired result, and how to generate/export from the resulting mask.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Project file exists and is valid .inv3 | 20 | Tarball parse |
| ≥2 bone masks present (compact + full) | 20 | mask plist HU ranges |
| ≥3 masks total (boolean result = third mask) | 25 | main.plist mask count |
| STL file exists at correct path | 20 | File existence |
| STL is valid format with ≥500 triangles | 15 | STL parse |

**Pass threshold: 70 points**

## Anti-Gaming Measures

- Mask count ≥3 enforces that a boolean operation result was created (not just 2 threshold masks)
- HU range checks for the bone masks confirm correct threshold values were used
- STL size requirement ensures a real cancellous surface was generated

## Schema Reference

**InVesalius project (.inv3)** — gzipped tar archive containing:
- `main.plist`: masks dict and surfaces dict
- `mask_N.plist`: threshold_range [min, max], name

**Boolean operation detection**: Result mask may have threshold_range of [0, 0] or unusual values indicating it was created by set operation rather than threshold.
