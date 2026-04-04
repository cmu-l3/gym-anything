# gap_compliance_audit_records

## Overview

**Role**: Farm and Home Management Educators (USDA Cooperative Extension / GAP Consultant)
**Difficulty**: Very Hard
**Environment**: farmOS Field Kit (Android app, offline mode)

A farm consultant preparing a vegetable operation for a USDA GAP certification audit must create 5 compliance documentation logs in farmOS Field Kit. These records are required by the FSMA Produce Safety Rule (21 CFR Part 112) and USDA GAP/GHP audit standards. The consultant must create logs covering worker hygiene, water testing, sanitation, wildlife risk assessment, and records management — all required audit documentation categories.

## Why This Is Hard

- Mixed log types: Activity ×3, Input ×1, Observation ×1
- Only the Observation log (log 4) must be NOT Done — the other 4 must be Done
- Log names reference specific FSMA regulatory codes and procedures requiring domain knowledge to type correctly
- Notes contain regulatory citations, sample IDs, lot codes, and corrective action language — complex text input
- The Input log type for water sampling represents a non-obvious categorization (water testing as a "farm input" operation)
- Times span the full workday (6:30 AM through 5:00 PM)
- No UI navigation hints provided — agent must independently complete all 5 entries

## Required Logs (in any order)

| # | Log Name | Type | Time | Done | GAP Category |
|---|----------|------|------|------|-------------|
| 1 | Worker hygiene training sign-in | Activity | 6:30 AM | Yes | Personnel/Worker Health |
| 2 | Irrigation well water E.coli sampling | Input | 8:00 AM | Yes | Agricultural Water |
| 3 | Field harvest bin sanitation log | Activity | 10:30 AM | Yes | Equipment/Sanitation |
| 4 | Field border wildlife intrusion check | Observation | 1:00 PM | No | Wildlife/Adjacent Land |
| 5 | GAP audit records daily review | Activity | 5:00 PM | Yes | Recordkeeping |

## Verification Strategy

The export script navigates to the Tasks list and dumps the UI hierarchy to `/sdcard/ui_dump_gap.xml`. The verifier checks for each required log name.

**Scoring (100 points total)**:
- Each log name found in Tasks list: 20 points
- Pass threshold: 80 points (4 of 5 logs correct)

## Domain Context

USDA GAP/GHP certification requires documented records in five core areas:
1. **Agricultural Water**: Testing for generic E. coli (must be within 0 MPN/100 mL for direct-contact water)
2. **Worker Health and Hygiene**: Signed training attestations, sanitation facility access
3. **Wildlife and Domesticated Animals**: Monitoring field borders for intrusion evidence
4. **Post-Harvest Handling**: Sanitation records for bins, cold chain documentation, traceability lot codes
5. **Recordkeeping**: Daily audit and verification of all compliance logs

Farm and Home Management Educators are the 5th-highest economic output occupation for farmOS (GDP $11.9M), frequently using the software to demonstrate record-keeping best practices to farming clients and to manage their own consulting operations. The Observation log (wildlife intrusion) is left open (Not Done) because the buffer zone requires re-inspection before the audit — a realistic GAP protocol where open observations trigger follow-up corrective actions.
