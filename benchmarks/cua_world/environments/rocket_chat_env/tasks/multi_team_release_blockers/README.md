# Multi-Team Release Blockers

## Occupation Context
**Computer and Information Systems Manager / Engineering Manager** (SOC importance: 98.0)
Engineering Managers are responsible for coordinating multi-team releases and making go/no-go decisions when teams are deadlocked. When backend, security, and QA teams all block a release for different reasons, the EM must diagnose which blockers are genuine, resolve team disputes, assign ownership, and communicate a definitive decision to all stakeholders.

## Task Overview
v4.0 was supposed to ship yesterday. Three teams each claim a release blocker, but each team lead believes the other teams' blockers are not their responsibility. Sales has already committed v4.0 to enterprise customers. The VP of Engineering is asking for a status update. The `#release-v4` channel contains all three blocker descriptions. The agent plays the Engineering Manager and must read the situation, adjudicate each blocker, assign ownership and timelines, make a go/no-go decision, and update all stakeholders — without being told which channel to read, what decisions to make, or who to contact.

## Starting State
- Rocket.Chat running at `http://localhost:3000`
- `#release-v4`: 5 seeded messages:
  - General delay notice with request for decision
  - Backend blocker: DB migration script fails on tables >5M rows (3 of 12 customers affected; workaround exists via batch script)
  - Security blocker: Semgrep found 1 HIGH (OAuth2 CSRF in token refresh), 1 MEDIUM (verbose error messages); backend disputes HIGH as unexploitable given CORS config
  - QA blocker: 3 e2e tests fail in staging due to CI config drift (wrong Stripe test key); tests pass locally and in QA env; DevOps says it's infra, not code
  - Stakeholder urgency message from sales perspective
- `#engineering-security`: 1 seeded message with full Semgrep scan results
- `#backend-team`: 1 seeded message clarifying migration workaround is available
- 8 users: backend.lead, security.eng, qa.lead, vp.engineering, product.manager, sales.lead, devops.lead, frontend.dev2
- Baseline recorded: all existing group names, 3 key blocker message IDs for thread verification

## Goal / End State
The agent must independently:
1. Read `#release-v4` (and optionally `#engineering-security`, `#backend-team`) to understand all three blockers
2. Create a coordination channel or post substantive decisions in the release channel
3. Engage all three blocker owners (backend.lead, security.eng, qa.lead) with clear direction
4. Reply to threads on each of the 3 blocker messages with decisions or escalations
5. Make explicit go/no-go decision language for the release
6. Assign resolution timelines for each blocker
7. Notify VP Engineering (vp.engineering) with a status update
8. Update external stakeholders (sales.lead or product.manager) on revised timeline

## Verification Strategy (8 criteria, 100 points, pass >= 60)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 10 | Coordination channel created OR substantive admin messages in release channel (3+) |
| C2 | 15 | All 3 blocker owners engaged (backend.lead, security.eng, qa.lead) via DM or channel |
| C3 | 15 | Thread replies on at least 2 of 3 blocker messages |
| C4 | 15 | Go/no-go decision language (approve, proceed, ship, hold, block, green light, decision) |
| C5 | 15 | Resolution timelines assigned for blockers (hours, days, by, deadline, ETA, today) |
| C6 | 10 | VP Engineering (vp.engineering) notified with status update |
| C7 | 10 | External stakeholders (sales.lead or product.manager) updated on revised timeline |
| C8 | 10 | All 3 blockers acknowledged in admin messages (migration, security/OAuth, e2e tests) |

### Do-nothing gate
If no coordination activity, no thread replies, no DMs, and no admin messages in release channel: score = 0.

### Anti-gaming
- Baseline records all groups; only agent-created groups evaluated as coordination channels
- Thread verification uses specific seeded blocker message IDs
- Blocker acknowledgment requires domain-specific keywords (migration/db, oauth/csrf, e2e/staging)

## Features Exercised
Read 3 different channels to piece together technical situation, create private coordination channel, adjudicate disputes between team leads via DMs, thread replies on 3 separate blocker messages, post structured decisions, notify leadership — 7+ distinct Rocket.Chat features

## Data Sources
- DB migration blocker reflects real production upgrade scenarios (large table row count edge cases)
- Security finding follows real Semgrep/SAST workflow (OAuth2 PKCE implementation, CSRF in token refresh)
- QA blocker reflects real CI/CD environment config drift scenarios (Stripe test key, staging env)
- Go/no-go process reflects real engineering release management workflow
- Team lead dispute pattern (each blaming another team) reflects common cross-functional org dynamics
