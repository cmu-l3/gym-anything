# lshape_bb_floor_setpoint_rebalancing

**Occupation**: Building Commissioning Engineer
**Difficulty**: Very Hard
**Building Model**: L_Shape (multi-storey commercial office with BB/UB/G/M/T floors)
**Timeout**: 900 s | **Max Steps**: 75

## Task Overview

Perform a thermal comfort commissioning intervention on the **Basement (BB.*)** floor of the L_Shape building. Occupants report persistent overcooling in summer and underheating in winter. Address both complaints plus fan energy via three parameter changes:

| Parameter | Old Value | New Value | Affected Elements |
|-----------|-----------|-----------|-------------------|
| `DESIGN-COOL-T` | 75°F | **77°F** | All 5 BB conditioned zones |
| `DESIGN-HEAT-T` | 72°F | **70°F** | All 5 BB conditioned zones |
| `SUPPLY-STATIC` | 1.25 in. w.g. | **1.1 in. w.g.** | All 5 BB PSZ systems |

BB conditioned zones: South Perim Zn (BB.S1), NE Perim Zn (BB.NE2), NE Perim Zn (BB.NE3), West Perim Zn (BB.W4), Core Zn (BB.C5).

BB PSZ systems: Sys1 (PSZ) (BB.C1) through (BB.C5).

After all changes, run the full annual simulation and save the project.

## What Makes This Hard

- No UI navigation instructions — agent must find BB floor in the eQUEST zone tree
- Three parameters across two different editors (Zone setpoints vs. HVAC system static pressure)
- The L_Shape model has 5 floors (BB/UB/G/M/T) with many zones — identifying only BB zones requires careful navigation
- 5 zones × 2 setpoints + 5 systems × 1 static pressure = 15 individual edits

## Verification

`export_result.ps1` (post_task hook) reads:
- `C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape\L_Shape.inp`
- Extracts zone setpoints and system static pressure for all BB floor entities

`verifier.py` scores (100 pts total):
| Criterion | Points |
|-----------|--------|
| Simulation ran during session | 10 |
| DESIGN-COOL-T = 77 ± 0.5 per BB zone (× 5) | 8 × 5 = 40 |
| DESIGN-HEAT-T = 70 ± 0.5 per BB zone (× 5) | 8 × 5 = 40 |
| SUPPLY-STATIC = 1.1 ± 0.02 per BB system (× 5) | 2 × 5 = 10 |
| **Total** | **100** |

**Pass**: score ≥ 60 **AND** simulation ran during the task session.

## Anti-Gaming

- Setup records baseline DESIGN-COOL-T for BB.S1 zone from source `.inp`
- `.SIM` file must be created/modified after task start timestamp
- Verifier independently checks each named zone and system — no aggregate shortcuts
