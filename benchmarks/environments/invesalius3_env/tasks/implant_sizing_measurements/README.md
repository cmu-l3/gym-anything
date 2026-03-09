# Task: implant_sizing_measurements

## Overview

Pre-surgical cranial implant sizing using InVesalius 3. This task reflects the workflow used by biomedical engineers and maxillofacial surgeons to document cranial dimensions from CT scans before planning patient-specific implants.

## Domain Context

Oral and maxillofacial surgeons and biomedical engineers use InVesalius to prepare pre-operative 3D reconstructions and dimensional analysis from patient CT data. Accurate cranial measurements are required for implant sizing (cranioplasty plates, titanium mesh, etc.) and surgical planning. The workflow involves segmentation, 3D surface generation, multi-point measurements, and export for CAD/manufacturing.

## Goal

Given a loaded CT Cranium DICOM series, produce:
- A bone segmentation mask (Hounsfield threshold ≥ 226 HU)
- A 3D bone surface mesh
- At least 5 linear cranial dimension measurements (transverse, anteroposterior, skull height, and 2+ additional)
- An STL export of the bone surface at `/home/ga/Documents/implant_sizing.stl`
- A saved InVesalius project at `/home/ga/Documents/implant_plan.inv3` (containing mask, surface, and all measurements)

## Starting State

- InVesalius 3 running with CT Cranium (108 slices, 0.957×0.957×1.5 mm spacing) pre-loaded
- Context document at `/home/ga/Documents/patient_brief.txt`
- No existing output files — clean workspace

## Agent Workflow (what must be discovered)

1. Access the segmentation panel and create a threshold-based bone mask
2. Generate a 3D surface from the bone mask
3. Navigate to the measurement tool and place linear measurements in multiple planes
4. Export the bone surface as STL to the specified path
5. Save the project file

The agent must discover the correct menus and tools; no UI navigation instructions are provided in the task description.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Project file exists at correct path | 15 | File existence check |
| Valid InVesalius .inv3 format | 15 | Tarball + plist parse |
| ≥5 measurements present | 25 | measurements.plist count |
| All measurements ≥50 mm (realistic cranial) | 20 | Value range check |
| STL file exists at correct path | 15 | File existence check |
| STL has ≥10,000 triangles (real bone geometry) | 10 | Binary/ASCII STL parse |

**Pass threshold: 70 points**

## Expected Values

- CT Cranium: 108 axial slices, 0.957×0.957 mm pixel spacing, 1.5 mm slice thickness
- Expected bone HU range: 226–3071 HU (typical) or 662–1988 HU (compact bone only)
- Expected transverse diameter: 130–180 mm
- Expected anteroposterior diameter: 150–200 mm
- Expected skull height: 110–150 mm
- STL file size: typically 1–25 MB for bone surface

## Anti-Gaming Measures

- Baseline records absence of output files before task start
- STL triangle count ensures actual bone surface was generated (not an empty mesh)
- Measurement count threshold (≥5) requires genuine multi-point assessment
- Measurement value floor (≥50 mm) rejects spurious zero/tiny measurements

## Schema Reference

**InVesalius project (.inv3)** — gzipped tar archive containing:
- `main.plist`: project metadata (window_width, window_level, masks dict, surfaces dict)
- `mask_N.plist`: each mask's threshold_range, name
- `measurements.plist`: dict of measurement objects with `value` (in mm)
