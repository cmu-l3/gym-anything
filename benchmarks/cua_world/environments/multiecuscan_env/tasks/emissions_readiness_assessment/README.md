# emissions_readiness_assessment

## Overview

**Difficulty**: very_hard
**Environment**: multiecuscan_env (Windows 11, Multiecuscan simulation mode)
**Occupation**: Automotive Mechanic at Independent MOT Testing Station (UK)
**Vehicle**: Alfa Romeo MiTo 1.4 TB (petrol, 2010, 955A8.000 engine)
**Systems**: Engine ECU (OBD-II readiness monitors, emissions)

## Scenario

A customer's Alfa Romeo MiTo needs a pre-MOT check. The battery was recently replaced, resetting all OBD-II readiness monitors. The engine management light came on briefly and then cleared. The mechanic must determine if the vehicle will pass the UK MOT emissions test by reading all readiness monitors and any DTCs, then produce a formal pre-MOT report.

## Task Complexity

This task is **very_hard** because the agent must:
1. Navigate Multiecuscan to select Alfa Romeo → MiTo → Engine system
2. Connect in simulation mode and read ECU identification data
3. Read the complete OBD-II readiness monitor status (7–10 monitors)
4. Scan for stored and pending DTCs and cross-reference with the DTC database
5. Interpret the monitor status against UK MOT rules (max 1 incomplete monitor allowed; catalyst must be complete)
6. Write a structured formal report with: vehicle ID, monitor table, DTCs, verdict, and drive cycle guidance
7. Work order is discovered on the Desktop — agent must read it to get vehicle details

There are no UI step instructions in the task description. The agent must independently navigate the software and interpret real diagnostic data.

## Scoring (100 points total, pass threshold: 65)

| Criterion | Points |
|---|---|
| Vehicle/ECU identification section | 10 |
| Readiness monitor table (≥3 monitors) | 20 |
| Catalyst monitor explicitly addressed | 10 |
| DTC section present | 15 |
| MOT verdict (READY/NOT READY/CONDITIONAL) | 15 |
| Drive cycle guidance for incomplete monitors | 15 |
| EVAP monitor mentioned | 5 |
| O2/lambda sensor monitor mentioned | 5 |
| MOT regulatory reference | 5 |
| **Total** | **100** |

## Files

- `task.json` — Task specification
- `setup_task.ps1` — Drops work order on Desktop, launches Multiecuscan
- `export_result.ps1` — Reads report, extracts signals, writes result JSON
- `verifier.py` — Real verifier with partial credit and anti-gaming gate
- `README.md` — This file

## Feature Coverage

- **Vehicle**: Alfa Romeo MiTo 1.4 TB (petrol)
- **System**: Engine ECU only (OBD-II focus)
- **Key features**: Readiness monitors, DTC scan, emissions compliance
- **Output**: Formal pre-MOT report with verdict and drive cycle guidance
- **Regulatory domain**: UK MOT emissions testing rules

## Anti-Gaming

The verifier checks `report_file_mtime > start_timestamp` to ensure the report was created during the task, not pre-existing.

## Do-Nothing Scores

| Scenario | Score | Passed |
|---|---|---|
| Export script never ran | 0 | False |
| Report missing | 0 | False |
| Report exists but predates task start | 0 | False |
| Report with only partial content | 15–45 | False |
| Complete report with verdict and drive cycle | 65–100 | True |
