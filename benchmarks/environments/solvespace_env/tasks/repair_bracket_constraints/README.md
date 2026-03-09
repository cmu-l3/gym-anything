# repair_bracket_constraints

## Task Overview

**Difficulty**: very_hard
**Domain**: Sheet metal fabrication / Manufacturing engineering
**Occupation**: Mechanical Design Engineer

A shelf-mounting L-bracket sketch is open in SolveSpace with all geometry drawn and geometric constraints applied (lines connected, horizontal/vertical orientation locked), but no dimensional constraints. Without dimension constraints, the file cannot be sent to the CNC press-brake. The agent must read the component specification on the desktop, identify the required dimensions, and apply them to the sketch.

## Goal

The end state must be a fully-constrained L-bracket sketch saved as `/home/ga/Documents/SolveSpace/bracket_constrained.slvs` containing the three distance dimension constraints specified in the component specification document at `/home/ga/Desktop/bracket_specification.txt`.

The agent must:
1. Locate and read the specification document
2. Identify the three required dimensions from the spec
3. Add a PT_PT_DISTANCE constraint (type 30) for each dimension
4. Save the file as `bracket_constrained.slvs`

## Starting State

File: `/home/ga/Documents/SolveSpace/bracket_start.slvs`
Geometry: L-bracket with 6 line segments forming the profile
Constraints present: POINTS_COINCIDENT (×6), HORIZONTAL (×3), VERTICAL (×3), WHERE_DRAGGED (×1)
Constraints missing: all PT_PT_DISTANCE (none applied)

Spec file: `/home/ga/Desktop/bracket_specification.txt`

## Success Criteria

| Check | Points | Description |
|-------|--------|-------------|
| File exists and is new | 20 | `bracket_constrained.slvs` saved after task start |
| ≥3 PT_PT_DISTANCE constraints | 20 | File contains at least 3 constraints of type 30 |
| Horizontal arm length correct | 20 | One constraint valA ≈ 85 mm (±0.5 mm) |
| Vertical arm height correct | 20 | One constraint valA ≈ 60 mm (±0.5 mm) |
| Arm thickness correct | 20 | One constraint valA ≈ 10 mm (±0.5 mm) |

**Pass threshold**: 80 / 100

## Verification Strategy

`export_result.sh` parses `bracket_constrained.slvs`, extracts all PT_PT_DISTANCE constraints (type=30), and writes the values to `/tmp/repair_bracket_constraints_result.json`. The verifier checks file newness (timestamp > task start) and each required dimension value within ±0.5 mm.

## Edge Cases

- Agent may add constraints between points that are geometrically correct but not the canonical endpoints — any pair of points separated by the correct distance will pass.
- Agent might save to the wrong filename — verifier checks for the exact path `bracket_constrained.slvs`.
- Wrong-target: if agent saves a different file without the correct constraints, all dimension checks fail.

## Programmatic Scaffolding Note

The starting sketch is generated programmatically in `setup_task.sh` because no pre-existing SolveSpace L-bracket sketch with the required geometry is available in the environment. The geometry (85×60mm L-bracket with 10mm thickness) matches plausible real-world shelf mounting hardware. The scaffolding format matches the real SolveSpace 3.0.rc2 `.slvs` format exactly (same magic bytes, same block structure, same constraint type IDs).
