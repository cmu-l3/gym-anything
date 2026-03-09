# Task: change_request_full_lifecycle

## Domain Context

**Occupation**: IT Change Manager / Network and Computer Systems Administrator
**Industry**: Information Technology — Enterprise Infrastructure
**Why realistic**: Change Managers in ITIL environments handle formal Change Requests (RFCs) for significant infrastructure work. Replacing end-of-life network switches is a textbook Normal Change: it requires a CAB (Change Advisory Board) review, detailed rollout and backout plans, and linkage to the incidents that triggered the need. Creating a complete RFC through the ITSM tool — with reason, impact/risk assessment, linked incidents, sub-tasks, and formal submission — is a multi-step workflow that spans the Change Management module's full capabilities.

---

## Goal

Repeated VPN outages have been traced to end-of-life Cisco Catalyst 2960 switches in Buildings A and B. The Change Manager must create a formal Change Request and submit it for CAB review. The end state must include:

1. A **Change Request** titled **"Campus Network Core Switch Replacement - Buildings A and B"**, type **Normal**, with High impact, High risk, a documented reason for change, and both rollout and backout plans filled in.
2. The existing **VPN connectivity incident** (ticket about VPN dropping every 30 minutes) **linked** to this Change as a related incident.
3. At least **one Change Task** added to the Change (e.g., a pre-deployment configuration backup task).
4. The Change **status set to "Requested"** to submit it for CAB review.

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Change created | 30 | Change with 'Campus Network' or 'Switch Replacement' in title exists |
| Change tasks ≥1 | 20 | At least one sub-task added to the Change |
| VPN incident linked | 20 | Ticket 1004 linked to this Change as a related incident |
| Status = Requested | 20 | Change submitted for CAB review |
| Reason + plan | 10 | reason_for_change AND at least one of rollout/backout plan filled in (5 pts for reason only) |

**Pass threshold**: 60/100
**Difficulty**: very_hard

---

## Verification Strategy

The `export_result.sh` script:
1. Queries PostgreSQL for a Change record with 'campus network' or 'switch replacement' in the title (tries tables: `changemanagement`, `changedetails`, `globalchange`)
2. Queries for Change Tasks associated with the found Change ID (tries tables: `changetask`, `changeactivity`)
3. Queries for the incident link between Change and ticket 1004 (tries tables: `changerequestlink`, `changeincidentlink`)
4. Cross-checks via REST API: `GET /api/v3/changes`, `GET /api/v3/changes/{id}/tasks`, `GET /api/v3/changes/{id}/linked_requests`
5. Checks `GET /api/v3/requests/1004` for a `change` field pointing to this Change
6. Writes all results to `/tmp/change_request_full_lifecycle_result.json`

The `verifier.py` function `verify_change_request_full_lifecycle`:
- **Wrong-target gate**: If no Change with 'campus network' or 'switch replacement' in title → score=0
- **Criterion 1**: `change_found` boolean (title keyword match)
- **Criterion 2**: `change_task_count >= 1`
- **Criterion 3**: `vpn_ticket_linked` boolean
- **Criterion 4**: `change_status_is_requested` boolean
- **Criterion 5**: `has_reason AND (has_rollout OR has_backout)` for full 10 pts; `has_reason` only for 5 pts

---

## Schema Reference

**Key tables (PostgreSQL, port 65432, database `servicedesk`):**

```sql
-- Find the Change record (try multiple table names)
SELECT * FROM changemanagement WHERE LOWER(title) LIKE '%campus network%';
SELECT * FROM changedetails WHERE LOWER(subject) LIKE '%switch replacement%';

-- Find linked incidents
SELECT * FROM changerequestlink WHERE changeid = <change_id>;

-- Find Change Tasks
SELECT * FROM changetask WHERE changeid = <change_id>;
```

**REST API (https://localhost:8080/api/v3/):**
- `GET /api/v3/changes` — list all changes; filter by title
- `GET /api/v3/changes/{id}` — full change details including status, type, impact, risk
- `GET /api/v3/changes/{id}/tasks` — change sub-tasks
- `GET /api/v3/changes/{id}/linked_requests` — linked incidents

---

## Pre-existing Data

- **Ticket 1004**: "VPN keeps dropping every 30 minutes" — Network, High priority, Open. This is the triggering incident that must be linked to the Change.
- No existing Change records in the system.

---

## Edge Cases and Potential Issues

- **Change Management module**: In ServiceDesk Plus, Changes are managed under a dedicated "Changes" module. The agent must navigate to it (separate from Requests/Incidents).
- **Normal vs. Standard change type**: SDP may offer Emergency, Normal, and Standard change types. The task requires "Normal".
- **Impact/Risk fields**: These are typically dropdown fields (Low/Medium/High) in the Change record's main form.
- **CAB submission**: "Requested" status may be labeled differently in some SDP versions (e.g., "Submitted for Approval"). The verifier checks for 'requested' case-insensitively.
- **Table name uncertainty**: The exact PostgreSQL table for Changes varies by SDP version. The export script tries `changemanagement`, `changedetails`, and `globalchange`. The API is the primary verification source.
- **Linking order**: The agent may need to create the Change first, then go back into the VPN ticket to link it to the Change — or link from within the Change's related incidents panel. Either approach produces the same DB state.
