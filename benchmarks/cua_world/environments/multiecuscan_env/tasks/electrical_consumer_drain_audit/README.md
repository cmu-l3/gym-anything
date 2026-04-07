# electrical_consumer_drain_audit

## Overview

**Difficulty**: very_hard
**Environment**: multiecuscan_env (Windows 11, Multiecuscan simulation mode)
**Occupation**: Freelance Auto-Electrician (parasitic drain specialist)
**Vehicle**: Fiat 500L 1.4 16v (199B6.000, 95HP, 2015)
**Systems**: Body Computer (BSI/BCM) + Engine ECU (2-system cross-audit)

## Scenario

A Fiat 500L kills its battery overnight. A new Bosch AGM battery was fitted 6 weeks ago and is already failing. The alternator is confirmed OK (14.2V). The problem is a parasitic drain from an electronic module that stays awake after ignition-off. The auto-electrician must scan BOTH the Body Computer and Engine ECU, identify CAN bus communication faults, note battery voltage readings, rank suspect modules, and recommend a fuse-pull isolation sequence.

## Task Complexity

This task is **very_hard** because the agent must:
1. Navigate to Fiat → 500L → Body Computer module (not just Engine ECU)
2. Switch to a second system (Engine ECU) within the same session
3. Read DTCs from both systems and identify CAN bus anomalies
4. Monitor battery voltage and charging parameters
5. Apply knowledge of automotive electronics: which modules commonly cause parasitic drains
6. Rank suspect modules with reasoning (alarm siren, infotainment, gateway, BSI)
7. Describe a fuse-pull isolation test sequence — practical next steps
8. Write a structured cross-system audit report

This requires multi-system navigation, cross-referencing, and applied electrical diagnostics knowledge.

## Scoring (100 points total, pass threshold: 65)

| Criterion | Points |
|---|---|
| Vehicle identified | 5 |
| Body Computer section present | 20 |
| Engine ECU section present | 15 |
| Both systems covered (bonus) | 5 |
| DTC section present | 10 |
| Battery voltage parameter recorded | 10 |
| CAN bus / network fault addressed | 5 |
| Ranked suspect module list | 15 |
| Next steps / fuse pull test | 15 |
| Specific suspect module named | 5 |
| **Maximum** | **105 → capped at 100** |

## Feature Coverage

- **Vehicle**: Fiat 500L 1.4 petrol (2015)
- **Systems**: Body Computer (BSI) + Engine ECU (2-system task)
- **Key features**: CAN bus faults, battery drain, parasitic current, module sleep
- **Output**: Cross-system drain audit report with suspect ranking
- **Occupation domain**: Freelance auto-electrician

## Anti-Gaming

Report `mtime > start_timestamp` gate prevents pre-existing reports from scoring.

## Do-Nothing Scores

| Scenario | Score | Passed |
|---|---|---|
| Export never ran | 0 | False |
| Report missing | 0 | False |
| Engine ECU only, no BCM | 30–40 | False |
| Both systems + DTCs only | 50–55 | False |
| Full audit with suspects + fuse test | 65–100 | True |
