# Incident Response Coordination

## Occupation Context
**Computer and Information Systems Manager** (SOC importance: 98.0)
Coordination with teams, stakeholders, and vendors during production incidents is a primary function of IT systems management.

## Task Overview
A P1 production incident has been reported: the database connection pool on `db-prod-01` is exhausted, causing 503 errors across `user-auth`, `payment-gateway`, and `inventory-sync` services. The agent must coordinate the full incident response in Rocket.Chat.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#production-alerts` channel exists with 5 seeded alert messages (CPU, SSL cert, **critical DB connection pool**, disk usage, CDN maintenance)
- `#engineering-general` channel exists
- Users created: `ops.lead`, `backend.dev`, `dba.admin`, `qa.engineer`, `frontend.dev`
- No incident channel exists yet
- Baseline recorded: existing groups/channels, DB alert message ID

## Goal / End State
1. Private incident channel `inc-20260306-db-outage` exists with correct topic
2. On-call responders (`ops.lead`, `backend.dev`, `dba.admin`) invited
3. Incident summary posted with Impact, Current Status, and Next Steps sections
4. Summary message pinned
5. Thread reply on the critical DB alert in `#production-alerts` referencing the incident channel
6. DM sent to `qa.engineer` requesting regression test plan
7. Status update posted in the incident channel

## Verification Strategy (8 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 12 | Private channel `inc-20260306-db-outage` exists (6 if public) |
| C2 | 12 | Topic contains P1 + database/connection pool + timestamp |
| C3 | 15 | Required members invited (5 pts each) |
| C4 | 15 | Incident summary with Impact/Status/Next Steps sections |
| C5 | 10 | At least one pinned message in incident channel |
| C6 | 12 | Thread reply on DB alert in #production-alerts |
| C7 | 12 | DM to qa.engineer about test plan |
| C8 | 12 | Status update message in incident channel |

### Do-nothing gate
If no incident channel exists and no DMs/threads created, score = 0.

### Anti-gaming
- Baseline records existing channels to detect new work
- Thread reply is validated against the specific DB alert message ID from setup
- DM content checked for test/regression/plan keywords
- Status update must be distinct from the summary message

## Features Exercised
Create private channel, set topic, invite members, post messages, pin message, thread reply, send DM (7 distinct features)

## Data Sources
- Alert messages follow real production monitoring alert formats (Datadog/PagerDuty style)
- Users represent real incident response roles (Ops Lead, Backend Dev, DBA, QA Engineer)
