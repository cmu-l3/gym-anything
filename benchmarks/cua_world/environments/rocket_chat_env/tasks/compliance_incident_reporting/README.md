# Compliance Incident Reporting

## Occupation Context
**Information Security Analyst** (Healthcare industry)
Investigating data breaches, coordinating HIPAA incident response, and ensuring regulatory compliance are core responsibilities of information security analysts in healthcare organizations.

## Task Overview
A SIEM system has detected a critical security incident: a patient records API endpoint (`/api/v2/patients/records`) was deployed without authentication middleware after build #4891, potentially exposing Protected Health Information (PHI) for 847 patients to an external IP address (203.0.113.42) over a 6-hour window (2026-03-06 02:15 to 08:15 UTC). This triggers HIPAA Breach Notification Rule requirements (45 CFR 164.400-414). The agent must coordinate the full incident response and regulatory compliance workflow in Rocket.Chat.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#security-monitoring` channel exists with 6 seeded messages (daily SIEM summary, outbound data warning, **critical PHI exposure alert**, emergency hotfix info, firewall block info, forensic log preservation)
- `#compliance-log` channel exists with 2 seeded compliance log entries
- Users created: `privacy.officer`, `legal.counsel`, `it.director`, `hr.manager`, `sys.admin`, `app.developer`
- No `hipaa-inc-2026-0306` channel exists yet
- Baseline recorded: PHI alert message ID, existing groups/channels

## Goal / End State
1. PHI alert message starred in `#security-monitoring`
2. Private channel `hipaa-inc-2026-0306` exists with correct topic
3. Incident response team (`privacy.officer`, `legal.counsel`, `it.director`, `sys.admin`) invited
4. Structured incident report posted with all required sections (Incident Summary, Affected Data, Timeline, Containment Actions, Regulatory Requirements)
5. Incident report pinned
6. Thread reply on the critical PHI alert in `#security-monitoring` confirming HIPAA process initiated
7. DM sent to `privacy.officer` about 60-day notification clock and patient notification letters
8. DM sent to `legal.counsel` about legal hold and HHS/OCR notification
9. Message posted in `#compliance-log` documenting the incident

## Verification Strategy (10 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 7 | PHI alert message starred in #security-monitoring |
| C2 | 10 | Private channel `hipaa-inc-2026-0306` exists (5 if public) |
| C3 | 8 | Channel topic contains HIPAA + PHI/patients/847 + /api/v2/records |
| C4 | 12 | Required members invited (3 pts each: privacy.officer, legal.counsel, it.director, sys.admin) |
| C5 | 15 | Structured incident report with required sections (partial credit per section) |
| C6 | 5 | Incident report pinned |
| C7 | 10 | Thread reply on PHI alert confirming HIPAA process initiated |
| C8 | 12 | DM to privacy.officer about 60-day notification / affected patients |
| C9 | 11 | DM to legal.counsel about legal hold / HHS / OCR |
| C10 | 10 | Message in #compliance-log about the incident (date + PHI exposure + 847 patients) |

### Do-nothing gate
If no incident channel exists and no DMs/threads/stars created, score = 0.

### Anti-gaming
- Baseline records existing channels to detect new work
- Thread reply is validated against the specific PHI alert message ID from setup
- Star status checked via Rocket.Chat API
- DM content checked for relevant keywords (60-day, notification, legal hold, HHS, OCR)
- Compliance log message verified for required data points

## Features Exercised
Star message, create private channel, set topic, invite members, post messages, pin message, thread reply, send DMs (2 recipients), post in existing channel (10 distinct features)

## Data Sources
- Alert messages follow real SIEM/SOC alert formats
- Users represent real incident response roles in healthcare (Privacy Officer, Legal Counsel, IT Director, System Administrator)
- Regulatory references follow actual HIPAA Breach Notification Rule (45 CFR 164.400-414)
