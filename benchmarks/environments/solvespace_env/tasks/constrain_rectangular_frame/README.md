# constrain_rectangular_frame

## Task Overview

**Difficulty**: very_hard
**Domain**: HVAC duct flange expansion joint design (EN 1505)
**Occupation**: HVAC / Piping Engineer

A flat rubber gasket profile is open in SolveSpace showing two concentric rectangles (outer boundary and inner cutout), with horizontal, vertical, and coincident constraints applied but no dimensional constraints. The agent must read the project specification on the desktop and apply the four dimensional constraints that fully define the gasket profile.

## Goal

The end state must be a fully-constrained gasket sketch saved as `/home/ga/Documents/SolveSpace/gasket_frame_constrained.slvs` containing four distance dimension constraints per the project specification at `/home/ga/Desktop/gasket_specification.txt`.

The agent must:
1. Locate and read the gasket specification document
2. Identify all four required dimensions (outer W, outer H, inner W, inner H)
3. Add four PT_PT_DISTANCE constraints (type 30)
4. Save the file as `gasket_frame_constrained.slvs`

## Starting State

File: `/home/ga/Documents/SolveSpace/gasket_frame_start.slvs`
Geometry: Two concentric rectangles (8 line segments total)
- Outer rect: request handles 4–7 (corners at (0,0) to (200,150) in world units)
- Inner rect: request handles 8–11 (corners at (10,10) to (190,140) in world units)
Constraints present: POINTS_COINCIDENT (×8), HORIZONTAL (×4), VERTICAL (×4), WHERE_DRAGGED (×1)
Constraints missing: all PT_PT_DISTANCE (none applied)

Spec file: `/home/ga/Desktop/gasket_specification.txt`

## Success Criteria

| Check | Points | Description |
|-------|--------|-------------|
| File exists and is new | 20 | `gasket_frame_constrained.slvs` saved after task start |
| ≥4 PT_PT_DISTANCE constraints | 20 | File contains at least 4 constraints of type 30 |
| Outer width correct | 15 | One constraint valA ≈ 200 mm (±0.5 mm) |
| Outer height correct | 15 | One constraint valA ≈ 150 mm (±0.5 mm) |
| Inner width correct | 15 | One constraint valA ≈ 180 mm (±0.5 mm) |
| Inner height correct | 15 | One constraint valA ≈ 130 mm (±0.5 mm) |

**Pass threshold**: 80 / 100

## Verification Strategy

`export_result.sh` parses `gasket_frame_constrained.slvs`, extracts all PT_PT_DISTANCE constraints (type=30), and writes values to `/tmp/constrain_rectangular_frame_result.json`. The verifier checks file newness and each of the four required dimension values within ±0.5 mm.

## Edge Cases

- The inner rectangle values (180mm, 130mm) are close to the outer values minus the wall thickness — the agent must constrain both rectangles, not just the outer one.
- Agent may use any valid point pair for each dimension — any pair separated by the correct distance passes.
- The spec document name/location differs from the bracket task to prevent cross-task caching.

## Programmatic Scaffolding Note

The starting sketch is generated programmatically. Geometry dimensions (200×150mm outer, 10mm wall) match typical HVAC ductwork flange gasket proportions for a 200mm × 150mm duct.
