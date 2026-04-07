# turbo_vgt_actuator_root_cause

## Overview

**Difficulty**: very_hard
**Environment**: multiecuscan_env (Windows 11, Multiecuscan simulation mode)
**Occupation**: Senior Diesel Technician at Authorised Fiat Dealership
**Vehicle**: Fiat Punto 1.3 Multijet Diesel (169A1.000, 75HP, 2012)
**Systems**: Engine ECU (multi-parameter turbo correlation)

## Scenario

A Fiat Punto has intermittent power loss under hard acceleration with limp-home activation. The vehicle has a variable geometry turbocharger (VGT). The technician must systematically correlate DTCs with multiple live parameters (boost pressure, MAF, EGR, actuator duty cycle) to identify the root cause from five possible candidates: VGT actuator solenoid, VGT geometry fouling, boost sensor fault, EGR contribution, or intercooler leak.

## Task Complexity

This task is **very_hard** because the agent must:
1. Navigate Multiecuscan to Fiat → Punto → Engine system
2. Read all stored + pending DTCs and identify turbo-related codes in P0045/P0046/P0234/P0236/P0299 range
3. Open live parameter monitoring and simultaneously track ≥4 parameters
4. Interpret the correlation between DTC codes and parameter readings
5. Select the most probable root cause from 5 distinct failure modes
6. Write a structured root cause analysis (RCA) with evidence-based reasoning
7. Include repair recommendations with labour time estimate

No UI navigation steps are provided — the agent must discover the workflow independently.

## Scoring (100 points total, pass threshold: 65)

| Criterion | Points |
|---|---|
| Vehicle/ECU identification | 10 |
| DTC section present | 10 |
| Boost pressure parameter monitored | 15 |
| MAF (mass air flow) parameter monitored | 10 |
| EGR system mentioned | 10 |
| ≥4 live parameters documented | 10 |
| Root cause analysis section | 15 |
| Specific root cause identified | 10 |
| Repair recommendations | 10 |
| **Total** | **100** |

## Feature Coverage

- **Vehicle**: Fiat Punto 1.3 Multijet Diesel (2012)
- **Systems**: Engine ECU only (deep turbo parameter analysis)
- **Key features**: VGT turbocharger, boost pressure, MAF, EGR, actuator duty
- **Output**: Root cause analysis report with evidence and repair actions
- **Occupation domain**: Authorised dealer senior technician

## Anti-Gaming

Report `mtime > start_timestamp` gate prevents pre-existing reports from scoring.

## Do-Nothing Scores

| Scenario | Score | Passed |
|---|---|---|
| Export script never ran | 0 | False |
| Report missing | 0 | False |
| Report exists but predates task start | 0 | False |
| Report with ECU info + DTC + 1-2 params | 20–40 | False |
| Complete RCA with boost, MAF, EGR, root cause | 65–100 | True |
