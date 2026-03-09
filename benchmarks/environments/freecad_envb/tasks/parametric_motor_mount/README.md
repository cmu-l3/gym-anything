# Task: Parametric NEMA 17 Motor Mount Design

## Domain Context

**Persona**: Robotics Engineer
**Software**: FreeCAD (PartDesign + Spreadsheet workbenches)
**Industry**: Robotics / Mechatronics
**Occupation GDP rank**: #1 — Robotics Engineers, importance=94, GDP=$61.7M

Robotics engineers routinely design custom motor mounts, brackets, and structural components in FreeCAD for robot arms, mobile platforms, and automated machinery. A parametric design approach using FreeCAD's Spreadsheet workbench is standard professional practice, allowing the same design to be adapted for different motor frame sizes without redrawing from scratch.

## Task Overview

Design a parametric NEMA 17 stepper motor mount bracket in FreeCAD using PartDesign. The mount must:
1. Use a Spreadsheet with named parameters for all critical dimensions
2. Include 4 M3 motor bolt holes at the NEMA 17 standard pattern (31mm × 31mm square, centered)
3. Include a 22mm central bore for the motor shaft collar boss
4. Include at least 2 frame-mounting holes for attachment to a V-slot 2020 extrusion frame
5. Be exportable as STL for 3D printing validation

## Real Data Sources

- **NEMA 17 Standard**: NEMA ICS 16 standard motor frame specification
  - Motor body: 42.3mm × 42.3mm
  - Mounting holes: 4× M3 at 31mm × 31mm square pattern, centered on shaft axis
  - Shaft collar boss: 22mm diameter
- **V-slot 2020 aluminum extrusion**: Standard 20mm slot pitch for T-nut attachment

These are publicly documented industry standards used in thousands of real robot designs worldwide.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| FCStd file exists | 10 | `/home/ga/Documents/FreeCAD/motor_mount.FCStd` is present |
| FCStd modified after task start | 10 | File was created/modified during this session |
| Spreadsheet with named cells | 15 | Has `Spreadsheet::Sheet` object with ≥3 aliased cells |
| PartDesign Body present | 5 | Has `PartDesign::Body` object |
| At least one Pad | 5 | Has `PartDesign::Pad` (main plate body) |
| Motor bolt holes (≥4 pockets/holes) | 20 | At least 4 `PartDesign::Hole` or `PartDesign::Pocket` objects |
| Frame mounting holes (≥6 total pockets/holes) | 10 | Additional holes for frame attachment bring total to ≥6 |
| STL exported and non-trivial | 25 | `/home/ga/Documents/FreeCAD/motor_mount.stl` exists, >5 KB |
| **Total** | **100** | **Pass threshold: 70** |

## Why This Is Hard

- The agent must know the NEMA 17 standard specifications (or discover them from the task description)
- The agent must use the Spreadsheet workbench (not commonly known) to define parametric dimensions
- The agent must create a PartDesign workflow with a base plate, multiple hole features, and a central bore — all without step-by-step UI guidance
- The agent must figure out how to export to STL as a separate action after modeling
- Failure in any single feature (no spreadsheet, wrong hole count, no STL) results in partial scoring below the pass threshold

## Verification Strategy

1. Copy `/tmp/parametric_motor_mount_result.json` from VM for timestamp and file existence metadata
2. Copy `/home/ga/Documents/FreeCAD/motor_mount.FCStd` from VM and parse as ZIP → Document.xml
3. Parse `<Objects>` section to count object types
4. Check for `Spreadsheet::Sheet` type and scan for aliased `<Cell>` elements
5. Count `PartDesign::Hole` and `PartDesign::Pocket` objects for hole features
6. Copy `/home/ga/Documents/FreeCAD/motor_mount.stl` and check size

## Edge Cases

- Agent may use PartDesign::Hole instead of Pocket for bolt holes — both are valid and checked
- Agent may define fewer than 3 Spreadsheet aliases but still have valid parametric design — partial credit given
- STL export might be omitted if agent runs out of steps — partial credit via FCStd criteria
- Agent might use Part workbench boolean instead of PartDesign — still detectable as Pocket-type features

## Schema Reference

**FCStd Document.xml** relevant object types:
- `Spreadsheet::Sheet` — spreadsheet with named parameters
- `PartDesign::Body` — container for PartDesign solid
- `Sketcher::SketchObject` — 2D sketch for profiles
- `PartDesign::Pad` — extrusion feature
- `PartDesign::Pocket` — pocket/subtraction feature
- `PartDesign::Hole` — dedicated hole feature (with thread options)
- `PartDesign::PolarPattern` — circular pattern (for 4-hole bolt pattern)
- `PartDesign::LinearPattern` — rectangular pattern alternative
