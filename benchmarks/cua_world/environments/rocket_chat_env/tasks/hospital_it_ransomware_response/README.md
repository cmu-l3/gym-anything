# Hospital IT Ransomware Response

## Occupation Context
**Computer and Information Systems Manager** (SOC importance: 98.0)
Hospital IT Managers are responsible for incident command during cyber events affecting clinical operations. NIMS/ICS principles require establishing formal incident command, coordinating clinical and IT stakeholders, protecting patient safety communications, and maintaining documented incident records.

## Task Overview
A ransomware attack is underway at Riverside Medical Center. LockBit indicators have been confirmed on EHR application servers. Three existing channels (`#clinical-it-alerts`, `#nursing-coordination`, `#it-security-ops`) contain escalating alerts from clinical staff, nursing, and IT security. The agent plays the IT Manager and must establish formal incident command without being told which channels to read, what to name the incident channel, or who to contact.

## Starting State
- Rocket.Chat running at `http://localhost:3000`
- `#clinical-it-alerts`: 4 seeded messages with escalating ransomware indicators (EHR latency → file encryption → LockBit confirmed)
- `#nursing-coordination`: 2 seeded messages from nursing staff about patient safety impact (paper downtime procedures)
- `#it-security-ops`: 3 seeded messages with EDR alerts, LockBit confirmation, FBI contact
- 8 users created: clinical.coordinator, it.security, nursing.supervisor, ciso, ehr.vendor.support, helpdesk.lead, biomedical.eng, network.admin
- No incident command channel exists yet
- Baseline recorded: all existing group names, 3 key seeded message IDs for thread verification

## Goal / End State
The agent must independently:
1. Read the existing alert channels to understand the situation
2. Create a private incident command channel (name at agent's discretion — must contain incident/security indicators)
3. Invite the correct stakeholders: clinical.coordinator, it.security, nursing.supervisor, ciso (minimum)
4. Post a structured incident declaration covering patient impact, affected systems, response status, and incident commander
5. Pin a key incident document (status message, declaration, or timeline)
6. Reply to threads on the critical alert messages in the existing channels
7. Send DMs to clinical.coordinator, it.security, and/or ciso with urgent coordination messages
8. Post a follow-up status update as the incident evolves

## Verification Strategy (8 criteria, 100 points, pass >= 60)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 15 | New private group found (scored via keyword matching on name/topic against incident terms) |
| C2 | 10 | Channel name or topic contains incident/security indicators |
| C3 | 15 | Required stakeholders invited (clinical.coordinator, it.security, nursing.supervisor, ciso — 5 pts each, max 15 shared among 4) |
| C4 | 15 | Structured declaration: contains patient impact + system impact + response/status + incident elements |
| C5 | 10 | Pinned message in incident channel |
| C6 | 15 | Thread replies on at least 2 of 3 seeded alert messages (7 pts each, max 15) |
| C7 | 10 | DMs to clinical.coordinator, it.security, or ciso (5 pts each, max 10) |
| C8 | 10 | Follow-up status update message (second substantive message in incident channel) |

### Do-nothing gate
If no new incident channel, no thread replies, and no DMs created, score = 0.

### Anti-gaming
- Baseline records all existing group names before setup completes; only groups created after baseline are evaluated
- Incident channel found by Python keyword scoring (not hardcoded name), resists guessing
- Thread verification uses specific seeded message IDs from baseline JSON
- DM check is against specific users (clinical.coordinator, it.security, ciso)

## Features Exercised
Read multiple channels, create private group, invite members, post structured message, pin message, thread replies (3 different channels), send DMs — 8 distinct Rocket.Chat features

## Data Sources
- Ransomware incident pattern based on real hospital IT incident command procedures (NIMS/ICS, HHS guidelines)
- LockBit indicators reflect documented attack patterns (not generated)
- Clinical workflow impact (EHR downtime, paper procedures) reflects real hospital IT incident scenarios
- FBI Cyber Division notification follows actual HIPAA breach + ransomware incident protocol

## Edge Cases
- Agent may use a public channel instead of private group — C1 awards partial credit (not full)
- Agent may only contact 2 of 4 required stakeholders — C3 awards partial credit proportionally
- Thread replies on 1 of 3 alert messages — C6 awards partial credit (3 pts vs 15 max)
- Very short messages not containing incident structure — C4 uses keyword matching with thresholds
