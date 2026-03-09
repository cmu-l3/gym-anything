# Task: chemical_incident_root_cause

## Domain
Occupational Health and Safety — Chemical Incident Investigation

## Overview
An OHS Specialist investigates a reactor explosion at a specialty chemicals plant. Maintenance workers used an improvised cleaning procedure, applying 68% Nitric Acid to a reactor vessel that still contained Toluene residues. Two alternative cleaning agents (35% H2O2 and KMnO4) were considered but not used. The agent must determine the chemical mechanism of the explosion, evaluate whether the alternative agents would have been safer, identify the root cause from multiple proposed explanations in the incident report, and produce a comprehensive investigation report.

## Starting State
- Firefox is open at the CAMEO Chemicals Reactivity tool (https://cameochemicals.noaa.gov/react/)
- `~/Desktop/post_incident_investigation.txt` contains the full incident report including proposed explanations, witness statements, and the two alternative cleaning agents
- No output file exists at task start

## Goal / End State
Produce a root cause investigation report at:
```
~/Documents/incident_root_cause_report.txt
```

The report must:
1. Identify the explosion mechanism: Toluene residues + concentrated Nitric Acid → nitration reaction → explosive nitrotoluene compounds
2. Correctly evaluate H2O2 as ALSO incompatible with toluene residues (oxidizer + organic = hazard)
3. Correctly evaluate KMnO4 as ALSO incompatible with organic residues
4. State the correct root cause (improvised use of oxidizing cleaning agent on vessel with organic residues)
5. Recommend preventive measures (purge/degas reactor; use inert solvents first; oxidizer compatibility check before cleaning)

## Key Chemistry (NOT revealed to agent)

| Reaction | Outcome |
|----------|---------|
| Toluene + conc. HNO3 | Nitration: forms mono/di/trinitrotoluene (explosive); highly exothermic |
| Toluene + H2O2 (35%) | Organic + peroxide = oxidation hazard; also incompatible |
| Toluene + KMnO4 | Strong oxidizer + organic = fire/explosion risk |

The incident report lists 4 proposed root causes (mislabeled drum, electrical fault, equipment corrosion, chemical incompatibility). Only the chemical incompatibility explanation is correct — but the agent must verify this using CAMEO Chemicals, not just guess.

## Difficulty: very_hard

- The nitration mechanism (toluene + HNO3 → explosive compounds) is not common knowledge in OHS
- Must check 3 separate reactivity pairs using CAMEO Reactivity tool
- Must evaluate the alternative agents and find that both are ALSO incompatible — a counter-intuitive finding that requires actual CAMEO lookup
- Must select the correct root cause from 4 proposed explanations, each described plausibly in the incident report
- Requires integrating chemistry findings into a structured investigation report

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File gate | 0/100 | If no output file → score=0 |
| Root cause: nitration (Toluene + HNO3) | 35 | All 3 elements: toluene + nitric acid + nitration/explosive |
| Both alt agents also incompatible | 25 | H2O2 AND KMnO4 flagged as hazardous with organics |
| Preventive measures | 20 | Purge/degas/inert solvents/compatibility check |
| Report structure & substance | 20 | ≥800 chars + root cause framing |

Pass threshold: 60/100
