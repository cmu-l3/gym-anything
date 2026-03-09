# DevOps Postmortem Action Items

## Occupation Context
**Software Developer / Senior Site Reliability Engineer** (SOC importance: 95.0)
SREs are responsible for ensuring reliability through systematic follow-through on postmortem action items. When postmortem findings go untracked, repeat incidents are the predictable result. Cataloguing, assigning, and following up on action items is a core SRE workflow.

## Task Overview
An engineering team at a high-growth SaaS company has experienced three production incidents in February 2026. Postmortem summaries have been published in `#engineering-postmortems` but none of the action items have been tracked, assigned deadlines, or communicated to owners. The `#sre-on-call` channel shows repeat failures already occurring. The agent plays a Senior SRE and must discover the untracked items, catalogue them with owners and deadlines, notify the responsible engineers, and establish leadership visibility — without being told which channel to read, which action items exist, or what format to use.

## Starting State
- Rocket.Chat running at `http://localhost:3000`
- `#engineering-postmortems`: 3 seeded postmortem summaries:
  - INC-2024-047 (DB failover failure, $180K impact): 4 untracked action items, owners: backend.dev, dba.eng, sre.lead, platform.eng
  - INC-2024-061 (CDN cache purge incident, EU outage): 4 untracked action items, owners: platform.eng, frontend.dev, ops.lead
  - INC-2024-079 (Alert storm + SLO breach, on-call burnout): 4 untracked action items, owners: sre.lead, backend.dev, devops.eng
- `#sre-on-call`: 4 messages showing stalled items causing repeat failures
- `#engineering-general`: reminder message about untracked items
- 7 users: sre.lead, backend.dev, platform.eng, frontend.dev, ops.lead, devops.eng, dba.eng
- Baseline recorded: existing group names, 3 postmortem message IDs for thread verification

## Goal / End State
The agent must independently:
1. Read `#engineering-postmortems` to identify the 3 postmortems and their action items
2. Create a tracking mechanism (new private channel, or catalogue in existing channel)
3. Reference all action owners with assigned responsibility
4. Specify deadlines or due dates for action items
5. Send DMs to the primary action owners (sre.lead, backend.dev, platform.eng, frontend.dev)
6. Reply to threads on the postmortem messages acknowledging each incident's action items
7. Notify leadership (ops.lead) of the tracking status
8. Flag critical items (DB failover, alert storm) with appropriate priority

## Verification Strategy (8 criteria, 100 points, pass >= 60)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 10 | Tracking mechanism established (new channel: 10pts; cataloguing in PM channel: 7pts) |
| C2 | 15 | Owner names referenced in cataloguing content (3+ of 7 engineers mentioned) |
| C3 | 15 | Deadline/due date language present (deadline, by, EOW, sprint, date) |
| C4 | 15 | DMs to primary action owners (sre.lead, backend.dev, platform.eng, frontend.dev) |
| C5 | 10 | Thread replies on at least 2 of 3 postmortem messages |
| C6 | 15 | Leadership (ops.lead) notified via DM or channel invite |
| C7 | 10 | Critical items flagged (DB failover / alert storm keywords present) |
| C8 | 10 | Sufficient coverage: 4+ owners in tracking channel or 5+ distinct owners mentioned |

### Do-nothing gate
If no tracking channel, no thread replies, no DMs, and no cataloguing messages: score = 0.

### Anti-gaming
- Baseline records all groups before setup completes
- Thread verification uses specific seeded postmortem message IDs
- Owner scoring counts distinct owner names in combined admin message content

## Features Exercised
Read multiple channels (3), create private group, post structured tracking messages, send DMs to multiple recipients, thread replies, mention engineering leadership — 6+ distinct features

## Data Sources
- Postmortem format follows real SRE postmortem structure (Blameless/Google SRE style)
- Action items reflect real reliability engineering concerns: DB failover config, CDN purge test coverage, alert quality SLOs
- Incident names (INC-2024-047 etc.) follow real incident numbering conventions
- All monetary impact figures ($180K) are illustrative of realistic P1 business impact
