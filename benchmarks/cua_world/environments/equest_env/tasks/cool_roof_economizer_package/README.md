# cool_roof_economizer_package

**Occupation**: Sustainability Specialist
**Difficulty**: Very Hard
**Building Model**: 4StoreyBuilding (4-storey commercial office)
**Timeout**: 900 s | **Max Steps**: 70

## Task Overview

Implement a two-measure Energy Conservation Measure (ECM) package in eQUEST for a commercial office building:

1. **Cool Surface Compliance**: Reduce solar absorptance of both the exterior wall (`EWall Construction`) and the roof (`Roof Construction`) from 0.6 to **0.45**, meeting ENERGY STAR cool-wall and cool-roof criteria.

2. **Enhanced Economizer Control**: Lower the dry-bulb economizer cutoff temperature (`DRYBULB-LIMIT`) on all five Ground Floor (G.*) packaged single-zone HVAC systems from 70°F to **65°F**, enabling more aggressive free cooling.

After applying both measures, run the full annual DOE-2.2 simulation and save the project.

## What Makes This Hard

- No UI navigation instructions are provided — the agent must independently locate `Construction` blocks in the eQUEST Building Shell tree and `Air-Side HVAC` system parameters
- Two independent subsystems must be modified: building envelope (constructions) and mechanical (HVAC economizers)
- Five separate HVAC system entries must each be updated to the same DRYBULB-LIMIT value
- Simulation must be triggered and project saved before export

## Verification

`export_result.ps1` (post_task hook) reads:
- `C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp`
- Recursively scans for `.sim` output files

`verifier.py` scores (100 pts total):
| Criterion | Points |
|-----------|--------|
| Simulation ran during session (.SIM is new) | 15 |
| EWall Construction ABSORPTANCE = 0.45 ± 0.005 | 20 |
| Roof Construction ABSORPTANCE = 0.45 ± 0.005 | 20 |
| Each G.* system DRYBULB-LIMIT = 65 ± 0.5 (× 5) | 9 × 5 = 45 |
| **Total** | **100** |

**Pass**: score ≥ 60 **AND** simulation ran during the task session.

## Anti-Gaming

- Setup records baseline ABSORPTANCE values from the source `.inp` before import
- The `.SIM` file must have been created/modified after the task start timestamp
- Without running simulation, the score is capped at 55 pts maximum
