# Client Onboarding Handoff

## Occupation Context
**IT Project Manager** (Professional Services / Consulting)
Coordinating project handoffs from sales to delivery, setting up communication infrastructure, and ensuring cross-functional team alignment is a core PM responsibility.

## Task Overview
Sales has just closed a major enterprise deal with Meridian Health Systems, a 500-bed hospital network seeking a custom EHR integration platform. The signed SOW is for $2.4M over 18 months. The PM must set up project communication infrastructure, transfer key requirements from the sales briefing, and coordinate with the cross-functional delivery team.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#sales-handoffs` channel exists with seeded messages including a detailed client briefing for Meridian Health Systems
- `#delivery-standup` channel exists with some chatter
- Users created: `solutions.architect`, `account.manager`, `delivery.lead`, `ux.designer`, `data.engineer`, `client.sponsor`
- No `proj-meridian-internal` or `proj-meridian-client` channels exist yet
- Baseline recorded: existing groups/channels, briefing message ID

## Goal / End State
1. Private channel `proj-meridian-internal` exists with correct topic
2. Internal delivery team (`solutions.architect`, `delivery.lead`, `ux.designer`, `data.engineer`) invited
3. Project kickoff message posted with requirements from briefing (HL7/FHIR, risk factors, timeline)
4. Kickoff message pinned
5. Public channel `proj-meridian-client` exists with correct topic
6. Client channel members invited (`solutions.architect`, `delivery.lead`, `account.manager`, `client.sponsor`)
7. Welcome message in client channel mentioning project/team/kickoff
8. Thread reply on briefing message in `#sales-handoffs` confirming handoff
9. DM sent to `solutions.architect` about HL7 FHIR technical assessment and legacy lab API gap

## Verification Strategy (10 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 10 | Private channel `proj-meridian-internal` exists |
| C2 | 8 | Internal channel topic contains "Meridian" and "$2.4M" or "EHR" or "Discovery" |
| C3 | 12 | Internal delivery team members invited (solutions.architect, delivery.lead, ux.designer, data.engineer) - 3pts each |
| C4 | 15 | Kickoff message with HL7/FHIR + risk factor (legacy lab or Cerner) + timeline reference |
| C5 | 5 | Kickoff message pinned |
| C6 | 8 | Public channel `proj-meridian-client` exists |
| C7 | 10 | Client channel members invited (solutions.architect, delivery.lead, account.manager, client.sponsor) - partial credit |
| C8 | 8 | Welcome message in client channel mentioning project/team/kickoff |
| C9 | 10 | Thread reply on briefing message in #sales-handoffs confirming handoff |
| C10 | 14 | DM to solutions.architect about technical assessment / HL7 FHIR / legacy lab API |

### Do-nothing gate
If no internal channel exists and no DMs/threads created, score = 0.

### Anti-gaming
- Baseline records existing channels to detect new work
- Thread reply is validated against the specific briefing message ID from setup
- DM content checked for HL7/FHIR/legacy/assessment keywords
- Kickoff message must reference content from the seeded briefing

## Features Exercised
Create private channel, create public channel, set topics, invite members, post messages, pin message, thread reply, send DM (8 distinct features)

## Data Sources
- Client briefing follows real enterprise deal handoff patterns
- Users represent real consulting team roles (Solutions Architect, Account Manager, Delivery Lead, UX Designer, Data Engineer, Client Sponsor)
