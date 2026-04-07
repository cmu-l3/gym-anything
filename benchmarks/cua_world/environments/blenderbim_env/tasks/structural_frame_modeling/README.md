# Task: structural_frame_modeling

## Domain Context

**Occupation:** Structural Engineer / Structural BIM Coordinator
**Industry:** Civil & Structural Engineering

Structural BIM coordinators create IFC structural models as part of multi-discipline
coordination packages. A key deliverable is a **structural framing model** that captures
the primary load-bearing elements (columns, beams, slabs) with correct IFC types and
material assignments, enabling downstream clash detection, quantity take-off, and FM use.

This task simulates creating a structural framing model for the **Hartwell Community Centre**
from a structural engineer's brief. The model is built from scratch in Bonsai (BlenderBIM)
using the correct IFC structural element types and a named concrete material.

---

## Goal (End State)

The output IFC file `/home/ga/BIMProjects/structural_frame.ifc` must exist and contain:

- **At least 4 `IfcColumn`** entities arranged in a grid pattern
- **At least 4 `IfcBeam`** entities connecting the columns
- **At least 1 `IfcSlab`** entity (ground floor slab)
- A **material named with "Concrete" or "Reinforced"** defined in the project, with at
  least one material association (`IfcRelAssociatesMaterial`) linking it to a structural element
- A valid IFC spatial hierarchy (`IfcProject → IfcSite → IfcBuilding → IfcBuildingStorey`)

The file must have been saved during the current task session.

---

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Output IFC file saved during task | 15 | binary gate |
| ≥ 4 `IfcColumn` entities | 25 | partial: ≥2 = 12 pts, 1 = 5 pts |
| ≥ 4 `IfcBeam` entities | 20 | partial: ≥2 = 10 pts, 1 = 4 pts |
| ≥ 1 `IfcSlab` entity | 15 | binary |
| Concrete material defined AND assigned | 25 | partial: defined but not assigned = 12 pts; assigned but wrong name = 8 pts |
| **Pass threshold** | **65/100** | — |

If the output file does not exist at all, score = 0 immediately.

---

## Verification Strategy

The export script runs `blender --background` with `ifcopenshell` to parse the saved IFC:

- `ifc.by_type("IfcColumn")` → count
- `ifc.by_type("IfcBeam")` → count
- `ifc.by_type("IfcSlab")` → count
- `ifc.by_type("IfcMaterial")` → names; check for "concrete" or "reinforced" (case-insensitive)
- `ifc.by_type("IfcRelAssociatesMaterial")` → find associations where the related material
  name contains "concrete" or "reinforced" and the related objects include structural elements

Results are written to `/tmp/structural_frame_result.json`.

Material check logic:
```python
concrete_present = any(
    "concrete" in m.lower() or "reinforced" in m.lower()
    for m in material_names
)
```

---

## IFC Schema Reference

| IFC Entity | Role |
|---|---|
| `IfcColumn` | Vertical load-bearing member |
| `IfcBeam` | Horizontal spanning structural member |
| `IfcSlab` | Flat plate element (floor/roof) |
| `IfcMaterial` | Named material definition |
| `IfcRelAssociatesMaterial` | Links a material to one or more building elements |
| `IfcBuildingStorey` | Spatial container; all structural elements must be contained here |

---

## Edge Cases and Potential Issues

- **IFC types vs Blender object types**: In Bonsai, geometry is modelled as Blender mesh
  objects and then assigned an IFC class. The agent must explicitly set `IfcColumn`,
  `IfcBeam`, `IfcSlab` — not leave them as `IfcBuildingElementProxy` or `IfcWall`.
- **Material assignment in IFC**: Creating a Blender material is not sufficient — the
  material must be assigned via Bonsai's material assignment tool to create the
  `IfcRelAssociatesMaterial` relationship. The verifier checks for this IFC relationship.
- **Spatial containment**: All structural elements should be contained in the Ground Floor
  storey. The verifier does not strictly enforce containment but counts all IFC instances.
- **Column grid**: The brief requires a 2×2 or larger grid. Minimum 4 columns is enforced.
- **IFC save**: Must use Bonsai's "Save IFC Project" functionality.
- **Anti-pattern 4**: Maximum partial score = 34 pts (columns=12, beams=10, concrete_only=12).
  Pass threshold = 65.
