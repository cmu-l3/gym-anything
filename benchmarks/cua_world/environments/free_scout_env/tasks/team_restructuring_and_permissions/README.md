# Team Restructuring and Permissions

## Overview

**Difficulty**: Hard
**Occupation**: IT Operations Director (growing tech company)
**Timeout**: 720 seconds | **Max steps**: 80

A high-complexity task simulating a real department reorganization. The agent must create a new mailbox, modify mailbox access permissions for two existing agents (adding and removing access), create a saved reply template, move VIP-tagged conversations to the new mailbox, and assign them to the newly designated agent. This task requires deep navigation through FreeScout's admin settings, agent management, and conversation management.

## Pre-Existing State (seeded in setup_task.sh)

**Mailboxes:**
- General Support (general@helpdesk.local)
- Technical Support (techsupport@helpdesk.local)
- Billing Support (billing@helpdesk.local)

**Agents (pre-seeded):**
- Alex Chen (alex.chen@helpdesk.local, role: User) — currently has access to General Support, Technical Support, AND Billing Support
- Maria Rodriguez (maria.rodriguez@helpdesk.local, role: User) — currently has access to General Support ONLY

**Conversations tagged 'vip' (4 total):**
- "Premium account migration request" — in General Support
- "Enterprise API integration issue" — in General Support
- "SLA breach complaint" — in Technical Support
- "Data export request" — in Technical Support

**Other conversations (untagged, 3 total):**
- "Standard billing inquiry" — in Billing Support
- "General product question" — in General Support
- "Password reset issue" — in Technical Support

## Required End State

1. VIP Support mailbox created (vip@helpdesk.local)
2. Alex Chen: removed from Billing Support, added to VIP Support
3. Maria Rodriguez: added to Technical Support AND VIP Support
4. Saved reply "VIP Priority Response" created with specified content
5. All 4 VIP-tagged conversations moved to VIP Support mailbox
6. All VIP Support conversations assigned to Alex Chen

## Verification Criteria (100 points)

| Criterion | Points |
|-----------|--------|
| VIP Support mailbox created | 15 |
| Alex removed from Billing + added to VIP Support | 15 |
| Maria added to Technical + VIP Support | 15 |
| Saved reply "VIP Priority Response" created | 15 |
| VIP-tagged conversations moved to VIP Support (partial credit) | 25 |
| VIP Support conversations assigned to Alex Chen | 15 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Why This Is Hard

- Permission modification requires navigating to admin settings → users → edit → mailbox access for each agent
- "Remove" access is a distinct action from "grant" access — easy to miss
- Moving conversations between mailboxes is a less obvious feature
- The "VIP-tagged conversations" are spread across two mailboxes, requiring the agent to search/filter
- Steps 5 and 6 depend on step 1 (VIP mailbox must exist before conversations can be moved)

## Data Source

Customer names from the Kaggle Customer Support Ticket Dataset (chiapudding/kaggle-customer-service).
