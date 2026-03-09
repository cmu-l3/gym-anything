# Task: radiation_tissue_atlas

## Overview

**Professional Context**: Medical physics / radiation oncology — defining target volumes and organs at risk (OARs) from CT for radiation treatment planning.

Radiation treatment planning (RTP) requires precise delineation of the target (tumor) volume and all critical surrounding structures. In brain radiation therapy, the key structures are: (1) the brain parenchyma or target volume, (2) the bony skull which absorbs and scatters radiation, and (3) the orbits/periorbital fat which must be protected from dose. Medical physicists use 3D surface models exported from segmentation software to define isocenter placement, field margins, and dose-volume constraints.

**Occupational Category**: Healthcare Practitioners and Technical / Medical Physicists

**Industry significance**: Medical physics is a multi-billion dollar clinical service area directly dependent on CT-based tissue segmentation tools like InVesalius.

---

## Goal

Create a 3-tissue radiation planning atlas:
1. Brain soft tissue mask (HU -100 to 80)
2. Compact bone/skull mask (HU ≥ 600)
3. Periorbital fat mask (HU -300 to -20)
4. 3D surfaces for all three, exported as separate STL files
5. ≥5 distance measurements
6. Complete project saved

---

## What Makes This Extremely Hard

**Three distinct HU regimes required simultaneously**:
- Near-zero HU (brain: -100 to 80) — brain soft tissue
- Negative HU (fat: -300 to -20) — uses negative thresholding like Task 1 but different range
- High positive HU (bone: ≥ 600) — dense cortical bone

All three must coexist as separate masks in the same project. The agent must correctly:
1. Set a very narrow, near-zero HU range for brain (cannot use the full tissue range)
2. Set a negative HU range for periorbital fat (different from the very-negative air range)
3. Set a high HU range for bone

**Three STL exports**: Each of the three masks requires its own surface reconstruction and STL export to a specific named path — the highest number of STL exports in any single task.

**Five measurements**: The inter-tissue distance measurements require navigating between tissue boundaries in multiple slice views.

**Sequential dependencies**: Surfaces cannot be exported until masks exist; measurements require slice navigation to correct anatomical locations.

**No UI path provided**: The agent must independently discover how to create masks with custom HU ranges, generate surfaces, export each STL separately, and take measurements.

---

## Starting State

- InVesalius 3 running with CT Cranium DICOM pre-loaded
- Output directory `/home/ga/Documents/rt_planning/` created
- Treatment planning brief at `/home/ga/Documents/rt_planning/planning_brief.txt`
- No pre-existing STL or .inv3 output files

---

## Scoring (100 pts, pass ≥ 65)

| Criterion | Points |
|-----------|--------|
| Project file saved and valid | 10 |
| Brain soft tissue mask (min ≥ -100, max ≤ 80) | 20 |
| Compact bone mask (min ≥ 600) | 20 |
| Periorbital fat mask (max ≤ -20, min ≥ -300) | 20 |
| All 3 STL files valid | 15 |
| ≥ 5 measurements | 15 |

---

## HU Range Reference (CT Cranium 0051)

| Tissue | Typical HU range | Task requirement |
|--------|-----------------|-----------------|
| Air (sinuses) | -1000 to -900 | Not required here |
| Periorbital fat | -150 to -50 | max ≤ -20, min ≥ -300 |
| Brain parenchyma | -10 to 45 | min ≥ -100, max ≤ 80 |
| Dura/blood | 50 to 80 | Included in brain mask |
| Compact bone | 700 to 2000 | min ≥ 600 |

---

## Anti-Gaming

- HU range validation from mask_N.plist in .inv3 ensures all three distinct tissue types were separately segmented
- Three separate STL files at three specific named paths — cannot be satisfied by a single export
- Measurement count ≥ 5 requires genuine inter-tissue distance assessment
- Output-existence gate: do-nothing returns score = 0
- Independent .inv3 re-analysis catches discrepancies from export JSON
