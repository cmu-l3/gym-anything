# Enterprise Support Onboarding

## Overview

**Difficulty**: Hard
**Occupation**: Customer Support Operations Manager (SaaS company)
**Timeout**: 720 seconds | **Max steps**: 75

A realistic multi-step task requiring an agent to configure FreeScout for a new enterprise support tier. The task spans six distinct feature areas: mailbox creation, user management, permission configuration, saved reply creation, conversation tagging, and conversation assignment. No UI path is provided—the agent must discover how to accomplish each goal independently.

## Background

The company has signed enterprise contracts requiring a dedicated support channel. The help desk must be set up to route enterprise traffic separately, ensure two new agents can handle it, and triage existing conversations across two other mailboxes.

## Pre-Existing State (seeded in setup_task.sh)

- **Mailbox 1**: "Technical Support" (techsupport@helpdesk.local) with 5 conversations (customers: Marisa Obrien, Jessica Rios, Christopher Robbins, Nicolas Wilson, Tamara Hahn)
- **Mailbox 2**: "Billing Support" (billing@helpdesk.local) with 3 conversations (customers: Christina Dillon, Alexander Carroll, William Dawson)
- **Pre-existing agent**: Sarah Mitchell (sarah.mitchell@helpdesk.local, role: User) — already has access to Billing Support only

## Required End State

1. **Enterprise Support mailbox** created with email `enterprise@helpdesk.local`
2. **James Kowalski** created: email `james.kowalski@helpdesk.local`, role: User
3. **Priya Sharma** created: email `priya.sharma@helpdesk.local`, role: User
4. **James Kowalski** has mailbox access to both "Technical Support" AND "Enterprise Support"
5. **Priya Sharma** has mailbox access to "Enterprise Support" only
6. **Saved reply** named "Enterprise Acknowledgment" exists with body containing the enterprise acknowledgment text
7. All 5 conversations in Technical Support tagged with **"technical"**
8. All 3 conversations in Billing Support **assigned to Sarah Mitchell**

## Verification Criteria (100 points)

| Criterion | Points |
|-----------|--------|
| Enterprise Support mailbox created | 15 |
| James Kowalski created with correct role | 10 |
| Priya Sharma created with correct role | 10 |
| James has access to Technical Support + Enterprise Support (both) | 15 |
| Saved reply "Enterprise Acknowledgment" exists | 15 |
| All 5 Technical Support conversations tagged "technical" | 20 |
| All 3 Billing Support conversations assigned to Sarah Mitchell | 15 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Data Source

Customer names and emails from the Kaggle Customer Support Ticket Dataset (chiapudding/kaggle-customer-service).

## Anti-Gaming Notes

- Baseline counts recorded before task; new users and mailboxes must be created *after* task start
- Timestamp comparison uses integer comparison to avoid sub-second false positives
- Tag verification counts how many of the 5 Technical conversations actually have the tag
- Assignment verification checks all 3 Billing conversations are assigned to Sarah Mitchell specifically (not just any agent)
