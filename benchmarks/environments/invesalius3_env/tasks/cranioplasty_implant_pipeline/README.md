# Task: cranioplasty_implant_pipeline

## Overview

**Professional Context**: Biomedical engineering / medical device manufacturing — patient-specific cranioplasty implant fabrication.

Cranioplasty (surgical skull reconstruction) requires fabricating patient-specific implants that match the exact geometry of the defect. Biomedical engineers use CT-derived 3D models to create these implants. The process involves: (1) separating the cortical shell from the cancellous interior to understand bone microarchitecture, (2) optimising the mesh for additive manufacturing tolerances, and (3) documenting calvarial dimensions for implant sizing.

This task uniquely combines two distinct InVesalius workflows:
- **Boolean mask operations** (from `boolean_mask_operations` task concept)
- **Mesh optimisation** (from `surface_mesh_optimization` task concept)

Neither existing task in the environment chains these together. This task requires executing them in the correct dependency order: masks → boolean → surfaces → optimize → export.

**Occupational Category**: Healthcare Practitioners and Technical / Biomedical Engineers

---

## Goal

10-step pipeline:
1. Create full bone mask (226–3071 HU)
2. Create compact cortical bone mask (662–3071 HU)
3. Boolean MINUS → cancellous bone mask
4. Generate surfaces for compact + cancellous bone
5. Apply mesh smoothing (≥10 iterations) to compact bone surface
6. Apply mesh decimation (< 400,000 triangles) to compact bone surface
7. Export optimised compact bone → PLY `/home/ga/Documents/cranioplasty/cortical_bone.ply`
8. Export cancellous bone → STL `/home/ga/Documents/cranioplasty/cancellous_bone.stl`
9. Place ≥5 calvarial dimension measurements
10. Save complete project → `/home/ga/Documents/cranioplasty/implant_fabrication.inv3`

---

## What Makes This Extremely Hard

**Longest sequential dependency chain** in the environment: 10 ordered steps where each step depends on the previous one. Steps 1–4 must complete before step 5 can start; step 5 must complete before step 6; step 6 before step 7; etc.

**Two distinct InVesalius capability areas chained together**: Boolean mask operations (Data > Mask > Boolean) AND mesh optimisation (3D Surface options) — requiring the agent to navigate to fundamentally different parts of the application.

**Dual export format requirement**: PLY (for compact bone, after optimisation) AND STL (for cancellous bone, unoptimised). The agent must export two different surfaces in two different formats.

**Three-mask boolean workflow**: Unlike the existing `boolean_mask_operations` task (which also requires 3 masks + boolean), this task additionally requires mesh optimisation on the resulting surfaces — adding 3 extra steps (smooth, decimate, PLY export).

**Mesh quality constraint**: Decimation must reduce to < 400,000 triangles — the agent must apply the right decimation percentage, not just click it once.

**Verification uniqueness**: PLY format verification (element vertex header), STL verification, ≥3 masks from .inv3, ≥5 measurements — 5 independent criteria.

---

## Starting State

- InVesalius 3 running with CT Cranium DICOM pre-loaded
- `/home/ga/Documents/cranioplasty/` directory created
- Fabrication specs at `/home/ga/Documents/cranioplasty/fab_specs.txt`
- No pre-existing output files

---

## Scoring (100 pts, pass ≥ 65)

| Criterion | Points |
|-----------|--------|
| Project file saved and valid | 10 |
| ≥ 3 masks (full bone + compact + boolean result) | 20 |
| PLY file valid (≥ 1,000 vertices) | 25 |
| STL (cancellous) file valid | 20 |
| ≥ 5 measurements (all ≥ 10 mm) | 15 |
| PLY triangle count < 400,000 (decimation applied) | 10 |

---

## Anti-Gaming

- PLY format verified by reading ASCII header (`element vertex N`, `element face N`) — not just existence
- STL verified by binary struct parsing or ASCII `facet normal` counting
- ≥3 masks in .inv3 requires: full bone + compact bone + boolean result (cannot be faked)
- PLY triangle < 400,000 ensures decimation was applied (raw mesh from CT typically 500K–2M triangles)
- Measurement count ≥ 5 + value ≥ 10 mm rejects spurious short clicks
- Output-existence gate: do-nothing returns score = 0

## PLY Format Reference

InVesalius exports PLY as ASCII header + binary or ASCII body:
```
ply
format ascii 1.0
element vertex N
property float x
property float y
property float z
element face M
property list uchar int vertex_indices
end_header
```
Verification checks for `ply` keyword on line 1 and `element vertex N` line.
