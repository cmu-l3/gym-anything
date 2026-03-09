# Task: Structural Steel Gusset Plate Connection Design

## Domain Context

**Persona**: Architectural Drafter / Structural Drafter
**Software**: FreeCAD (PartDesign workbench)
**Industry**: Structural Steel Fabrication / Civil/Architectural Engineering
**Occupation GDP rank**: #5 — Architectural and Civil Drafters, importance=94, GDP=$5.9M

Architectural and civil drafters regularly model structural steel connection details in CAD for fabrication shop drawings. A gusset plate connection is one of the most common structural steel details, used to connect diagonal braces to columns and beams in steel-framed buildings. The design must comply with AISC standard connection geometry including bolt pattern layout, edge distances, and weld preparation.

## Task Overview

Design a steel gusset plate connection bracket in FreeCAD:

1. Main gusset plate body: ~250mm × 200mm × 12mm
2. Brace bolt group: 4× M20 clearance holes (22mm dia) in 2×2 pattern (70mm gauge, 75mm pitch)
3. Column bolt group: 4× M20 clearance holes in 2×2 pattern along left edge
4. Weld prep chamfer: 45° chamfer on brace attachment edge
5. Spreadsheet / BOM table listing key plate and bolt parameters
6. Export: FCStd + STEP for fabrication shop

## Real Data Sources

- **AISC Steel Construction Manual**: American Institute of Steel Construction standard connection design
  - Standard gusset plate connection geometry for W-section columns
  - M20 bolt (22mm clearance hole) — AISC standard bolt
  - 70mm gauge and 75mm pitch — standard AISC connection spacing
  - 45° weld chamfer — standard AWS D1.1 weld prep
  - Source: AISC Steel Construction Manual 15th Edition, widely used by structural engineers
- **W8×31 wide-flange column**: Standard ASTM A992 wide-flange section (published in AISC section tables)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| FCStd file exists | 10 | `/home/ga/Documents/FreeCAD/gusset_plate.FCStd` present |
| FCStd modified after task start | 10 | File created/modified this session |
| Spreadsheet (BOM table) | 15 | `Spreadsheet::Sheet` object present |
| PartDesign Body with base Pad | 10 | `PartDesign::Body` + `PartDesign::Pad` present |
| At least 6 bolt holes | 30 | `PartDesign::Hole` + `PartDesign::Pocket` count ≥ 6 (2 bolt groups × 4 holes − some margin) |
| Chamfer or Fillet present | 10 | `PartDesign::Chamfer` or `PartDesign::Fillet` object present (weld prep) |
| STEP file exported (>5 KB) | 15 | `/home/ga/Documents/FreeCAD/gusset_plate.step` present and non-trivial |
| **Total** | **100** | **Pass threshold: 70** |

## Why This Is Hard

- The bolt group layout requires knowledge of AISC standard gauge/pitch dimensions — the agent must read and interpret the professional specification
- Creating two separate bolt groups in different orientations requires precise positioning in 2D sketches
- The chamfer is an additional feature that must be applied to a specific edge — requires selecting the correct face/edge
- 8 total bolt holes means 8 separate cut features or a combination of patterns — requires multi-step PartDesign workflow
- STEP export for fabrication is less intuitive than STL export in FreeCAD

## Verification Strategy

1. Copy `/tmp/structural_gusset_plate_result.json` for timestamps
2. Copy `/home/ga/Documents/FreeCAD/gusset_plate.FCStd`, parse as ZIP → Document.xml
3. Check for `Spreadsheet::Sheet`
4. Check `PartDesign::Body` + `PartDesign::Pad`
5. Count `PartDesign::Hole` + `PartDesign::Pocket` objects (need ≥6)
6. Check for `PartDesign::Chamfer` or `PartDesign::Fillet`
7. Copy `/home/ga/Documents/FreeCAD/gusset_plate.step`, check size

## Edge Cases

- Agent might use Part workbench Cut instead of PartDesign::Pocket — detectable as `Part::Cut` or `Part::MultiCut`; verifier checks both PartDesign and Part types for flexibility
- Chamfer vs Fillet: Both are valid weld prep features; verifier accepts either
- 6 vs 8 bolt holes: Awarding points at ≥6 allows partial completion if agent only finishes one bolt group (4+2 = 6 total holes still passes this threshold)
- Spreadsheet content: Just having the object is sufficient; verifier does not check cell content

## Schema Reference

**AISC Gusset Plate Connection Geometry:**
```
Plate: 250mm wide × 200mm tall × 12mm thick (A36 steel plate)

Brace bolt group (upper-left quadrant):
  Layout: 2 columns × 2 rows = 4 bolts
  Gauge (column spacing): 70mm
  Pitch (row spacing): 75mm
  Bolt: M20, clearance hole = 22mm diameter

Column bolt group (left edge):
  Layout: 2 columns × 2 rows = 4 bolts
  Same gauge and pitch as brace group
  Positioned along left edge for column flange attachment

Weld prep:
  45° chamfer, 6mm depth
  Applied to top edge (brace attachment edge)
```
