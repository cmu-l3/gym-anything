# supplier_capa_closure

## Domain Context

**Occupation**: Quality Assurance Engineer (Manufacturing)
**Industry**: Office Furniture / Precision Manufacturing
**Software**: Odoo 17 Quality Module
**Difficulty**: very_hard

Quality Assurance Engineers in manufacturing are responsible for ensuring all non-conformance records are formally closed before batch release decisions are made. CAPA (Corrective and Preventive Action) documentation is a core ISO 9001 / FDA 21 CFR Part 820 requirement — every open quality alert must have both a corrective action (what was done immediately to contain the defect) and a preventive action (what process change prevents recurrence) before it can be closed.

## Task Description

Production has halted because all quality alerts in the "In Progress" stage are missing their CAPA documentation. The QA manager requires:

1. **Corrective action** documented on every In Progress alert (what was done to fix the immediate issue)
2. **Preventive action** documented on every In Progress alert (what process change prevents recurrence)
3. Every In Progress alert transitioned to the **Done** stage to formally close the corrective action record

The agent must discover which alerts are in the In Progress stage, navigate to each one, fill in both CAPA fields, and move the alert to Done. No specific alert names are given — the agent must find them.

## Starting State

`setup_task.sh` finds all quality alerts in the "In Progress" stage and:
- Clears `corrective_action` field on all of them
- Clears `preventive_action` field on all of them
- Leaves their stage as "In Progress"

The In Progress alerts (5 total from setup_data.py) are:
- Cabinet Door Hinge Misalignment
- Acoustic Panel Bonding Failure
- Desk Height Adjustment Mechanism Stiff
- Chair Foam Density Below Grade
- Cabinet Coating Thickness Non-Uniform

## Verification Strategy

**Multi-criterion scoring (100 pts total, pass ≥ 60):**

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1: Corrective action | 35 pts | All target alerts have corrective_action ≥ 10 chars |
| C1 partial | 17 pts | ≥ 50% of alerts have corrective_action |
| C2: Preventive action | 35 pts | All target alerts have preventive_action ≥ 10 chars |
| C2 partial | 17 pts | ≥ 50% of alerts have preventive_action |
| C3: Done stage | 30 pts | All target alerts in Done stage |
| C3 partial | 15 pts | ≥ 50% of alerts in Done stage |

**Anti-gaming**: The verifier reads alert states via the GT file saved during setup, which records the exact alert IDs that were in In Progress stage. Wrong alerts cannot be credited.

**Partial credit check**: Max partial total = 17+17+15 = 49 < 60 (pass threshold). Only genuine task completion can cross the pass line.

## Schema Reference

- **Model**: `quality.alert`
- **Fields**: `corrective_action` (Html), `preventive_action` (Html), `stage_id` (Many2one → `quality.alert.stage`)
- **Stage names**: New (sequence=1), In Progress (sequence=5), Done (sequence=10, folded=True)
- **DB**: `odoo_quality` (PostgreSQL in Docker)

## Files

- `task.json` — task configuration and hooks
- `setup_task.sh` — clears CAPA fields on all In Progress alerts, saves GT file
- `export_result.sh` — reads CAPA fields and stage for each target alert
- `verifier.py` — multi-criterion scoring on corrective, preventive, and stage

## Edge Cases

- Agent may complete only some alerts: handled by partial credit
- Agent may fill corrective but not preventive: C1 passes, C2 fails (35+0 = 35, not enough to pass alone)
- Agent may document but forget to close the stage: C1+C2 = 70, partial pass even without C3
