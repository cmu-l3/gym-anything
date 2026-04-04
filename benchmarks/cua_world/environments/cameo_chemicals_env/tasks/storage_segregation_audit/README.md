# Task: storage_segregation_audit

## Domain
Occupational Health and Safety — Chemical Storage Compliance

## Overview
An Occupational Health and Safety Specialist must perform a comprehensive storage segregation audit of a chemical facility. The facility stores 15 different chemicals across 4 buildings. Using CAMEO Chemicals, the agent must identify ALL incompatible co-storage pairs within the inventory and produce a written audit report with specific findings and recommendations.

The task intentionally omits chemical-pair information from the task description — the agent must discover dangerous combinations by researching each chemical's reactivity in CAMEO Chemicals. This mirrors real OHS compliance audits where the specialist does not know in advance which pairs are dangerous.

## Starting State
- Firefox is open at CAMEO Chemicals homepage (https://cameochemicals.noaa.gov/)
- `~/Desktop/facility_chemical_inventory.csv` contains the 15-chemical inventory with names, CAS numbers, UN numbers, quantities, and storage locations
- No output file exists at task start (anti-gaming confirmed)

## Goal / End State
Produce a written audit report at:
```
~/Documents/storage_audit_report.txt
```

The report must:
1. Identify **all dangerous co-storage pairs** in the facility inventory
2. Specifically flag **Sulfuric Acid + Sodium Cyanide** (HCN gas generation — Buildings A and B)
3. Specifically flag **Hydrogen Peroxide + Acetone** (explosive peroxides — Building C)
4. Identify at least 2 additional dangerous pairs from the inventory (e.g., Chlorine gas + Ammonia, Nitric Acid + organic solvents, Sodium Azide instability)
5. Include concrete storage/segregation recommendations

## Difficulty: very_hard

This task is very hard because:
- 15 chemicals × 14 pairs = up to 105 potential combinations to evaluate
- Agent must use CAMEO Chemicals Reactivity tool to check incompatibilities — not guessable by common knowledge alone
- Agent must cross-reference storage locations from the CSV (co-located chemicals in same building present actual risk)
- No specific pairs are named in the task description — agent must discover all of them
- Writing a substantive report requires synthesizing findings from multiple CAMEO lookups

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File gate | 0/100 | If no output file → score=0 immediately |
| Substantive report | 15 | File ≥ 1000 chars AND ≥ 20 lines |
| H2SO4 + NaCN pair | 30 | Both chemicals mentioned in report |
| H2O2 + Acetone pair | 25 | Both mentioned |
| Recommendations | 15 | Keywords: recommend/segregate/separate/incompatible |
| 2+ additional pairs | 15 | Cl2+NH3, nitric+organic, azide, etc. |

Pass threshold: 60/100

## Key Chemicals in Inventory (from facility_chemical_inventory.csv)

| Building | Chemical | Key Hazard Pair |
|----------|----------|-----------------|
| A | Sulfuric Acid (98%) | Reacts violently with NaCN → HCN |
| A | Sodium Cyanide | Reacts with acids → HCN gas |
| B | Hydrogen Peroxide (30%) | Forms explosive peroxides with Acetone |
| C | Acetone | Explosive peroxides with H2O2 |
| D | Chlorine Gas | Toxic gas with Ammonia |
| D | Anhydrous Ammonia | Toxic cloud with Cl2 |
| B | Nitric Acid | Strong oxidizer — reacts with organics |
| A | Sodium Azide | Shock-sensitive, forms explosive azides with metals |

## Reference
CAMEO Chemicals Reactivity tool: https://cameochemicals.noaa.gov/react/
