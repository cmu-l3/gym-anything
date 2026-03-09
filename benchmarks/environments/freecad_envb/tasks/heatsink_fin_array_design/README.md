# Task: Parametric Heatsink with Fin Array Design

## Domain Context

**Persona**: Electronics Engineer
**Software**: FreeCAD (PartDesign + Spreadsheet workbenches)
**Industry**: Power Electronics / Thermal Management
**Occupation GDP rank**: #3 — Electronics Engineers (Except Computer), importance=89, GDP=$21.1M

Electronics engineers designing power electronics routinely create custom heatsinks in FreeCAD when standard catalog heatsinks don't fit the PCB layout or thermal requirements. The parametric design approach with a fin array (using LinearPattern) is standard practice, allowing thermal engineers to quickly evaluate different fin geometries by changing Spreadsheet parameters.

## Task Overview

Design a parametric aluminum heatsink for a TO-220 power package:

1. Flat base plate with TO-220 package mounting interface (JEDEC TO-220 dimensions)
2. Fin array: ≥8 fins using PartDesign LinearPattern (driven by Spreadsheet parameters)
3. Spreadsheet with ≥4 named parameters: fin count, fin height, fin thickness, base thickness
4. At least 2 M3 mounting holes for PCB/chassis attachment
5. Export to both STL (for 3D print prototype) and STEP (for machining)

## Real Data Sources

- **JEDEC TO-220 Package Standard**: JESD77-B / TO-220 outline specification (publicly available from JEDEC)
  - Mounting surface: 15.9mm × 10.15mm (nominal)
  - Mounting hole: 3.5mm diameter (standard TO-220 mounting hole)
  - Mounting hole offset: 5.08mm from package body edge
  - Source: JEDEC publication JESD77-B, widely reproduced in component datasheets
- **Aluminum thermal properties**: Common aluminum alloys (6061-T6) used for heatsinks: λ = 167 W/(m·K), density = 2.7 g/cm³

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| FCStd file exists | 10 | `/home/ga/Documents/FreeCAD/heatsink.FCStd` present |
| FCStd modified after task start | 10 | File created/modified this session |
| Spreadsheet with ≥4 named parameters | 20 | `Spreadsheet::Sheet` with ≥4 aliased cells |
| PartDesign Body with base Pad | 10 | `PartDesign::Body` + at least 1 `PartDesign::Pad` |
| LinearPattern for fins | 25 | `PartDesign::LinearPattern` present (for fin array) |
| Mounting holes/pockets (≥2) | 10 | At least 2 `PartDesign::Hole` or `PartDesign::Pocket` for mounting |
| STL exported (>1 KB) | 7 | `/home/ga/Documents/FreeCAD/heatsink.stl` present |
| STEP exported (>1 KB) | 8 | `/home/ga/Documents/FreeCAD/heatsink.step` present |
| **Total** | **100** | **Pass threshold: 70** |

## Why This Is Hard

- LinearPattern is a non-obvious feature for creating fin arrays — the agent must discover this PartDesign feature
- The Spreadsheet workbench must be used AND properly linked to the PartDesign model (aliases must be referenced in sketches)
- A complete heatsink requires: base pad + fin sketch + fin pad + linear pattern + mounting hole features — a chain of 4+ dependent operations
- Exporting to both STL and STEP requires two separate export actions
- The TO-220 mounting geometry requires understanding the real package standard

## Verification Strategy

1. Copy `/tmp/heatsink_fin_array_design_result.json` for timestamps
2. Copy `/home/ga/Documents/FreeCAD/heatsink.FCStd`, parse as ZIP → Document.xml
3. Count `Spreadsheet::Sheet` and scan for aliased cells (need ≥4)
4. Verify `PartDesign::Body` and `PartDesign::Pad`
5. Verify `PartDesign::LinearPattern` presence (the key feature for fin arrays)
6. Count mounting holes/pockets (≥2 required)
7. Copy `.stl` and `.step` files, check sizes

## Edge Cases

- Agent might use Part workbench array instead of PartDesign LinearPattern — `Part::Array` or `Part::Mirror` would not satisfy the LinearPattern check but structural complexity check provides partial credit
- Agent might create fin array by hand (8 separate Pad features) instead of using LinearPattern — gets partial credit for Pad count but misses the LinearPattern criterion
- Spreadsheet parameters not linked to sketch: the parametric design isn't functional, but the verifier checks for object presence, not linkage correctness
- Step vs STEP extension: both `.step` and `.stp` extensions checked

## Schema Reference

**TO-220 Package Geometry (JEDEC JESD77-B):**
```
Mounting surface: 15.9 × 10.15 mm
Mounting hole: 3.5mm diameter
Mounting hole position: 5.08mm from package body edge
Typical base plate for heatsink: ~20mm × 15mm minimum
Recommended fin height: 20-30mm for natural convection
Recommended fin thickness: 1.5-2mm
Recommended fin pitch: 4-6mm (for natural convection)
```
