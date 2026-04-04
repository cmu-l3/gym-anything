# lshape_lighting_power_density_reduction

**Occupation**: LEED BD+C Consultant
**Difficulty**: Very Hard
**Building Model**: L_Shape (multi-storey commercial office)
**Timeout**: 900 s | **Max Steps**: 80

## Task Overview

Perform an ASHRAE 90.1-2019 Energy Cost Budget compliance correction for the L_Shape building's lighting and plug load schedules. Private executive office spaces on multiple floors are modeled with non-compliant values:

| Parameter | Current (Non-compliant) | Target (Compliant) | ASHRAE Basis |
|-----------|------------------------|--------------------|--------------|
| `LIGHTING-W/AREA` | 1.3 W/ft² | **1.05 W/ft²** | ASHRAE 90.1-2019 Space-by-Space: private office 1.07 W/ft² |
| `EQUIPMENT-W/AREA` | 1.5 W/ft² | **1.2 W/ft²** | Client plug-load management target |

These spaces appear on **multiple floors** of the L_Shape model. The agent must find and update **all** non-compliant spaces without being told the count, then run simulation and save.

## What Makes This Hard

- The agent must navigate the eQUEST Space Activity Definition editor to find every space at 1.3 W/ft² across all 5 floors (BB/UB/G/M/T)
- No count of affected spaces is provided — the agent must discover all of them
- Two parameters must be updated per space
- Partial credit is awarded based on the fraction of spaces corrected
- Score is capped unless simulation also runs

## Verification

`export_result.ps1` (post_task hook) reads:
- `C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape\L_Shape.inp`
- Counts LIGHTING-W/AREA=1.3 (remaining), =1.05 (corrected); EQUIPMENT-W/AREA=1.5 (remaining), =1.2 (corrected)

`verifier.py` scores (100 pts total):
| Criterion | Points |
|-----------|--------|
| Simulation ran during session | 15 |
| All LIGHTING-W/AREA=1.3 spaces corrected (none remaining) | 15 bonus |
| Lighting corrected proportionally: 40 × (corrected/baseline) | up to 40 |
| All EQUIPMENT-W/AREA=1.5 spaces corrected | 10 bonus |
| Equipment corrected proportionally: 20 × (corrected/baseline) | up to 20 |
| **Total** | **100** |

**Pass**: score ≥ 60 **AND** simulation ran **AND** at least one space changed to 1.05 W/ft².

## Anti-Gaming

- Setup counts LIGHTING-W/AREA=1.3 occurrences in source `.inp` and stores as baseline
- After task, export checks count of remaining 1.3 spaces (should be 0)
- `.SIM` file timestamp check confirms simulation actually ran
