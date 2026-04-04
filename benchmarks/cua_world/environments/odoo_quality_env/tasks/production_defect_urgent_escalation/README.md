# production_defect_urgent_escalation

## Domain Context

**Occupation**: First-Line Supervisor of Production
**Industry**: Furniture Manufacturing
**Software**: Odoo 17 Quality Module (Quality Checks + Quality Alerts)
**Difficulty**: very_hard

Production Floor Supervisors must immediately document quality failures discovered during physical inspection and simultaneously create escalation records to alert management. These two actions — recording a specific check failure AND creating an urgent escalation alert — are typically done in parallel during a production hold event.

## Task Description

Two simultaneous events require immediate system documentation:

1. **Fail a pending quality check**: The quality check "Visual Inspection - Cabinet Finish" was just physically performed and failed. The agent must mark it as Failed with detailed notes describing the defect (at minimum describing surface irregularities, discoloration, or thickness issues).

2. **Create an Urgent escalation alert**: The batch failure triggers a mandatory escalation. The agent must create a new quality alert with "Urgent" priority, assign it to an existing quality team if one exists, and give it a meaningful description explaining the production hold situation.

## Starting State

`setup_task.sh`:
- Resets "Visual Inspection - Cabinet Finish" quality check to state='none' with empty notes
- Removes any prior Urgent batch hold alerts (idempotent)
- Records available quality teams for later validation

## Verification Strategy

**Multi-criterion scoring (100 pts total, pass ≥ 60):**

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1: Check marked Failed with notes | 40 pts | quality_state='fail' AND note ≥ 20 chars |
| C1 partial (failed, no notes) | 20 pts | quality_state='fail' but note < 20 chars |
| C2: Urgent alert created | 35 pts | New quality.alert with priority='2' or '3' exists |
| C3: Alert has description + team | 25 pts | Alert description ≥ 20 chars AND team_id assigned |
| C3 partial (description only) | 15 pts | Description ≥ 20 chars but no team |
| C3 partial (team only) | 10 pts | Team assigned but no description |

**Anti-gaming**: The "new Urgent alert" check looks at all Urgent/Blocker alerts currently in the system. Since setup clears prior ones and none exist in the seeded data, any Urgent alert found at export time was created by the agent.

**Partial credit check**: Max partial = 20 (fail, no notes) + 0 + 15 (desc, no team) = 35 < 60. ✓

## Schema Reference

- **Model**: `quality.check`
  - `name`: "Visual Inspection - Cabinet Finish"
  - `quality_state`: 'none' → agent must set to 'fail'
  - `note`: Html field for inspection notes
- **Model**: `quality.alert`
  - `priority`: '2'=Urgent, '3'=Blocker
  - `team_id`: Many2one → quality.alert.team
  - `description`: Html field

## Files

- `task.json` — task configuration and hooks
- `setup_task.sh` — resets check to none state, clears prior Urgent alerts
- `export_result.sh` — reads check state/notes, finds new Urgent alerts
- `verifier.py` — multi-criterion scoring

## Edge Cases

- If no quality teams exist in system: C3 team requirement is waived (15 pts awarded for description alone becoming 25)
- Agent may create Blocker (priority='3') instead of Urgent: still passes C2
- Notes with HTML formatting: stripped before length check
