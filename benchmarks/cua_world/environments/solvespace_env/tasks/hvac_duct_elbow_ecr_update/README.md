# hvac_duct_elbow_ecr_update

## Task Overview

**Occupation**: HVAC Systems Engineer
**Industry**: Building Services / Mechanical Engineering
**Difficulty**: very_hard
**Archetype**: ECR parametric update (4 constraint values to update per Engineering Change Request)

An Engineering Change Request (ECR-HVAC-2247) has been issued for a duct elbow cross-section due to increased airflow requirements. The current SolveSpace file `duct_elbow_current.slvs` has four parametric constraints reflecting the old design. The ECR document is on the Desktop. The agent must:

1. Open `duct_elbow_current.slvs`
2. Update all four dimension constraints to the ECR-specified values
3. Save the updated file as `duct_elbow_updated.slvs`
4. Export a DXF to `duct_elbow_updated.dxf`

## Domain Context

HVAC rectangular duct systems are designed for specific airflow volumes per ASHRAE standards. When occupancy or usage changes, the duct cross-section must be resized. ECR-driven parametric updates in CAD tools are a routine part of the building services engineer's workflow — the engineer must apply the new dimensions from the formal ECR document to the parametric model and re-export fabrication drawings.

## Goal / End State

`duct_elbow_updated.slvs` must exist, be newer than task start, and contain four PT_PT_DISTANCE constraints matching the ECR values. A DXF export must also exist.

For `very_hard`: Description names the ECR document but does NOT state which constraints to change or what the new values are — the agent must read the ECR to determine both.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| `duct_elbow_updated.slvs` saved and new | 15 | Hard gate: score=0 if missing or not new |
| total_width = 300 mm | 15 | ±0.5 mm; old=250 rejected |
| total_height = 240 mm | 15 | ±0.5 mm; old=200 rejected |
| leg_height = 130 mm | 15 | ±0.5 mm; old=100 rejected |
| wall_thickness = 70 mm | 15 | ±0.5 mm; old=50 rejected |
| DXF exported and new | 25 | Gate: capped to 74 if DXF missing |
| **Total** | **100** | Pass threshold: 75 |

## Verification Strategy

- `export_result.sh` parses `duct_elbow_updated.slvs` for type=30 constraints
- `verifier.py` checks new ECR values; also reports specifically when old values still present
- Timestamp gate; DXF gate

## Constraint Changes (ECR-HVAC-2247)

| Dimension | Current (old) | ECR target (new) |
|-----------|--------------|-----------------|
| Total duct width | 250 mm | 300 mm |
| Total duct height | 200 mm | 240 mm |
| Elbow leg height | 100 mm | 130 mm |
| Wall/web thickness | 50 mm | 70 mm |

## Anti-Pattern Checks

- **AP-7** (update-style reset): The starting file has the OLD values seeded. The agent must update them; the file does not start in the correct state. ✓
- **AP-4**: All binary, no partial credit. Max without DXF = 75; gate caps to 74. ✓
- **AP-10**: Setup prints only file size; old dimension values not printed. ✓
