# Task: export_model_and_picture

## Overview

A neurosurgical team needs a complete pre-operative planning package from a cranial CT: a 3D mesh model for spatial planning and a 2D screenshot for the operative report. Both outputs must be produced in a single InVesalius session.

## Professional Context

Before cranial surgery, surgeons and radiologists prepare planning packages that include both a 3D surface model (for visualizing anatomy and planning the approach) and 2D image exports (for inclusion in operative reports and team briefings). Preparing both in InVesalius requires chaining the segmentation, surface generation, 3D export, and picture export workflows without losing session state.

## Goal

Complete all of the following in a single InVesalius session:
1. Create a bone segmentation mask and generate a 3D surface reconstruction
2. Export the 3D surface as an OBJ file to `/home/ga/Documents/skull_surface.obj`
3. Export a screenshot of the current InVesalius view to `/home/ga/Documents/surgical_view.png`

## Required Steps (not told to agent)

1. Create a bone mask (Bone preset 226–3071 HU or similar)
2. Generate a 3D surface from that mask
3. Export the surface via Export Data > Export Surface as OBJ → skull_surface.obj
4. Export the view via Export Data > Export Picture as PNG → surgical_view.png

## Success Criteria

- `/home/ga/Documents/skull_surface.obj` exists and is a valid OBJ file (has vertex lines starting with "v ")
- OBJ has at least 1,000 vertices (non-trivial 3D model)
- `/home/ga/Documents/surgical_view.png` exists and is a valid PNG (starts with PNG magic bytes)
- PNG file size > 50 KB

## Verification Strategy

export_result.sh:
- Checks OBJ file: counts "v " lines for vertex count
- Checks PNG file: verifies magic bytes \x89PNG\r\n\x1a\n

## Ground Truth

- Bone threshold: 226–3071 HU (or similar bone presets)
- Expected OBJ vertex count: 50,000–500,000 (full skull surface)
- Expected PNG size: 200 KB–2 MB (full 1920×1080 or cropped view)

## Edge Cases

- STL exported instead of OBJ: FAILS (task specifies OBJ)
- Only one output file: partial credit (15+25 or 15+40 depending on which)
- PNG exported as BMP or JPG: FAILS (task specifies PNG format)
