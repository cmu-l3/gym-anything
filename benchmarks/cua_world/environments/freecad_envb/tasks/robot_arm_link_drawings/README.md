# Task: Robot Arm Link Engineering Drawing Package

## Domain Context

**Persona**: Robotics Engineer
**Software**: FreeCAD (TechDraw workbench)
**Industry**: Robotics / Mechanical Engineering
**Occupation GDP rank**: #1 — Robotics Engineers, importance=94, GDP=$61.7M

Engineering drawings are a core deliverable in robotics development. Once a 3D model is approved, a formal 2D drawing package must be created for the machining shop. FreeCAD's TechDraw workbench is the standard tool for creating ISO-compliant engineering drawings with orthographic projection views, dimension annotations, and title blocks.

## Task Overview

Using an existing T8 lead screw housing bracket model (`T8_housing_bracket.FCStd`), create a complete engineering drawing package using FreeCAD's TechDraw workbench:

1. Front orthographic projection view of the bracket
2. Right-side orthographic projection view
3. Top orthographic projection view
4. At least one isometric or auxiliary view for spatial context
5. At least 6 critical dimension annotations (overall dimensions, hole center distances, etc.)
6. Export drawing as PDF to `/home/ga/Documents/FreeCAD/bracket_drawing.pdf`
7. Save updated FreeCAD document to `/home/ga/Documents/FreeCAD/bracket_drawing.FCStd`

## Real Data Sources

- **T8_housing_bracket.FCStd**: Real T8 lead screw housing bracket from the FreeCAD-library (github.com/FreeCAD/FreeCAD-library). This is a real mechanical part used in 3D printers, CNC routers, and linear motion systems worldwide.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| FCStd file exists | 10 | `/home/ga/Documents/FreeCAD/bracket_drawing.FCStd` present |
| FCStd modified after task start | 10 | File created/modified this session |
| TechDraw page exists | 20 | Has `TechDraw::DrawPage` object |
| At least 2 projection views | 15 | `DrawViewPart` or `DrawProjGroupItem` count ≥ 2 |
| At least 3 projection views | 10 | View count ≥ 3 (bonus) |
| At least 3 dimensions | 20 | `TechDraw::DrawViewDimension` count ≥ 3 |
| PDF exported (>5 KB) | 15 | `/home/ga/Documents/FreeCAD/bracket_drawing.pdf` present and non-trivial |
| **Total** | **100** | **Pass threshold: 70** |

## Why This Is Hard

- TechDraw is an advanced workbench requiring the agent to understand orthographic projection, view placement, and dimension annotation without step-by-step guidance
- The agent must open an existing model, add TechDraw content, and save under a new filename
- Creating dimensions requires selecting edges or vertices on the drawing views — complex interaction
- PDF export is a separate step from saving the FCStd
- The agent must discover TechDraw workbench, create pages, add views, and place dimensions entirely through exploration

## Verification Strategy

1. Copy `/tmp/robot_arm_link_drawings_result.json` for timestamps
2. Copy `/home/ga/Documents/FreeCAD/bracket_drawing.FCStd`, parse as ZIP → Document.xml
3. Scan `<Objects>` for `TechDraw::DrawPage`, `TechDraw::DrawViewPart`, `TechDraw::DrawProjGroup`, `TechDraw::DrawProjGroupItem`, `TechDraw::DrawViewDimension`
4. Count projection views (DrawViewPart + DrawProjGroupItem)
5. Count dimension annotations (DrawViewDimension)
6. Copy `/home/ga/Documents/FreeCAD/bracket_drawing.pdf` and check file size

## Edge Cases

- Agent may use DrawProjGroup (projection group) instead of individual DrawViewPart — both contain the same views and are counted via DrawProjGroupItem
- Dimension count varies by how detailed the agent is — partial credit awarded for ≥3 dimensions
- Agent might export SVG instead of PDF — only PDF is checked; if PDF missing, that criterion fails
- Agent might save to a different filename — only the exact required paths are checked

## Schema Reference

**FCStd TechDraw object types:**
- `TechDraw::DrawPage` — the drawing page/canvas
- `TechDraw::DrawSVGTemplate` — page template (A3/A4/etc.)
- `TechDraw::DrawViewPart` — a single projection view
- `TechDraw::DrawProjGroup` — a group of linked projection views
- `TechDraw::DrawProjGroupItem` — individual view within a projection group
- `TechDraw::DrawViewDimension` — a dimension annotation
- `TechDraw::DrawViewSection` — a cross-section view
