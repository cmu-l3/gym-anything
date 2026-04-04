# Task: export_skull_stl

## Overview

A neurosurgical team needs a 3D-printable model of the cranial bone from the CT Cranium DICOM scan for pre-operative planning. The task requires completing InVesalius's full 3D reconstruction workflow: segmenting bone tissue, generating a surface mesh, and exporting it in STL format.

## Professional Context

Urologists, neurosurgeons, and oral & maxillofacial surgeons routinely use InVesalius to reconstruct 3D models from CT scans for surgical planning, patient-specific implant design, and teaching. Exporting an STL from a bone segmentation is the core InVesalius workflow used daily in these settings.

## Goal

Export a binary STL surface model of the cranial bone to `/home/ga/Documents/skull_model.stl`.

## Required Steps (not told to agent)

1. Create a new mask using the Bone threshold preset (226–3071 HU)
2. Generate a 3D surface from the bone mask
3. Navigate to the Export Data panel
4. Export the surface as STL to the specified path

## Success Criteria

- `/home/ga/Documents/skull_model.stl` exists
- File is a valid binary STL (80-byte header followed by triangle count)
- Triangle count > 10,000 (ensures actual cranial bone geometry, not a trivial mesh)
- File size > 200 KB

## Verification Strategy

The export_result.sh copies the STL and parses:
- File existence and size
- Binary STL magic: 80-byte header + uint32 triangle count
- Triangle count validation (must be > 10,000)

## Ground Truth

- DICOM: CT Cranium (/home/ga/DICOM/ct_cranium/0051), 108 slices, spacing 0.957×0.957×1.5 mm
- Bone threshold: 226–3071 HU
- Expected triangle count range: 50,000–500,000 for full skull

## Edge Cases

- ASCII STL also accepted (check for "solid" header)
- Agent may use "Compact Bone (Adult)" preset (662–1988) instead of "Bone"; still accepted if surface is generated
- File saved to a different but recognisable path: NOT accepted (verifier checks exact path)
