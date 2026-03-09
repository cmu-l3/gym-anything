# Client Churn Risk Escalation

## Occupation Context
**Sales Manager / Senior Account Manager** (SOC importance: 94.0)
Account Managers at B2B SaaS companies are responsible for managing renewal risk. When a high-value enterprise account threatens to churn, the AM must diagnose the root causes, coordinate an internal response across sales/CS/product/engineering/executive, and drive a retention plan — all within business-day urgency.

## Task Overview
Meridian Financial Group ($1.2M ARR, 47 days to renewal) has called the Customer Success Manager to express intent to evaluate alternatives. Their VP of Operations cited 200 hours of ops team workarounds, two unresolved Sev-1 support tickets, and three delayed product commitments. The `#customer-success` and `#sales-enterprise` channels contain the full context. The agent plays the Senior Account Manager and must own the escalation: build an internal war room, coordinate all stakeholders, and drive the four conditions Meridian requires to stay — without being told which channel to read, who to contact, or what the retention plan should contain.

## Starting State
- Rocket.Chat running at `http://localhost:3000`
- `#customer-success`: 4 seeded messages:
  - Health score alert: Meridian at RED (23/100), 11 days since last login
  - VP of Operations call note (Diana Walsh): "We are evaluating alternatives", direct quote, renewal in 47 days
  - Design partner context: 3 of 5 Q3 roadmap promises delayed to Q2 next year
  - Exact retention conditions: (1) Sev-1 tickets P1-4821 + P1-4898 resolved in 48h, (2) CTO roadmap letter, (3) 2-3 month service credit, (4) CEO-to-CEO call before March 14 board
- `#sales-enterprise`: 2 seeded messages (competitive intel: Meridian in demos with DataOps Pro)
- `#product-feedback`: 1 seeded message (14 feedback items, 3 delayed features identified)
- 7 users: cs.manager, vp.sales, cto.internal, product.lead, exec.sponsor (CEO), support.lead, solutions.eng
- Baseline recorded: all existing group names, 2 key CS message IDs for thread verification

## Goal / End State
The agent must independently:
1. Read `#customer-success`, `#sales-enterprise`, `#product-feedback` to understand the situation
2. Create an internal escalation channel for Meridian coordination
3. Engage all four core stakeholders: cs.manager, vp.sales, cto.internal, exec.sponsor (CEO)
4. Reply to threads on the CS channel messages acknowledging the situation
5. Draft retention plan covering all four Meridian conditions (tickets, roadmap, credit, exec call)
6. Contact the executive sponsor (exec.sponsor) directly with urgent framing
7. Engage product/CTO about roadmap commitment requirements (cto.internal or product.lead)
8. Notify support lead (support.lead) about P1 ticket SLA requirements

## Verification Strategy (8 criteria, 100 points, pass >= 60)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 10 | Internal escalation channel created (keyword match: meridian, escalat, churn, retent, renewal) |
| C2 | 15 | Core stakeholders engaged: cs.manager, vp.sales, cto.internal, exec.sponsor (4pts each) |
| C3 | 15 | Thread replies on CS channel messages (2 messages with critical context) |
| C4 | 15 | Retention plan addresses 2+ of 4 conditions (tickets, roadmap, credit, exec call) |
| C5 | 10 | Executive sponsor (exec.sponsor/CEO Robert) contacted via DM or channel |
| C6 | 15 | Product/engineering (cto.internal or product.lead) engaged for roadmap commitments |
| C7 | 10 | Business impact language present (ARR, renewal, board, churn, Q2, competitive) |
| C8 | 10 | Support lead notified about P1 ticket resolution with ticket references |

### Do-nothing gate
If no escalation channel, no thread replies, no DMs, and no CS channel admin messages: score = 0.

### Anti-gaming
- Baseline records all groups; only agent-created groups are evaluated as escalation channels
- Thread verification uses specific seeded CS message IDs
- Retention plan scoring requires content from at least 2 of 4 distinct retention elements

## Features Exercised
Read 3 different channels to piece together situation, create private escalation channel, engage 6+ different stakeholders via DMs and channel invites, thread replies, post structured retention plan — 7+ distinct Rocket.Chat features

## Data Sources
- Churn scenario follows real enterprise SaaS account management patterns (health score, CSM escalation path)
- Retention conditions (SLA resolution, roadmap commitment letter, service credits, exec-to-exec call) are standard B2B SaaS retention practices
- Sev-1 ticket descriptions (bulk export, SSO failure) are real enterprise software pain points
- Competitive intel context (Vanta, DataOps Pro) reflects real B2B SaaS competitive landscape patterns
- ARR ($1.2M) and renewal timing (47 days) represent realistic enterprise account parameters
