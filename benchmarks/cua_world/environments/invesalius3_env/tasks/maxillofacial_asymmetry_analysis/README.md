# Task: maxillofacial_asymmetry_analysis

## Overview

**Professional Context**: Oral and maxillofacial surgery — pre-operative bilateral symmetry documentation for orthognathic surgery planning.

Orthognathic surgery corrects skeletal jaw discrepancies (malocclusion, facial asymmetry, micrognathia). Pre-operative planning requires quantitative documentation of the degree and distribution of asymmetry across all craniofacial regions. Surgeons and orthodontists use CT-based 3D surface models and bilateral measurements to plan osteotomy sites, measure correction distances, and document the baseline asymmetry for comparison with post-operative CT.

This is the highest-complexity task in the invesalius3_env environment, combining the highest measurement count (12+) with the highest number of orientation screenshots (5) of any task.

**Occupational Category**: Healthcare Practitioners and Technical / Oral and Maxillofacial Surgeons

**Economic significance**: Oral and maxillofacial surgeons are identified in the master_dataset.csv as a top-2 occupation for InVesalius by product_gdp_usd. Their use case ("Critical for viewing CBCT, panoramic X-rays, and 3D imaging essential for diagnosing impactions, cysts, and planning reconstruction") directly informs this task.

---

## Goal

1. Create bone segmentation mask
2. Generate 3D bone surface
3. Place ≥12 measurements (bilateral protocol)
4. Export STL surface
5. Capture 5 orientation screenshots (anterior, left lateral, right lateral, superior, posterior)
6. Save complete project

---

## What Makes This Extremely Hard

**Highest measurement count**: 12 measurements — the most of any task in the environment. Placing 12 measurements requires extensive navigation across multiple slices, bilateral attention, and careful landmark identification.

**Five orientation screenshots**: More screenshots than any other task. The existing `multi_view_3d_documentation` requires 3 screenshots; `forensic_craniometric_protocol` also requires 3. This task requires 5 — anterior, left lateral, right lateral (mirror of left lateral), superior, AND posterior. Getting 5 distinct orientation screenshots requires 5 separate rotations and saves in the 3D viewer.

**Bilateral protocol complexity**: The task explicitly requires both LEFT and RIGHT measurements at corresponding anatomical locations. This means the agent cannot just place 12 measurements randomly — at least 4 bilateral pairs are needed, requiring the agent to navigate to both sides of the skull at symmetric locations.

**Five output artifacts** (counting the project): STL + 5 PNGs + .inv3 = 7 output files total. Managing 7 output files in a single session is the most complex output management in the environment.

**No UI path provided**: The agent must independently:
- Find the measurement tool
- Navigate to bilateral anatomical landmarks
- Rotate the 3D surface to 5 distinct orientations and save each one
- Export STL
- Save the project

---

## Starting State

- InVesalius 3 running with CT Cranium DICOM pre-loaded
- `/home/ga/Documents/asymmetry_study/` directory created
- Assessment form at `/home/ga/Documents/asymmetry_study/assessment_form.txt`
- No pre-existing output files

---

## Scoring (100 pts, pass ≥ 65)

| Criterion | Points |
|-----------|--------|
| Project file saved and valid | 10 |
| ≥ 12 measurements in project | 25 |
| All measurements ≥ 10 mm | 10 |
| STL file valid (≥ 10,000 triangles) | 20 |
| anterior_view.png valid (≥ 10 KB) | 7 |
| left_lateral.png valid (≥ 10 KB) | 7 |
| right_lateral.png valid (≥ 10 KB) | 7 |
| superior_view.png valid (≥ 10 KB) | 7 |
| posterior_view.png valid (≥ 10 KB) | 7 |

**Total PNG points: 35** — the largest single criterion group, reflecting the importance of multi-orientation documentation.

---

## Expected Measurement Values (CT Cranium 0051)

For bilateral measurements (left/right pairs should differ by < 5 mm in a symmetric skull):
- Temporal width (each side): 20–40 mm
- Orbital width (each side): 35–45 mm
- Mastoid height (each side): 25–40 mm
- Parietal span (each side): 50–80 mm

Midline / overall:
- Maximum cranial length: 165–195 mm
- Maximum cranial breadth: 130–160 mm
- Cranial height: 120–145 mm
- Minimum frontal breadth: 90–110 mm

All measurements ≥ 10 mm (the 10mm floor excludes spurious very-short clicks).

---

## Anti-Gaming

- 12 measurement threshold is far above any achievable by accident (existing max is 5)
- 5 PNG files at 5 specific named paths cannot be satisfied by a single screenshot operation
- STL ≥ 10,000 triangles ensures real bone geometry
- PNG minimum size ≥ 10 KB ensures actual rendered screenshots
- Output-existence gate: do-nothing returns score = 0
- Independent .inv3 re-analysis for measurement count
- Independent PNG re-analysis via copy_from_env + magic bytes verification
