# Task: multi_view_3d_documentation

## Overview

Pre-operative surgical documentation package creation using InVesalius 3. This task reflects the workflow used by surgical residents and attending physicians to prepare standardized anatomical documentation from CT scans before neurosurgical procedures.

## Domain Context

Neurosurgeons require standardized anatomical views captured before surgery to plan incision sites, identify at-risk structures, and document the pre-operative state. Standard cranial documentation packages include anterior, lateral, and superior 3D views of the bone surface, plus dimensional measurements from multi-planar CT slices. These images are shared with the surgical team, archived in the patient record, and used during intra-operative reference.

## Goal

Given a loaded CT Cranium DICOM series, produce a complete surgical documentation package:
1. Create a bone segmentation mask (appropriate HU thresholds)
2. Generate the 3D bone surface
3. Capture 3D screenshots from three anatomical orientations:
   - Anterior (front-facing) view → `/home/ga/Documents/surgical_views/anterior_view.png`
   - Left lateral (side-facing) view → `/home/ga/Documents/surgical_views/lateral_view.png`
   - Superior (top-down, cranial vertex) view → `/home/ga/Documents/surgical_views/superior_view.png`
4. Place at least 3 linear measurements on CT slice views documenting cranial dimensions
5. Save the complete project (with bone mask, surface, and all measurements) to `/home/ga/Documents/surgical_views/skull_study.inv3`

## Starting State

- InVesalius 3 running with CT Cranium pre-loaded
- `/home/ga/Documents/imaging_protocol.txt` present (protocol document)
- `/home/ga/Documents/surgical_views/` directory already created
- No existing output files — clean workspace

## Agent Workflow (what must be discovered)

1. Create threshold mask for bone
2. Generate 3D surface
3. Navigate the 3D viewer to the anterior orientation and take a screenshot (save to file)
4. Rotate to left lateral orientation, take screenshot
5. Rotate to superior orientation, take screenshot
6. Switch to slice views and use the linear measurement tool to place ≥3 measurements
7. Save the project

The agent must discover: how to navigate/rotate the 3D viewer to specific anatomical orientations, how to capture and save screenshots from the 3D viewer (vs. full desktop screenshot), how to use the measurement tool in slice views, and how to combine all of this into one project.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Project file exists and is valid .inv3 | 20 | Tarball parse |
| ≥3 measurements in project, all ≥30 mm | 25 | measurements.plist parse |
| anterior_view.png exists (≥10 KB) | 15 | File existence + size |
| lateral_view.png exists (≥10 KB) | 20 | File existence + size |
| superior_view.png exists (≥10 KB) | 20 | File existence + size |

**Pass threshold: 70 points**

## Anti-Gaming Measures

- Three separate named PNG files required (different filenames enforce different view captures)
- Minimum file size (10 KB) prevents empty/blank screenshot files
- Measurement count threshold (≥3) requires genuine multi-point documentation
- Measurement value floor (≥30 mm) rejects spurious zero or sub-millimeter entries

## Schema Reference

**InVesalius project (.inv3)** — gzipped tar archive containing:
- `main.plist`: masks dict, surfaces dict
- `mask_N.plist`: threshold_range
- `measurements.plist`: dict of measurement objects with `value` (in mm)

**PNG format**: magic bytes 0x89 0x50 0x4E 0x47 0x0D 0x0A 0x1A 0x0A
