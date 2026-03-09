# Task: technician_group_routing_configuration

## Domain Context

**Occupation**: IT Service Desk Manager / Network Support Specialist
**Industry**: Information Technology — Enterprise IT Support
**Why realistic**: IT Service Desk Managers routinely configure technician groups (queues) to route incoming tickets to the right team automatically. A common real-world scenario: a company's help desk starts as a single pool, but as it grows, tickets must be routed to specialised teams (Network, Hardware, Software, etc.) based on category. This requires creating the groups, assigning technicians, and updating ticket assignments. This workflow spans 4–5 different sections of the ITSM admin interface.

---

## Goal

The service desk currently has no specialised technician groups — all tickets go to a single pool. The IT Service Desk Manager must:

1. Create a technician group named **"Network Operations Team"**
2. Create a technician group named **"Hardware Support Team"**
3. Create a new technician account **Maya Patel** (login: mpatel) and add her to the Network Operations Team
4. Create a new technician account **Carlos Rivera** (login: crivera) and add him to the Hardware Support Team
5. Assign the VPN connectivity ticket (the one about VPN dropping) to the **Network Operations Team** group
6. Assign the keyboard issue ticket to the **Hardware Support Team** group

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Network Operations Team created | 20 | Group with this name exists in the system |
| Hardware Support Team created | 20 | Group with this name exists in the system |
| Maya Patel created | 20 | Technician with firstname=Maya, lastname=Patel exists |
| Carlos Rivera created | 20 | Technician with firstname=Carlos, lastname=Rivera exists |
| VPN ticket (1004) → Network group | 10 | Ticket 1004 assigned to Network Operations Team |
| Keyboard ticket (1001) → Hardware group | 10 | Ticket 1001 assigned to Hardware Support Team |

**Pass threshold**: 60/100
**Difficulty**: very_hard

---

## Verification Strategy

The `export_result.sh` script:
1. Queries PostgreSQL `supportgroup` (or `techniciangroup`) table for groups with names matching 'network operations%' and 'hardware support%'
2. Queries `sduser` for technicians named Maya Patel and Carlos Rivera
3. Queries `workorderstates.groupid` for tickets 1001 and 1004
4. Calls REST API `GET /api/v3/groups` (or `/api/v3/technician_groups`) to cross-check group existence
5. Calls `GET /api/v3/requests/1001` and `/api/v3/requests/1004` to check the `group.name` field
6. Writes all results to `/tmp/technician_group_routing_configuration_result.json`

The `verifier.py` function `verify_technician_group_routing_configuration`:
- **Wrong-target gate**: If neither group exists → score=0 (nothing meaningful was done)
- **Criteria 1–4**: Binary checks (group/technician exists or not)
- **Criteria 5–6**: Check both SQL `groupid` correlation and API `group.name` string match

---

## Schema Reference

**Key tables (PostgreSQL, port 65432, database `servicedesk`):**

```sql
-- Check technician groups
SELECT groupid, groupname FROM supportgroup WHERE LOWER(groupname) LIKE '%network%';
SELECT groupid, groupname FROM supportgroup WHERE LOWER(groupname) LIKE '%hardware%';

-- Check technician accounts
SELECT userid, firstname, lastname, status FROM sduser WHERE LOWER(firstname)='maya';
SELECT userid, firstname, lastname, status FROM sduser WHERE LOWER(firstname)='carlos';

-- Check ticket group assignment
SELECT workorderid, groupid FROM workorderstates WHERE workorderid IN (1001, 1004);
```

**REST API (https://localhost:8080/api/v3/):**
- `GET /api/v3/groups` — list all technician groups
- `GET /api/v3/technicians` — list all technician accounts
- `GET /api/v3/requests/{id}` — check `group.name` in response

---

## Pre-existing Data

- **Ticket 1001**: "Keyboard not working" — Hardware category, needs Hardware Support Team
- **Ticket 1004**: "VPN keeps dropping every 30 minutes" — Network category, needs Network Operations Team
- No technician groups exist in the baseline state
- Maya Patel and Carlos Rivera do not exist in the baseline state (verified in setup)

---

## Edge Cases and Potential Issues

- **Group table name**: SDP may use `supportgroup`, `techniciangroup`, or similar. The export script tries multiple names.
- **API endpoint variation**: The Groups API may be at `/api/v3/groups` or `/api/v3/technician_groups`. The export script tries both.
- **Group assignment vs. technician assignment**: A ticket can have both a `groupid` (the team) and an `ownerId` (individual technician). This task requires the group assignment, not individual assignment. The agent must use the correct field.
- **Technician creation requires email**: SDP may require a valid email address when creating technician accounts. The agent must provide one.
- **Group membership**: After creating groups and technicians separately, the agent must also add the technician to the group (these are often separate UI steps in SDP).
