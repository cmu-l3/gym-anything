# Task: multi_storey_office_authoring

## Domain Context

**Occupation:** BIM Technician
**Industry:** Architecture

BIM technicians author building models from scratch using IFC authoring tools. A key
deliverable in early design stages is establishing the correct **spatial hierarchy** —
`IfcProject → IfcSite → IfcBuilding → IfcBuildingStorey` — and populating each storey
with the building envelope elements. Bonsai (BlenderBIM) is a professional IFC authoring
tool used by BIM technicians to create, edit, and export IFC4 models.

This task simulates a real BIM commission: create a new multi-storey office building model
to specification, including correct storey elevations and perimeter walls on each floor.

---

## Goal (End State)

The output IFC file `/home/ga/BIMProjects/meridian_office.ifc` must exist and contain:

- An `IfcProject` whose name contains "Meridian"
- **At least 3 `IfcBuildingStorey`** entities (Ground Floor, First Floor, Second Floor)
- Upper floor storeys at non-zero elevations (~3.5 m and ~7.0 m)
- **At least 12 `IfcWall`** entities across all storeys (4 perimeter walls per storey minimum)

The file must have been saved during the current task session.

---

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Output IFC file saved during task | 15 | binary gate |
| Project name contains "Meridian" | 15 | — |
| ≥ 3 `IfcBuildingStorey` entities | 25 | partial: 2 = 10 pts, 1 = 4 pts |
| Both upper floors at non-zero elevations | 20 | partial: 1 upper floor = 10 pts |
| ≥ 12 `IfcWall` entities | 25 | partial: ≥8 = 18 pts, ≥4 = 10 pts, ≥1 = 4 pts |
| **Pass threshold** | **65/100** | — |

If the output file does not exist at all, score = 0 immediately.

---

## Verification Strategy

The export script runs `blender --background` with `ifcopenshell` to parse the saved IFC.
It queries:

- `ifc.by_type("IfcProject")[0].Name` → project name
- `ifc.by_type("IfcBuildingStorey")` → count and `Elevation` values
- `ifc.by_type("IfcWall")` → count
- Unit conversion: if max elevation > 100, divide by 1000 (mm → m)
- `os.path.getmtime()` vs task start timestamp

Results are written to `/tmp/office_authoring_result.json` and passed to `verifier.py`.

Upper floor detection: `has_upper_floor = any(e > 1.0 for e in elevations_m)`,
`has_second_floor = any(e > 5.0 for e in elevations_m)`.

---

## IFC Schema Reference

| IFC Entity | Role |
|---|---|
| `IfcProject` | Root container; must carry the project name |
| `IfcSite` | Geographic location container |
| `IfcBuilding` | Building aggregation |
| `IfcBuildingStorey` | Floor level; carries `Elevation` attribute |
| `IfcWall` | Standard wall element |
| `IfcRelAggregates` | Spatial decomposition linking storeys to building |
| `IfcRelContainedInSpatialStructure` | Links walls to their storey |

---

## Edge Cases and Potential Issues

- **Project units**: Bonsai may default to metres or millimetres depending on project setup.
  The brief specifies elevations in mm (0, 3500, 7000). The verifier handles both by
  checking if the maximum elevation exceeds 100 and converting accordingly.
- **IFC save vs Blender save**: Must use Bonsai's "Save IFC Project" — not Blender's Save.
- **Spatial containment**: Walls must be contained within a storey using
  `IfcRelContainedInSpatialStructure`. Walls placed in the scene but not assigned to a
  storey may not be counted correctly in some verifiers, but the current verifier counts
  all `IfcWall` instances globally.
- **Project name**: The spec requires exactly "Meridian Office Tower" but the verifier
  checks for case-insensitive substring "meridian" — minor name variations pass.
- **Anti-pattern 4**: Maximum partial score = 38 pts. Pass threshold = 65.
