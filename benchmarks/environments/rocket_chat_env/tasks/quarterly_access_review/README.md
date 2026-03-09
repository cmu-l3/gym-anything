# Quarterly Access Review

## Occupation Context
**Computer and Information Systems Manager** (SOC importance: 98.0)
IT Security/Compliance management requires periodic channel permission audits to enforce least-privilege access and regulatory compliance.

## Task Overview
A quarterly access review has revealed over-provisioned channel permissions. The agent must read the access policy from `#compliance-announcements`, remove unauthorized users from restricted channels, document all changes, and notify affected users.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#compliance-announcements` contains the Q1 2026 access policy message
- `#finance-reports` created with ALL 7 users (over-provisioned: authorized are `finance.manager`, `senior.analyst`)
- `#hr-confidential` created with ALL 7 users (over-provisioned: authorized are `hr.director`, `finance.manager`)
- Users: `finance.manager`, `hr.director`, `senior.analyst`, `dev.jones`, `dev.wilson`, `contractor.smith`, `former.intern`
- Baseline: initial member lists for both channels recorded

## Goal / End State
1. `#finance-reports` has only `finance.manager` and `senior.analyst` (+ admin)
2. `#hr-confidential` has only `hr.director` and `finance.manager` (+ admin)
3. Audit trail messages posted in each modified channel
4. `access-review-q1-2026` channel created with summary report
5. DMs sent to `contractor.smith` and `former.intern` about access revocation

## Verification Strategy (9 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 15 | Unauthorized users removed from finance-reports (4 users) |
| C2 | 15 | Unauthorized users removed from hr-confidential (5 users) |
| C3 | 10 | Authorized users retained in finance-reports |
| C4 | 10 | Authorized users retained in hr-confidential |
| C5 | 10 | Audit trail messages in modified channels |
| C6 | 10 | access-review-q1-2026 channel created |
| C7 | 10 | Summary report in review channel |
| C8 | 10 | DM to contractor.smith about revocation |
| C9 | 10 | DM to former.intern about revocation |

### Do-nothing gate
If member lists unchanged and no review channel created, score = 0.

### Anti-gaming
- Baseline member lists compared to current members (detects actual removals)
- Checks that authorized users were NOT removed (penalizes over-removal)
- Audit trail must reference "removed" or "access review" keywords
- DM content checked for access-related keywords

## Features Exercised
Read messages, remove channel members, post messages, create public channel, send DMs (5 distinct features with member removal being unique to this task)

## Data Sources
- Access policy follows real corporate compliance document format
- Channel structure models real restricted-access channel patterns (finance, HR)
