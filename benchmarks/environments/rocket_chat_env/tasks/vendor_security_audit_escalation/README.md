# Vendor Security Audit Escalation

## Occupation Context
**Computer and Information Systems Manager** (Financial Services industry)
Coordinating vendor security remediation, PCI-DSS compliance escalation, and cross-team mobilization after a critical penetration test finding is a core function of IT security management in financial services.

## Task Overview
A third-party penetration test by CyberGuard Solutions has revealed 3 critical CVEs affecting vendor integrations (PayStream API, IdentityBridge SSO, DataSync middleware). The agent must coordinate the full security remediation response in Rocket.Chat: star the alert, create a remediation channel, triage vulnerabilities, notify compliance and vendor teams, and post status updates.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#security-alerts` channel exists with 6 seeded messages (monthly scan, unusual login, **critical pentest report**, firewall update, TLS warning, SOC 2 audit)
- `#vendor-integrations` channel exists with 3 ongoing vendor discussion messages
- Users created: `ciso`, `security.analyst`, `vendor.liaison`, `compliance.officer`, `devops.lead`, `network.admin`
- No remediation channel exists yet
- Baseline recorded: existing groups/channels, pentest alert message ID

## Goal / End State
1. Pentest alert message starred in `#security-alerts`
2. Private remediation channel `sec-remediation-2026-03-06` exists with correct topic
3. Remediation team (`ciso`, `security.analyst`, `vendor.liaison`, `compliance.officer`, `devops.lead`) invited
4. Vulnerability triage matrix posted with all 3 CVEs, CVSS scores, affected systems, and priority
5. Triage matrix message pinned
6. Thread reply on pentest alert in `#security-alerts` referencing the remediation channel
7. DM sent to `compliance.officer` about PCI-DSS notification requirements
8. DM sent to `vendor.liaison` requesting vendor security team contact for patches
9. Status update posted in the remediation channel about containment and vendor contacts

## Verification Strategy (10 criteria, 100 points, pass >= 70)

| ID  | Points | Criterion |
|-----|--------|-----------|
| C1  | 8      | Pentest alert message starred in #security-alerts |
| C2  | 10     | Private channel `sec-remediation-2026-03-06` exists (5 if public) |
| C3  | 10     | Topic contains Critical + at least 2 CVE numbers + deadline date |
| C4  | 15     | Required members invited (3 pts each x 5 members) |
| C5  | 12     | Vulnerability triage matrix with all 3 CVEs and CVSS scores |
| C6  | 7      | Triage matrix message pinned |
| C7  | 10     | Thread reply on pentest alert in #security-alerts |
| C8  | 10     | DM to compliance.officer about PCI-DSS/compliance/notification |
| C9  | 8      | DM to vendor.liaison about vendor contact/patch/PayStream/IdentityBridge |
| C10 | 10     | Status update in remediation channel about containment/vendor contacts |

### Do-nothing gate
If no remediation channel exists and no DMs, threads, or stars created, score = 0.

### Anti-gaming
- Baseline records existing channels to detect new work
- Thread reply is validated against the specific pentest alert message ID from setup
- Starred status checked via the starred messages API for the specific alert
- DM content checked for domain-specific keywords (PCI-DSS, PayStream, IdentityBridge)
- Status update must be distinct from the triage matrix message
- Pinned message verified to contain CVE references (confirming it is the triage matrix)

## Features Exercised
Star message, create private channel, set topic, invite members, post messages, pin message, thread reply, send DMs to multiple recipients (9 distinct features)

## Data Sources
- CVEs follow realistic CVSS scoring and vulnerability categories (SQL injection, auth bypass, insecure deserialization)
- Users represent real security incident response roles (CISO, Security Analyst, Vendor Liaison, Compliance Officer, DevOps Lead)
- Scenario reflects PCI-DSS compliance requirements for financial services vendor management
