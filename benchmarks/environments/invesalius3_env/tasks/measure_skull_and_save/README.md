# Task: measure_skull_and_save

## Overview

A physical medicine and rehabilitation physician needs to document cranial dimensions from a CT Cranium scan for an anthropometric assessment. InVesalius includes a measurement tool (linear ruler) that can be used to place distance measurements directly on the slice views. The task requires placing two measurements and saving the project.

## Professional Context

Physical medicine physicians and radiologists frequently measure anatomical dimensions from CT scans for anthropometric studies, implant sizing, and surgical planning. InVesalius's measurement tool is analogous to PACS measurement calipers used in clinical practice.

## Goal

Using InVesalius's linear measurement tool, place at least two linear measurements in the axial view:
1. The **maximum transverse diameter** of the skull (left-to-right at the widest axial slice)
2. The **maximum anteroposterior diameter** of the skull (front-to-back)

Save the project to `/home/ga/Documents/cranial_measurements.inv3`.

## Required Steps (not told to agent)

1. Find and activate the linear measurement tool (Tools menu → Measurement or toolbar)
2. Place first measurement spanning the transverse (left-right) width of the skull
3. Place second measurement spanning the anteroposterior (front-back) depth of the skull
4. Save project via File > Save As to /home/ga/Documents/cranial_measurements.inv3

## Success Criteria

- `/home/ga/Documents/cranial_measurements.inv3` exists and is a valid .inv3 file
- `measurements.plist` within the project contains at least 2 measurements
- Each measurement has a value > 80 mm (realistic for adult cranium; transverse ~140–170 mm, AP ~160–190 mm)

## Verification Strategy

export_result.sh:
1. Opens the .inv3 tarfile
2. Reads measurements.plist
3. Extracts all measurement values from the `"value"` fields

## Ground Truth

- CT Cranium (Dataset 0051): Adult cranium, 108 axial slices
- Expected transverse diameter: ~140–170 mm
- Expected AP diameter: ~160–190 mm
- Acceptable range: > 80 mm per measurement (generous lower bound to accept partially correct placements)

## Edge Cases

- Measurements placed in sagittal or coronal views also accepted (value check is the gate)
- Three or more measurements also accepted
- Measurement tool may be in "Tools" menu under "Measure" or via toolbar icon
