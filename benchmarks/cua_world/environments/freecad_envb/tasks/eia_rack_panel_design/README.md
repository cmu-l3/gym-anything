# Task: EIA-310 1U Rack-Mount Panel Design

## Domain Context

**Persona**: Electronics Engineer
**Software**: FreeCAD (PartDesign + Spreadsheet workbenches)
**Industry**: Test & Measurement / Electronics Instrumentation
**Occupation GDP rank**: #3 — Electronics Engineers (Except Computer), importance=89, GDP=$21.1M

Electronics engineers routinely design rack-mount instrument panels following EIA-310 standard specifications. FreeCAD is used for sheet metal panel design, connector cutout layout, and export to STEP for CNC machining or sheet metal bending. Parametric design is essential because panel variants (1U/2U/3U) share the same connector layout with different heights.

## Task Overview

Design a 1U 19-inch rack-mount front panel per EIA-310 standard:

1. Panel body: 482.6mm wide × 44.45mm tall × 2mm thick aluminum
2. Rack-ear mounting holes: 4× M6 clearance holes at EIA-310 standard positions (31.75mm vertical centers per ear)
3. BNC connector cutouts: 2× circular holes (15mm diameter) on left half of panel
4. DE-9 (D-sub 9-pin) rectangular cutout: 1× (31.6mm × 12.5mm) on right half
5. Parametric Spreadsheet: panel height, width, thickness, BNC diameter as named parameters
6. Export: Save as FCStd + STEP for fabrication

## Real Data Sources

- **EIA-310 Standard**: Electronic Industries Alliance EIA-310-D (Cabinets, Racks, Panels, and Associated Equipment)
  - 1U height: 44.45mm (1.75 inches exactly)
  - Full rack width: 482.6mm (19 inches exactly)
  - Rack-ear hole centers: 31.75mm (1.25 inch) vertical spacing
  - Source: Published ANSI/EIA-310 standard, widely available in electronics engineering references
- **BNC connector**: IEC 61169-8 standard; 15mm panel cutout is the industry standard
- **DE-9 D-sub connector**: Standard panel cutout: 31.6mm × 12.5mm (IEC 61076-3-101)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| FCStd file exists | 10 | `/home/ga/Documents/FreeCAD/rack_panel.FCStd` present |
| FCStd modified after task start | 10 | File created/modified this session |
| Spreadsheet with named params (≥3 aliases) | 20 | `Spreadsheet::Sheet` with ≥3 named cells |
| PartDesign Body with Pad | 10 | `PartDesign::Body` + `PartDesign::Pad` present |
| At least 4 cutout/hole features | 25 | Count of `PartDesign::Pocket` + `PartDesign::Hole` ≥ 4 (3 connectors + some mounting holes) |
| STEP file exported (>5 KB) | 25 | `/home/ga/Documents/FreeCAD/rack_panel.step` present and non-trivial |
| **Total** | **100** | **Pass threshold: 70** |

## Why This Is Hard

- Must translate real-world EIA-310 standard dimensions into precise CAD geometry
- Must use Spreadsheet workbench for parametric design (not commonly demonstrated in tutorials)
- Creating multiple different-shaped cutouts (circular BNC + rectangular D-sub + mounting holes) requires several distinct Pocket operations
- STEP export is less common than STL — agent must discover the correct export format and filter
- The panel has precise dimensional requirements; off-by-much dimensions would fail real manufacturing checks

## Verification Strategy

1. Copy `/tmp/eia_rack_panel_design_result.json` for timestamps
2. Copy `/home/ga/Documents/FreeCAD/rack_panel.FCStd`, parse as ZIP → Document.xml
3. Check for `Spreadsheet::Sheet` object and count aliased cells
4. Check for `PartDesign::Body`, `PartDesign::Pad`
5. Count `PartDesign::Pocket` + `PartDesign::Hole` objects (need ≥4 for 2 BNC + 1 DE-9 + some mounting holes)
6. Copy `/home/ga/Documents/FreeCAD/rack_panel.step` and check file size

## Edge Cases

- Agent might create circular pockets instead of Hole features for BNC cutouts — both are valid
- Agent might name the STEP file with `.stp` extension instead of `.step` — check both extensions
- Agent might not include the DE-9 cutout (rectangular cutout is harder to create than circular) — partial credit for 3+ features
- Spreadsheet aliases: agent might use Spreadsheet for formulas but without aliases — check for any named cell content

## Schema Reference

**EIA-310 1U Panel Geometry:**
```
Width:  482.6mm
Height:  44.45mm (= 1.75 inches = 1U)
Thickness: 2mm typical aluminum

Rack ear holes (each side):
  - Center 1: 6.35mm from top edge, 7.94mm from side edge
  - Center 2: 38.1mm from top edge, 7.94mm from side edge
  - (31.75mm vertical centers)

BNC cutout: 15.0mm diameter circle
DE-9 cutout: 31.6mm wide × 12.5mm tall rectangle
```
