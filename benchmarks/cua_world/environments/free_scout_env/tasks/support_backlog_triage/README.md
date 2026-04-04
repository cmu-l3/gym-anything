# Support Backlog Triage

## Overview

**Difficulty**: Hard
**Occupation**: Customer Success Manager (tech company)
**Timeout**: 720 seconds | **Max steps**: 80

A realistic backlog management task. The agent must identify conversations that have never been responded to (requiring inspection of thread history for each), tag and assign them, add internal notes, reopen mistakenly-closed tickets, reply to a specific conversation, and assign it to an agent. The hardest part is discovering which conversations have no agent threads — this requires navigating through conversations, not just reading a list.

## Pre-Existing State (seeded in setup_task.sh)

**Mailbox**: General Support (general@helpdesk.local)

**10 conversations seeded:**
- 4 active conversations with NO agent replies (only customer-opened threads):
  - "Software installation failure" — Jacqueline Wright
  - "Refund request not processed" — Denise Lee
  - "Account login not working" — Sandra Barnes
  - "Subscription renewal error" — Amy Hill
- 3 active conversations WITH agent replies (already responded):
  - "Billing overcharge inquiry" — Joseph Moreno
  - "Password reset not received" — Brandon Arnold
  - "Shipping delay concern" — (seeded agent reply for each)
- 3 CLOSED conversations (mistakenly closed):
  - "Product defect report" — William Dawson
  - "Invoice discrepancy" — Christina Dillon
  - "Warranty claim pending" — Alexander Carroll

**Pre-existing agents**: Admin User + Derek Thompson (derek.thompson@helpdesk.local)

## Required End State

1. The 4 unresponded conversations tagged `awaiting-first-response` and assigned to Admin User
2. Internal note "Priority: requires first response within 24 hours" on each of those 4 conversations
3. The 3 closed conversations changed to Active status
4. The "Software installation failure" conversation has an agent reply with specified content
5. The "Software installation failure" conversation assigned to Derek Thompson

## Verification Criteria (100 points)

| Criterion | Points |
|-----------|--------|
| Correct count of conversations tagged "awaiting-first-response" (4) | 25 |
| Those 4 conversations assigned to Admin User | 20 |
| Internal notes present on those conversations | 15 |
| 3 closed conversations reopened to Active | 15 |
| "Software installation failure" replied with correct content | 15 |
| "Software installation failure" assigned to Derek Thompson | 10 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Why This Is Hard

- The agent cannot simply see a list of "unresponded" conversations — they must navigate into each conversation to check if any agent replies exist
- The agent must recognize the difference between customer threads and agent threads
- The task spans 5 independent sub-goals requiring navigation through different parts of the UI
- Adding internal notes requires knowing they are different from public replies

## Data Source

Customer names from the Kaggle Customer Support Ticket Dataset (chiapudding/kaggle-customer-service).
