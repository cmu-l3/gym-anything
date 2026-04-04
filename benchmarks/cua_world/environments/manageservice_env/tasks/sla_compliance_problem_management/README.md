# Task: sla_compliance_problem_management

## Domain Context

**Occupation**: IT Operations Manager
**Industry**: Information Technology — Enterprise Service Desk
**Why realistic**: IT Operations Managers own SLA compliance and are responsible for escalating patterns of missed SLAs. When high-priority tickets pile up unresolved, the standard ITSM response is to (a) triage the backlog by updating status and assigning ownership, and (b) create a Problem record to track the root cause of repeated SLA misses and link the contributing incidents to it. This is a core day-to-day workflow for any team using ITIL-aligned service desks.

---

## Goal

The service desk has three Open, High-priority service requests that have been sitting unattended, driving SLA compliance down to 22% this month. The IT Operations Manager must:

1. Change the status of all three Open High-priority requests to **"In Progress"** and assign each to the **administrator** technician.
2. Create a new **Problem** record titled **"Recurring SLA Compliance Failures - High Priority Response Times"** with **High** priority, and **link all three service requests** to this Problem as related incidents.

The final state must have:
- Tickets 1001, 1003, and 1004 in a non-Open status with a technician assigned
- A Problem record with the specified title containing links to those tickets

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Status changed | 30 | Each of the 3 tickets moved out of Open status (10 pts each) |
| Technician assigned | 25 | Each of the 3 tickets has a technician owner (≈8 pts each) |
| Problem created | 25 | Problem record with 'SLA' + 'compliance/failure/breach' in title |
| Problem linked | 20 | ≥2 of the 3 tickets linked to the Problem (20 pts), or 1 linked (10 pts) |

**Pass threshold**: 60/100
**Difficulty**: very_hard

---

## Verification Strategy

The `export_result.sh` script:
1. Queries PostgreSQL `workorderstates` for the `statusid` and `ownerId` of workorderids 1001, 1003, 1004
2. Calls `GET /api/v3/requests/{id}` to get `status.name` and `technician.name` via REST API
3. Calls `GET /api/v3/problems` and searches for a problem whose title contains both 'sla' and ('compliance' OR 'failure' OR 'breach')
4. For the matching Problem, calls `GET /api/v3/problems/{id}` to retrieve linked request IDs
5. Writes everything to `/tmp/sla_compliance_problem_management_result.json`

The `verifier.py` function `verify_sla_compliance_problem_management`:
- **Wrong-target gate**: If no tickets changed status AND no problem was created → score=0
- **Criterion 1**: Counts tickets where statusid != 2 (Open)
- **Criterion 2**: Counts tickets where ownerId > 0 OR technician_name is non-empty
- **Criterion 3**: Checks `problem_found` boolean
- **Criterion 4**: Uses `problem_linked_target_count` (max of SQL and API counts)

---

## Schema Reference

**Key tables (PostgreSQL, port 65432, database `servicedesk`):**

```sql
-- Check ticket status
SELECT statusid, ownerId FROM workorderstates WHERE workorderid IN (1001, 1003, 1004);

-- statusid values: 2=Open, 3=In Progress (or similar), 4=Resolved, 5=Closed

-- Ticket details
SELECT workorderid, title FROM workorder WHERE workorderid IN (1001, 1003, 1004);
```

**REST API (https://localhost:8080/api/v3/):**
- `GET /api/v3/requests/{id}` — returns status.name, technician.name, priority.name
- `GET /api/v3/problems` — list all problems; check title field
- `GET /api/v3/problems/{id}` — get problem details including linked requests

---

## Pre-existing Data

The three target tickets created at task setup:
- **1001**: "Keyboard not working" — Hardware, High priority, Open, unassigned
- **1003**: "Office printer not printing" — Hardware, High priority, Open, unassigned
- **1004**: "VPN keeps dropping every 30 minutes" — Network, High priority, Open, unassigned

---

## Edge Cases and Potential Issues

- **Problem module location**: In ServiceDesk Plus, Problem records are found under "Problems" in the left navigation or via Admin > Problem Management. The agent must discover this.
- **Linking requests to problems**: SDP allows linking incidents to problems via the "Related Incidents" or "Linked Requests" tab within a Problem record. The export script checks multiple field names (`requests`, `related_requests`, `linked_requests`) to handle API version differences.
- **Status names**: Exact status names depend on SDP configuration. The verifier uses `statusid != 2` (not just name-matching) so partial credit is robust to status name variations.
- **Problem title matching**: The verifier uses lowercase keyword matching ('sla' AND one of 'compliance'/'failure'/'breach') — not an exact title match — so minor variations in capitalization are handled.
