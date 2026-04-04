# Support Operations Cleanup

## Overview

**Difficulty**: Very Hard (Discovery-Based)
**Occupation**: Head of Customer Support Operations (SaaS company — Horizon Digital)
**Timeout**: 900 seconds | **Max steps**: 90

A high-complexity, discovery-based task. The agent inherits a disorganized helpdesk and must independently identify misrouted conversations by reading their content, fix agent permission misassignments, assign unattended conversations to the correct agents, and set up new infrastructure (saved reply + tag). There are no explicit pointers to what is wrong — the agent must audit, reason, and act.

## Pre-Existing State (seeded in setup_task.sh)

**Mailboxes:**
- Customer Success (cs@helpdesk.local)
- Technical Support (techsupport@helpdesk.local)
- Sales Inquiries (sales@helpdesk.local)

**Agents (pre-seeded with incorrect access):**
- Raj Patel (raj.patel@helpdesk.local) — currently has access to: Technical Support + **Sales Inquiries** (Sales access should be removed)
- Nina Kovacs (nina.kovacs@helpdesk.local) — has access to: Customer Success (correct)
- Ben Harris (ben.harris@helpdesk.local) — has access to: Sales Inquiries only (should also have Customer Success)

**Technical Support conversations (4):**
| Subject | Status | Issue |
|---------|--------|-------|
| Webhook authentication failure | Unassigned, no reply | Correct mailbox |
| Database connection timeout in production | Unassigned, no reply | Correct mailbox |
| Enterprise license pricing inquiry | Unassigned, no reply | **WRONG — belongs in Sales Inquiries** |
| Reseller partnership program inquiry | Unassigned, no reply | **WRONG — belongs in Sales Inquiries** |

**Customer Success conversations (2):**
| Subject | Status | Issue |
|---------|--------|-------|
| Account upgrade to Enterprise tier | Unassigned, no reply | Correct mailbox |
| New client onboarding assistance | Unassigned, no reply | Correct mailbox |

**Sales Inquiries conversations (4):**
| Subject | Status | Issue |
|---------|--------|-------|
| Custom pricing quote for startup bundle | Unassigned, no reply | Correct mailbox, no reply → tag |
| Annual renewal options and discounts | Unassigned, no reply | Correct mailbox, no reply → tag |
| Invoice discrepancy - overcharge on subscription | Unassigned, no reply | **WRONG — belongs in Customer Success** |
| Team plan upgrade pricing comparison | Agent replied | Correct mailbox, HAS reply → do NOT tag |

## Required End State

1. **Misrouted conversations moved:**
   - "Enterprise license pricing inquiry" → Sales Inquiries
   - "Reseller partnership program inquiry" → Sales Inquiries
   - "Invoice discrepancy - overcharge on subscription" → Customer Success
2. **Raj Patel**: Sales Inquiries access removed; Technical Support access retained
3. **Ben Harris**: Customer Success access added (retains Sales Inquiries)
4. **Technical Support unassigned convs**: Both assigned to Raj Patel
5. **Customer Success unassigned convs**: Both assigned to Nina Kovacs
6. **Saved reply "Sales Inquiry Acknowledgment"** created with appropriate body
7. **Tag "needs-follow-up"** applied to all Sales Inquiries conversations with no agent reply (4 after moves)

## Verification Criteria (100 points)

| Criterion | Points |
|-----------|--------|
| 2 Tech Support convs moved to Sales Inquiries (partial credit) | 15 |
| 1 Sales Inquiries conv moved to Customer Success | 10 |
| Raj's Sales Inquiries access removed | 10 |
| Ben's Customer Success access added | 10 |
| Unassigned Tech Support convs assigned to Raj (partial credit) | 15 |
| Unassigned Customer Success convs assigned to Nina (partial credit) | 10 |
| Saved reply "Sales Inquiry Acknowledgment" created | 15 |
| needs-follow-up tag applied to Sales convs without replies (partial credit) | 15 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Why This Is Very Hard

- Agent must **discover** misrouted conversations by reading content (no explicit list given)
- Identification requires understanding business context: what belongs in "Technical Support" vs "Sales Inquiries" vs "Customer Success"
- Permission changes require navigating to admin → users → each agent to make removals AND additions
- Finding "unassigned" conversations requires filtering each mailbox
- The "needs-follow-up" tag step requires identifying conversations WITHOUT agent replies — less obvious than other filtering
- One Sales conversation ("Team plan upgrade pricing comparison") already HAS an agent reply and should NOT be tagged — agent must check carefully
- 7 distinct action categories with high step count

## Data Source

Customer names and email addresses from the Kaggle Customer Support Ticket Dataset (chiapudding/kaggle-customer-service).
