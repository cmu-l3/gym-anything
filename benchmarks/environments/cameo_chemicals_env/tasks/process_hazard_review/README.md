# Task: process_hazard_review

## Domain
Occupational Health and Safety — Process Hazard Analysis (PHA)

## Overview
An OHS Specialist conducts a Process Hazard Analysis (PHA) for a methyl acrylate synthesis operation. The process uses 5 chemicals: Acrylic Acid, Sulfuric Acid (catalyst), Methanol (reactant), Sodium Hydroxide (neutralizer), and Toluene (solvent/wash). The agent must systematically check all relevant chemical pairs using the CAMEO Chemicals Reactivity tool, identify which combinations pose explosion or violent reaction risks, and identify a specific safety gap described in the process documentation.

## Starting State
- Firefox is open at the CAMEO Chemicals Reactivity tool (https://cameochemicals.noaa.gov/react/)
- `~/Desktop/synthesis_process_description.txt` contains the process description including chemical inventory, process steps, and Building 12 infrastructure details
- No output file exists at task start

## Goal / End State
Produce a PHA report at:
```
~/Documents/process_hazard_report.txt
```

The report must:
1. Use the CAMEO Reactivity tool to check all relevant chemical pairs
2. Identify Acrylic Acid + Sodium Hydroxide as a critical reactive hazard
3. Identify Methanol + Sulfuric Acid as a reactive/exothermic hazard
4. Identify the Building 12 ventilation safety gap (no explosion-proof ventilation for flammable vapors)
5. Cover all 5 process chemicals
6. Provide safeguard recommendations

## Critical Chemical Pairs (NOT revealed to agent)

| Pair | Hazard |
|------|--------|
| Acrylic Acid + Sodium Hydroxide | Violent exothermic neutralization; can trigger uninhibited polymerization of acrylic acid |
| Methanol + Sulfuric Acid | Exothermic; at elevated temperatures can produce dimethyl ether (flammable gas) |
| Acrylic Acid + Sulfuric Acid | Possible polymerization (less severe but relevant) |

**Safety gap**: The process description states Building 12 has standard ventilation but NOT explosion-proof electrical classification — a code violation for a process using Toluene and Methanol (flammable vapors).

## Difficulty: very_hard

- Agent must systematically check all 10 pairs (5-chemical process = C(5,2) = 10 combinations)
- The CAMEO Reactivity tool interface requires selecting reactive groups, not direct name entry
- Key hazard (acrylic acid polymerization triggered by NaOH) is not common knowledge
- Safety gap identification requires reading and cross-referencing the process description
- Must distinguish severe hazards from minor ones and prioritize recommendations

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File gate | 0/100 | If no output file → score=0 |
| Acrylic Acid + NaOH hazard | 30 | Both chemicals + reaction hazard mentioned |
| Methanol + H2SO4 hazard | 20 | Both chemicals + reaction hazard mentioned |
| Building 12 ventilation gap | 20 | Ventilation + explosion-proof + Building 12 mentioned |
| All 5 chemicals covered | 15 | All chemicals present in report |
| Safeguard recommendations | 15 | Recommendations/controls mentioned |

Pass threshold: 60/100
