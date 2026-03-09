# OSS CVE Disclosure Coordination

## Occupation Context
**Information Security Analyst** (SOC importance: 91.0)
Security analysts at open source foundations are responsible for coordinating responsible disclosure of vulnerabilities in widely-used libraries. This involves private coordination with maintainers and downstream consumers under embargo before public disclosure — a multi-party, time-sensitive workflow that requires precise communication and process adherence.

## Task Overview
A critical heap buffer overflow (CVSS 9.8) has been privately reported in `libparse` v2.x, a widely-used developer infrastructure library. The vulnerability affects versions 2.0.0–2.14.3. Initial triage notes in `#security-triage` identify known downstream consumers at risk (TechFlow Enterprise, CloudScale, OpenDistro). The agent plays the Security Lead and must manage the full responsible disclosure workflow: private patch coordination with maintainers, embargo notifications to downstream consumers, timeline agreement with the researcher, and advisory documentation — without being told which channel to read or what steps to follow.

## Starting State
- Rocket.Chat running at `http://localhost:3000`
- `#security-triage`: 4 seeded messages:
  - HackerOne report with PoC details (heap overflow, YAML deserialization, yaml_parser.c:847-923)
  - Full triage assessment: CVSS 9.8, affected versions, downstream consumers identified
  - Foundation counsel advisory notice with disclosure policy requirements
  - Timeline proposal: patch ready 2026-03-10, public disclosure 2026-03-12 14:00 UTC
- `#foundation-security-general`: 1 seeded message with disclosure policy summary
- 9 users: security.researcher, core.maintainer, release.manager, lib.author, enterprise.consumer, cloud.vendor, distro.maintainer, foundation.counsel, security.lead.internal
- Baseline recorded: all existing group names, 2 key triage message IDs for thread verification

## Goal / End State
The agent must independently:
1. Read `#security-triage` to understand the situation (vulnerability, consumers, timeline)
2. Create a private coordination channel for the disclosure process (name at agent's discretion)
3. Invite the three core maintainers (core.maintainer, release.manager, lib.author)
4. Notify the three downstream consumers under embargo (enterprise.consumer, cloud.vendor, distro.maintainer)
5. Contact the security researcher (security.researcher) with acknowledgment and timeline
6. Specify the disclosure timeline in coordination content
7. Coordinate patch review process (branch, review, testing references)
8. Reference CVE/advisory documentation requirements

## Verification Strategy (8 criteria, 100 points, pass >= 60)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 15 | Private coordination channel created (scored by keyword matching against embargo/cve/disclosure terms) |
| C2 | 15 | All three maintainers engaged (core.maintainer, release.manager, lib.author in channel or DM'd) |
| C3 | 15 | Downstream consumers notified (enterprise.consumer, cloud.vendor, distro.maintainer — 5pts each) |
| C4 | 10 | Security researcher contacted via DM with acknowledgment/timeline |
| C5 | 15 | Disclosure timeline specified (embargo date, 2026-03, deadline, coordinated release language) |
| C6 | 10 | Thread replies on triage messages showing active coordination |
| C7 | 10 | Patch review coordination (patch, review, branch, merge, test keywords) |
| C8 | 10 | Advisory/CVE documentation referenced (cve, advisory, mitre, cvss, credit) |

### Do-nothing gate
If no coordination channel, no thread replies, and no DMs: score = 0.

### Anti-gaming
- Baseline records all groups before task; only agent-created groups are evaluated
- Thread verification uses specific seeded triage message IDs
- Downstream consumer notification requires DM or channel membership — not just text mentions

## Features Exercised
Read multiple channels, create private group (embargo), invite internal maintainers, send external DMs to downstream consumers, thread replies, send DM to researcher — 6+ distinct Rocket.Chat features

## Data Sources
- Vulnerability details (heap overflow in YAML deserialization, CVSSv3.1 scoring) follow real CVE report structure
- Disclosure policy requirements follow CERT/CC and GitHub Security Advisory standards
- Library names and downstream consumers reflect real open source ecosystem patterns
- Timeline (7-day embargo, simultaneous patch + advisory release) follows industry-standard responsible disclosure
