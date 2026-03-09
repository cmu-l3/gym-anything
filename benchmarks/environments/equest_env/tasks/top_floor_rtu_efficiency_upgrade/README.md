# top_floor_rtu_efficiency_upgrade

**Occupation**: Mechanical Engineer (HVAC Retrofit)
**Difficulty**: Very Hard
**Building Model**: 4StoreyBuilding (4-storey commercial office)
**Timeout**: 900 s | **Max Steps**: 75

## Task Overview

Update the eQUEST energy model to reflect a capital equipment replacement of all rooftop units (RTUs) on the **Top Floor (T.*)** of a commercial office building. Replace aging standard-efficiency units with high-efficiency alternatives by updating three performance parameters in all five T.* packaged single-zone (PSZ) HVAC systems:

| Parameter | Old Value | New Value | Meaning |
|-----------|-----------|-----------|---------|
| `COOLING-EIR` | 0.34565 | **0.28571** | EER 3.5 — high-efficiency cooling |
| `FURNACE-HIR` | 1.24069 | **1.11111** | 90% AFUE — condensing furnace |
| `SUPPLY-EFF`  | 0.53    | **0.65**    | Premium-efficiency fan motor |

After updating all top-floor systems, run the full annual DOE-2.2 simulation and save the project.

## What Makes This Hard

- No UI navigation instructions are provided — the agent must find the T.* systems in the eQUEST Air-Side HVAC tree independently
- The number of Top Floor systems is not stated (there are 5: T.S31, T.E32, T.N33, T.W34, T.C35)
- Three separate parameters must be changed per system — 15 individual edits total
- Partial credit is awarded per system and per parameter, but full pass requires ≥ 3 systems with COOLING-EIR corrected

## Verification

`export_result.ps1` (post_task hook) reads:
- `C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp`
- Extracts COOLING-EIR, FURNACE-HIR, SUPPLY-EFF for each of the 5 T.* systems

`verifier.py` scores (100 pts total):
| Criterion | Points |
|-----------|--------|
| Simulation ran during session | 10 |
| COOLING-EIR ≈ 0.28571 per T.* system (× 5) | 8 × 5 = 40 |
| FURNACE-HIR ≈ 1.11111 per T.* system (× 5) | 6 × 5 = 30 |
| SUPPLY-EFF ≈ 0.65 per T.* system (× 5)     | 4 × 5 = 20 |
| **Total** | **100** |

**Pass**: score ≥ 60 **AND** simulation ran **AND** COOLING-EIR corrected on ≥ 3 systems.

## Anti-Gaming

- Setup records baseline COOLING-EIR from the source `.inp`
- `.SIM` file must be created/modified after task start timestamp
- Per-system scoring means partial completion is rewarded proportionally
