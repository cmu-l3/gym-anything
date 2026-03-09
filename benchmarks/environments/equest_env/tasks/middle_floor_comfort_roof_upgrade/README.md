# middle_floor_comfort_roof_upgrade

**Occupation**: Energy Auditor
**Difficulty**: Very Hard
**Building Model**: 4StoreyBuilding (4-storey commercial office)
**Timeout**: 900 s | **Max Steps**: 70

## Task Overview

Implement two approved Energy Conservation Measures (ECMs) in the 4StoreyBuilding annual energy simulation:

**ECM 1 — Middle Floor Thermostat Reset**
Occupancy analysis shows Middle Floor (M.*) spaces have lower internal heat gain density. Implement a thermostat reset for all 5 conditioned M.* zones to reduce unnecessary mechanical cooling and heating:

| Parameter | Old Value | New Value |
|-----------|-----------|-----------|
| `DESIGN-COOL-T` | 75°F | **76°F** |
| `DESIGN-HEAT-T` | 72°F | **71°F** |

**ECM 2 — High-Reflectance Cool Roof**
The building roof is due for replacement. Model a white TPO/EPDM membrane (Solar Reflectance ≥ 0.65):

| Parameter | Old Value | New Value |
|-----------|-----------|-----------|
| Roof Construction `ABSORPTANCE` | 0.6 | **0.35** |

Middle Floor zones: South Perim Zn (M.S21), East Perim Zn (M.E22), North Perim Zn (M.N23), West Perim Zn (M.W24), Core Zn (M.C25).

After both ECMs, run the full annual DOE-2.2 simulation and save the project.

## What Makes This Hard

- No UI navigation instructions — agent must independently find M.* zones in the Building Shell tree and Roof Construction in the Constructions editor
- Two unrelated eQUEST subsystems: Zone setpoints (Building Shell → Zones) vs. Construction properties (Building Shell → Constructions)
- 5 zones × 2 parameters + 1 construction parameter = 11 individual edits
- Both ECMs are required for full credit; partial completion is scored proportionally

## Verification

`export_result.ps1` (post_task hook) reads:
- `C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp`
- Extracts Roof ABSORPTANCE and DESIGN-COOL-T/DESIGN-HEAT-T for all M.* zones

`verifier.py` scores (100 pts total):
| Criterion | Points |
|-----------|--------|
| Simulation ran during session | 10 |
| Roof ABSORPTANCE = 0.35 ± 0.005 | 25 |
| DESIGN-COOL-T = 76 ± 0.5 per M.* zone (× 5) | 7 × 5 = 35 |
| DESIGN-HEAT-T = 71 ± 0.5 per M.* zone (× 5) | 6 × 5 = 30 |
| **Total** | **100** |

**Pass**: score ≥ 60 **AND** simulation ran during the task session.

## Anti-Gaming

- Setup records baseline Roof ABSORPTANCE and M.S21 DESIGN-COOL-T from source `.inp`
- `.SIM` file must be created/modified after task start timestamp
- Without simulation, maximum achievable score is 90 (cool roof + all zone setpoints)
