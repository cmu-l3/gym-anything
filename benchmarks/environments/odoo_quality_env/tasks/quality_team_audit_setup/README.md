# quality_team_audit_setup

## Domain Context

**Occupation**: Compliance Manager / Internal Audit Manager
**Industry**: Office Workspace Solutions / Manufacturing
**Software**: Odoo 17 Quality Module
**Difficulty**: very_hard

Compliance Managers must ensure quality management systems meet ISO 9001 surveillance audit requirements. A critical requirement is that every open quality alert has a responsible team assigned for accountability. Prior to audits, managers must also triage safety-critical alerts to ensure they receive Urgent escalation per company risk classification procedures.

## Task Description

An ISO 9001 surveillance audit is scheduled for next week. Pre-audit gap analysis found that none of the quality alerts in the "New" stage have a quality team assigned — a major non-conformance. The agent must:

1. **Create** a new quality alert team named **"ISO Surveillance Response Team"**
2. **Assign** ALL quality alerts currently in the New stage to this new team
3. **Escalate** New-stage alerts describing structural failures, hardware problems, or material cracking to **"Urgent"** priority

The agent must navigate to Quality > Teams to create the team, then to Quality Alerts and filter by New stage to make assignments, then identify which alerts are safety-critical from their descriptions/titles.

## Starting State

`setup_task.sh`:
- Removes any pre-existing "ISO Surveillance Response Team" (idempotent reset)
- Clears `team_id` from all New-stage alerts
- Resets all New-stage alert priorities to Normal (0)

The 8 New-stage alerts in the system:
- Paint Discoloration on Metal Panels (Normal)
- Incorrect Spacing Between Components (Normal)
- Material Hardness Below Specification (Normal, reset from High)
- Critical Weld Failure on Frame (Normal) ← safety-critical (Weld)
- Loose Hardware on Shelf Unit (Normal) ← safety-critical (Hardware)
- Desk Laminate Delamination (Normal)
- Chair Armrest Cracking (Normal, reset from High) ← safety-critical (Cracking)
- Screen Frame Scratch on Delivery (Normal)

## Verification Strategy

**Multi-criterion scoring (100 pts total, pass ≥ 60):**

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1: Team created | 20 pts | "ISO Surveillance Response Team" exists in quality.alert.team |
| C2: All 8 alerts assigned to team | 50 pts | 100% of New-stage alerts have team_id = new team |
| C2 partial (≥75%) | 38 pts | ≥ 6/8 alerts assigned |
| C2 partial (≥50%) | 25 pts | ≥ 4/8 alerts assigned |
| C3: 3 safety-critical alerts Urgent | 30 pts | All 3 (Weld, Hardware, Cracking) at priority '2' |
| C3 partial (2/3) | 20 pts | 2 of 3 escalated |
| C3 partial (1/3) | 10 pts | 1 of 3 escalated |

**Anti-gaming**: If team not found (C1 fails), C2 cannot score (team_id check is impossible without a team).

**Partial credit check**: Max without full pass: if team found (20) + 50% assignment (25) + 0 escalations = 45 < 60. Or team + 75% assignment + 1 escalation = 20+38+10 = 68 (pass). Only meaningful partial work crosses 60.

## Schema Reference

- **Model**: `quality.alert.team` (create team)
- **Model**: `quality.alert` (update `team_id`, `priority`)
- **Priority values**: '0'=Normal, '1'=High, '2'=Urgent, '3'=Blocker
- **Target team name**: "ISO Surveillance Response Team"

## Files

- `task.json` — task configuration and hooks
- `setup_task.sh` — removes stale team, clears assignments and priorities
- `export_result.sh` — checks team existence, counts assignments, checks escalations
- `verifier.py` — multi-criterion scoring

## Edge Cases

- If no team is found, C2 automatically skips (returns early with low score)
- If agent creates a differently-named team, C1 fails and score drops below pass threshold
- Safety-critical alerts identified by keywords "Weld", "Hardware", "Cracking" in alert titles
