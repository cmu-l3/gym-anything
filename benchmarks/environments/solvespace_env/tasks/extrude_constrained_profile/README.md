# extrude_constrained_profile

## Task Overview

**Difficulty**: very_hard
**Domain**: Aluminium extrusion profile design / NC programming
**Occupation**: Manufacturing Engineer / Product Designer

A fully constrained 2D T-profile cross-section is open in SolveSpace. The manufacturing order on the desktop specifies the required extrusion length. The agent must create a 3D extrusion group from the sketch per the manufacturing order and save the 3D model.

## Goal

The end state must be a 3D SolveSpace model saved as `/home/ga/Documents/SolveSpace/profile_extruded.slvs` that contains an extrude group (Group.type=5100) with a depth constraint matching the manufacturing order at `/home/ga/Desktop/manufacturing_order.txt`.

The agent must:
1. Read the manufacturing order to determine the required extrusion length
2. Create a new extrude group from the T-profile sketch
3. Set the extrusion depth per the manufacturing order
4. Save the 3D model as `profile_extruded.slvs`

## Starting State

File: `/home/ga/Documents/SolveSpace/profile_sketch.slvs`
Geometry: T-profile cross-section with 8 line segments:
  - Base rectangle: 60mm wide × 40mm tall
  - Tab protrusion: 20mm wide × 15mm tall (centered on top of base)
Constraints present: fully constrained (COINCIDENT + HORIZ + VERT + WHERE_DRAGGED + all PT_PT_DISTANCE)
Groups: g001 (#references) + g002 (sketch-in-plane) — no extrude group yet

Manufacturing order: `/home/ga/Desktop/manufacturing_order.txt`

## Success Criteria

| Check | Points | Description |
|-------|--------|-------------|
| File exists and is new | 25 | `profile_extruded.slvs` saved after task start |
| Extrude group present | 50 | File contains Group.type=5100 |
| Extrusion depth correct | 25 | PT_PT_DISTANCE or equivalent depth constraint ≈ 100 mm (±1 mm) |

**Pass threshold**: 75 / 100

## Verification Strategy

`export_result.sh` parses `profile_extruded.slvs`, extracts all group types and all distance constraints, and writes to `/tmp/extrude_constrained_profile_result.json`. The verifier checks for Group.type=5100 (required) and a ≈100mm constraint (bonus points — some SolveSpace versions set extrude depth differently).

## Edge Cases

- SolveSpace extrude depth is typically set as a distance constraint in the new extrude group's sketch context. The verifier accepts any PT_PT_DISTANCE or DIAMETER constraint with value ~100mm anywhere in the file.
- If the agent creates the extrude group but doesn't set the depth, it scores 75/100 (passes at 75 threshold).
- The T-profile is fully constrained — the agent does NOT need to add any sketch constraints, only the extrude group.
