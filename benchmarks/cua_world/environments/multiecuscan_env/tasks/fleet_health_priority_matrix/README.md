# fleet_health_priority_matrix

## Overview

**Difficulty**: very_hard
**Environment**: multiecuscan_env (Windows 11, Multiecuscan simulation mode)
**Occupation**: Fleet Technician at Logistics Company
**Vehicles**: 3 different vehicles (Punto CNG + Giulietta MultiAir + Ducato diesel)
**Systems**: Engine ECU × 3 vehicles

## Scenario

A logistics fleet manager needs an urgent electronic triage of 3 vehicles before a combined Monday service slot. The fleet technician must scan the Engine ECU of each vehicle in Multiecuscan, compare their DTC counts and fault severities, rank them by urgency (most to least urgent), and recommend pre-service actions so the service team can pre-order parts.

## Task Complexity

This is the most workflow-intensive task in the set. The agent must:
1. Navigate Multiecuscan 3 times (once per vehicle: Punto/Giulietta/Ducato)
2. Read ECU identification and DTCs for each vehicle
3. Record parameters for each
4. Synthesise data from 3 sessions into a comparative table
5. Rank vehicles 1–3 by urgency with data-driven justification
6. Recommend pre-service actions for each vehicle
7. Optionally include downtime/cost impact estimates

The multi-vehicle nature forces repeated navigation and session management in Multiecuscan — the hardest navigation challenge in the task set.

## Scoring (100 points total, pass threshold: 65)

| Criterion | Points |
|---|---|
| Vehicle A section (Punto CNG) | 15 |
| Vehicle B section (Giulietta MultiAir) | 15 |
| Vehicle C section (Ducato diesel) | 15 |
| All 3 vehicles covered (bonus) | 5 |
| ECU identification (any vehicle) | 10 |
| Engine parameters documented | 5 |
| Side-by-side comparison table | 10 |
| Priority ranking (Rank 1/2/3) | 15 |
| Pre-service actions | 10 |
| **Maximum** | **100** |

## Feature Coverage

- **Vehicles**: 3 distinct vehicles across 2 makes, 3 fuel types (CNG, petrol turbo, diesel)
- **Systems**: Engine ECU (consistent system, varying vehicles)
- **Key features**: Multi-vehicle comparison, priority triage, fleet management
- **Output**: Fleet Health Priority Matrix with ranking and pre-service plan
- **Occupation domain**: Commercial fleet technician / logistics

## Anti-Gaming

Report `mtime > start_timestamp` gate prevents pre-existing reports from scoring.

## Do-Nothing Scores

| Scenario | Score | Passed |
|---|---|---|
| Export never ran | 0 | False |
| 1 vehicle only | 20–30 | False |
| 2 vehicles + comparison | 45–55 | False |
| All 3 vehicles + ranking + actions | 65–100 | True |
