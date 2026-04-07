# Task: cost_schedule_from_takeoff

## Domain Context

**Occupation:** Quantity Surveyor
**Industry:** Architecture / Engineering / Construction (AEC)

Quantity surveyors use BIM authoring tools to extract model-based take-offs and produce
pre-tender cost estimates directly embedded in the IFC project file. Bonsai (BlenderBIM)
includes a cost management module that allows QS professionals to create formal
`IfcCostSchedule` entities, populate them with `IfcCostItem` line items, and attach
`IfcCostValue` unit rates — all stored in the IFC schema alongside the geometry.

The **FZK-Haus** (`fzk_haus.ifc`) is a publicly available two-storey residential test
model from the Forschungszentrum Karlsruhe (KIT), used extensively in IFC interoperability
research. It contains 13 walls, 5 doors, 11 windows, and 4 slabs.

---

## Goal (End State)

The output IFC file `/home/ga/BIMProjects/fzk_cost_schedule.ifc` must exist and contain:

- **At least 1 `IfcCostSchedule`** entity embedded in the model
- **At least 4 `IfcCostItem`** entities (one per major element category)
- **At least 4 `IfcCostValue`** entities representing the unit rates from the project documentation

The file must have been saved during the current task session (modification time after task start).

---

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Output IFC file saved during task | 20 | binary gate |
| ≥ 1 `IfcCostSchedule` present | 25 | — |
| ≥ 4 `IfcCostItem` entities | 35 | partial: 2–3 items = 15 pts, 1 item = 5 pts |
| ≥ 4 `IfcCostValue` entities | 20 | partial: 2–3 values = 8 pts |
| **Pass threshold** | **65/100** | — |

If the output file does not exist at all, score = 0 immediately.

---

## Verification Strategy

The export script runs `blender --background` with the bundled `ifcopenshell` to parse the
saved IFC. It queries:

- `ifc.by_type("IfcCostSchedule")` → count
- `ifc.by_type("IfcCostItem")` → count
- `ifc.by_type("IfcCostValue")` → count
- `ifc.by_type("IfcElementQuantity")` → count (informational)
- `os.path.getmtime()` vs task start timestamp

Results are written to `/tmp/cost_schedule_result.json` and passed to `verifier.py`.

---

## IFC Schema Reference

| IFC Entity | Role |
|---|---|
| `IfcCostSchedule` | The schedule container (name, status) |
| `IfcCostItem` | A line item within the schedule (element category) |
| `IfcCostValue` | A monetary value/rate attached to a cost item |
| `IfcRelNests` | Associates cost items to the schedule and sub-items |
| `IfcElementQuantity` | Stores quantity take-off data per element |

---

## Edge Cases and Potential Issues

- **Bonsai cost module location**: The cost management panel is not in the default Blender
  Properties panel — agents need to locate it within Bonsai's custom UI panels.
- **IFC save vs Blender save**: Saving as a `.blend` file does NOT create the IFC output;
  the agent must use Bonsai's "Save IFC Project" action to write the `.ifc` file.
- **Schedule name**: The spec document specifies the exact schedule name "Pre-Tender Estimate"
  and status "DRAFT" — but verification does not check the name, only the presence of the entity.
- **Unit rates**: The spec provides GBP unit rates per category; the verifier checks for
  `IfcCostValue` presence, not specific values, so approximate entry is acceptable.
- **Anti-pattern 4**: Maximum partial score = 23 pts (items=15, values=8). Pass threshold = 65.
  A partially-completing agent cannot pass.
