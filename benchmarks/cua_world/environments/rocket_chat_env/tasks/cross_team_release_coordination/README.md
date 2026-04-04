# Cross-Team Release Coordination

## Occupation Context
**DevOps Engineer / Release Manager** at an e-commerce company.
Coordinating multi-service releases across engineering teams is a core responsibility of release management in software organizations.

## Task Overview
Platform v3.0 is a major release requiring synchronized deployment across 4 teams (Frontend, Backend, Payments, Infrastructure). The deployment window is 2026-03-07 02:00-06:00 UTC. Each team has posted a pre-release checklist in their channel. The release manager must create a coordination channel, post the deployment runbook, collect go/no-go decisions, and communicate with leadership.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#team-frontend` channel exists with pre-release checklist (CONDITIONAL GO - pending cross-browser tests)
- `#team-backend` channel exists with pre-release checklist (GO)
- `#team-payments` channel exists with pre-release checklist (GO)
- `#team-infra` channel exists with pre-release checklist (GO)
- `#release-announcements` channel exists with past release notices
- Users created: `vp.engineering`, `frontend.lead`, `backend.lead`, `payments.lead`, `infra.lead`, `qa.lead`
- No `release-v3-coordination` channel exists yet
- Baseline recorded: existing channels, team checklist message IDs

## Goal / End State
1. Public channel `release-v3-coordination` exists with correct topic
2. All required members invited (vp.engineering, frontend.lead, backend.lead, payments.lead, infra.lead, qa.lead)
3. Deployment runbook posted with ordered sequence and rollback triggers
4. Runbook message pinned
5. Go/no-go status tracker posted with team readiness statuses
6. Message posted in #team-frontend about cross-browser tests
7. Rollback procedure summary posted in coordination channel
8. DM sent to vp.engineering with readiness summary
9. Release notice posted in #release-announcements
10. At least 3 distinct messages in coordination channel

## Verification Strategy (11 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 8 | Public channel `release-v3-coordination` exists |
| C2 | 7 | Topic contains v3.0, deployment window date/time |
| C3 | 12 | Required members invited (2 pts each x 6) |
| C4 | 12 | Deployment runbook with ordered sequence and rollback triggers |
| C5 | 5 | Runbook message pinned |
| C6 | 10 | Go/no-go tracker with team statuses (GO + CONDITIONAL) |
| C7 | 8 | Message in #team-frontend about cross-browser tests |
| C8 | 10 | Rollback procedure summary with team-specific procedures |
| C9 | 10 | DM to vp.engineering with readiness summary |
| C10 | 9 | Release notice in #release-announcements about v3.0 |
| C11 | 9 | At least 3 distinct messages in coordination channel |

### Do-nothing gate
If no coordination channel exists and no DMs or messages posted, score = 0.

### Anti-gaming
- Baseline records existing channels to detect new work
- Checklist message IDs recorded for verification
- DM content checked for readiness/GO/CONDITIONAL keywords
- Distinct message count verified to ensure separate posts

## Features Exercised
Create public channel, set topic, invite members, post messages, pin message, send DM, post in multiple channels (7 distinct features)

## Data Sources
- Pre-release checklists follow real DevOps release management patterns
- Users represent real engineering team roles (VP Engineering, Team Leads, QA)
- Deployment runbook follows industry-standard release coordination practices
