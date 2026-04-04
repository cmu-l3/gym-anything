# fix_wrong_panel_dimensions

## Task Overview

**Difficulty**: very_hard
**Domain**: Precision machining / CAD quality review
**Occupation**: Quality Engineer

This task uses the error-injection design pattern. A rectangular steel panel drawing is open in SolveSpace with two existing PT_PT_DISTANCE constraints applied, but the constraint values are incorrect — they don't match the approved design specification. The agent must compare the drawing to the approved spec on the desktop, identify the discrepant constraint values, and correct them.

## Goal

The end state must be a corrected panel drawing saved as `/home/ga/Documents/SolveSpace/panel_corrected.slvs` containing the dimension constraint values that match the approved specification at `/home/ga/Desktop/panel_approved_spec.txt`.

The agent must:
1. Locate and read the approved specification document
2. Inspect the existing constraint values in the drawing
3. Identify which constraints do not match the spec
4. Correct the wrong constraint values
5. Save as `panel_corrected.slvs`

## Starting State

File: `/home/ga/Documents/SolveSpace/panel_wrong_dims.slvs`
Geometry: Rectangle with corners at (0,0), (120,0), (120,75), (0,75)
Constraints present: POINTS_COINCIDENT (×4), HORIZONTAL (×2), VERTICAL (×2), WHERE_DRAGGED (×1)
Injected errors: Two PT_PT_DISTANCE constraints with wrong values (type 30):
  - Width constraint: 95 mm (should be 120 mm per spec)
  - Height constraint: 50 mm (should be 75 mm per spec)

Spec file: `/home/ga/Desktop/panel_approved_spec.txt`

## Success Criteria

| Check | Points | Description |
|-------|--------|-------------|
| File exists and is new | 20 | `panel_corrected.slvs` saved after task start |
| Wrong width removed | 20 | No constraint with valA ≈ 95 mm present |
| Wrong height removed | 20 | No constraint with valA ≈ 50 mm present |
| Correct width present | 20 | Constraint with valA ≈ 120 mm present (±0.5 mm) |
| Correct height present | 20 | Constraint with valA ≈ 75 mm present (±0.5 mm) |

**Pass threshold**: 80 / 100

## Verification Strategy

`export_result.sh` parses `panel_corrected.slvs`, extracts all PT_PT_DISTANCE constraints (type=30), and writes values to `/tmp/fix_wrong_panel_dimensions_result.json`. The verifier checks both that wrong values are gone AND that correct values are present.

## Error Injection Documentation

The injected wrong values (95mm and 50mm) are documented in task.json metadata (`wrong_width_mm`, `wrong_height_mm`). The correct values (120mm, 75mm) are in `correct_width_mm`, `correct_height_mm`. The setup script injects exactly these two wrong constraints; the geometry (actual param coordinates) is at the correct dimensions but the constraint values override the solver.

## Edge Cases

- Agent cannot simply add new correct constraints — the old wrong ones must be removed or replaced. If both 95mm and 120mm constraints exist simultaneously, both "wrong removed" checks fail.
- The file geometry coordinates are at the correct size; the agent may notice the mismatch between geometry and constraint display when SolveSpace re-solves.
- Agent must save as `panel_corrected.slvs`, not overwrite `panel_wrong_dims.slvs`.
