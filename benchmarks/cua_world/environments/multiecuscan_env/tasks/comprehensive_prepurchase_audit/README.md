# comprehensive_prepurchase_audit

## Overview

**Difficulty**: very_hard
**Environment**: multiecuscan_env (Windows 11, Multiecuscan simulation mode)
**Occupation**: Certified Vehicle Inspector (Independent Inspection Company)
**Vehicle**: Fiat Ducato 2.3 Multijet II 130HP L3H2 (F1AE3481D, Euro 6, 2016)
**Systems**: ALL 5 — Engine, Transmission, ABS, Body Computer, Airbag/SRS

## Scenario

A courier company wants to buy a high-mileage (187,420 miles) Fiat Ducato van. The inspector must scan all 5 major electronic systems, classify every DTC by severity (CRITICAL/MAJOR/MINOR/CLEARED), compute an overall risk score, and produce a formal pre-purchase inspection certificate with a buy/no-buy recommendation. The Ducato has 5 unique issues flagged: idle roughness, notchy gearbox, and a transient dashboard warning light.

## Task Complexity

This is the hardest task in the set. The agent must:
1. Navigate Multiecuscan to Fiat → Ducato → 5 different ECU modules in sequence
2. For each system: read ECU identification, read all DTCs, monitor relevant parameters
3. Classify every fault as CRITICAL/MAJOR/MINOR/CLEARED
4. Compute a composite risk score
5. Write a professional inspection certificate with cover page, 5 system sections, risk score, and verdict
6. 80-step budget and 900-second timeout (the highest of all tasks)

This task tests the agent's ability to perform a structured multi-system audit — the most demanding multi-module navigation scenario in the benchmark.

## Scoring (100 points total, pass threshold: 65)

| Criterion | Points |
|---|---|
| Vehicle identified | 5 |
| Engine ECU section | 15 |
| Transmission section | 10 |
| ABS/Braking section | 10 |
| Body Computer section | 10 |
| Airbag/SRS section | 10 |
| All 5 systems covered (bonus) | 5 |
| DTC classification (CRITICAL/MAJOR/MINOR) | 15 |
| Risk score (0-100) | 10 |
| Final verdict | 10 |
| **Maximum** | **100** |

## Feature Coverage

- **Vehicle**: Fiat Ducato 2.3 Multijet II (2016), 187K miles
- **Systems**: All 5 ECU types (broadest coverage in the task set)
- **Key features**: Multi-system inspection, DTC classification, risk scoring
- **Output**: Formal pre-purchase inspection certificate
- **Occupation domain**: Commercial vehicle inspection for fleet purchase

## Anti-Gaming

Report `mtime > start_timestamp` gate.

## Do-Nothing Scores

| Scenario | Score | Passed |
|---|---|---|
| Export never ran | 0 | False |
| Engine ECU only | 20–25 | False |
| 3 systems + basic DTCs | 40–50 | False |
| 5 systems + classification + verdict | 65–100 | True |
