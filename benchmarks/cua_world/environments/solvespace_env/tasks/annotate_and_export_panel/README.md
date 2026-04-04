# annotate_and_export_panel

## Task Overview

**Difficulty**: very_hard
**Domain**: Woodworking / CNC routing shop drawings
**Occupation**: CAD Drafter / Manufacturing Engineer

This task uses the REAL wooden box divider panel from the official SolveSpace tutorial project (`box-parts.zip` from `solvespace.com`). The panel is a 2D profile with corner notches for box assembly. The agent must add dimension annotations per the shop drawing specification on the desktop, save the annotated drawing, and export it as a DXF file for the CNC router operator.

## Goal

Two output files must exist after task completion:
1. **Annotated drawing**: `/home/ga/Documents/SolveSpace/divider_annotated.slvs` — the `.slvs` file with dimension constraints added
2. **DXF shop drawing**: `/home/ga/Documents/SolveSpace/divider_shop_drawing.dxf` — exported 2D DXF for NC programming

The required dimensions are listed in the shop drawing specification at `/home/ga/Desktop/panel_spec.txt`.

The agent must:
1. Read the shop drawing specification to identify required dimension annotations
2. Add the dimension constraints to `divider_annotate.slvs`
3. Save the annotated file as `divider_annotated.slvs`
4. Export the dimensioned 2D view as DXF to `divider_shop_drawing.dxf`

## Starting State

File: `/home/ga/Documents/SolveSpace/divider_annotate.slvs` (copy of the real `/opt/solvespace_samples/divider.slvs`)
Source: Official SolveSpace tutorial project — wooden box divider panel
Size: ~80 KB (real parametric drawing)
Geometry: Rectangular panel with corner notches, all fully constrained from the real tutorial

Shop drawing specification: `/home/ga/Desktop/panel_spec.txt`

## Success Criteria

| Check | Points | Description |
|-------|--------|-------------|
| Annotated .slvs exists and is new | 15 | `divider_annotated.slvs` saved after task start |
| New constraints added | 10 | At least 3 new PT_PT_DISTANCE constraints vs baseline |
| Width annotation correct | 15 | Constraint with valA ≈ 150 mm (±1 mm) |
| Height annotation correct | 15 | Constraint with valA ≈ 100 mm (±1 mm) |
| Notch depth correct | 15 | Constraint with valA ≈ 25 mm (±1 mm) |
| DXF exported | 30 | `divider_shop_drawing.dxf` exists, is new, and is >100 bytes |

**Pass threshold**: 70 / 100

## Verification Strategy

`export_result.sh` performs two checks:
1. Parses `divider_annotated.slvs` for PT_PT_DISTANCE constraints, comparing count to baseline (recorded before task start) and checking specific values
2. Checks `divider_shop_drawing.dxf` for existence, newness, and minimum file size

## Real Data Note

This task uses the actual `divider.slvs` file from the official SolveSpace tutorial. The file dimensions (150mm × 100mm panel, 25mm notches) are real design values from the tutorial project, not invented values. Source: `https://solvespace.com/dl/box-parts.zip`

## Edge Cases

- The divider.slvs already contains constraints — the baseline count is recorded before the task and the verifier only checks for NEW constraints added during the task.
- DXF export uses File > Export 2d Section... — this exports the active 2D sketch view. The agent must ensure the sketch is the active group before exporting.
- The agent must save two separate files: one `.slvs` (Save As to `divider_annotated.slvs`) and one `.dxf` (File > Export 2d Section...).
