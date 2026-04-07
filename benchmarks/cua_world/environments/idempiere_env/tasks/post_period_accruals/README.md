# Task: Post Period-End Accrual Journal Entries

## Overview

At the end of March 2026, GardenWorld's accountant must record two accrual journal entries in the General Ledger: one for rent expense and one for wages. These are standard period-end accruals — costs incurred in March that have not yet been paid in cash.

This task tests the agent's ability to navigate iDempiere's GL Journal module, create a journal batch with multiple journals, enter balanced debit/credit lines using the correct account codes, and complete/post the batch.

## Goal

Create two GL journal entries in a single batch, both posted (Completed status):

**Journal 1 — Rent Expense Accrual:**
| Account | Code | DR | CR |
|---------|------|----|----|
| Rent Expense | 61100 | $3,200.00 | |
| Accounts Payable Trade | 21100 | | $3,200.00 |

Description: `March 2026 Rent Accrual`

**Journal 2 — Wages Accrual:**
| Account | Code | DR | CR |
|---------|------|----|----|
| Wages | 60110 | $8,500.00 | |
| Accrued Payroll | 22100 | | $8,500.00 |

Description: `March 2026 Wages Accrual`

## Credentials

- **URL**: https://localhost:8443/webui/
- **User**: GardenAdmin
- **Password**: GardenAdmin

## Success Criteria

- At least 2 new GL journals created after task start, both with docstatus=CO
- Rent journal: has DR line for account 61100 ($3,200 ±$10) and CR line for account 21100 ($3,200 ±$10)
- Wages journal: has DR line for account 60110 ($8,500 ±$50) and CR line for account 22100 ($8,500 ±$50)

## Verification Strategy

**Scoring (100 points):**
- Rent accrual journal created and posted (CO): 20 points
- Rent journal debit line correct (61100 = $3,200): 15 points
- Rent journal credit line correct (21100 = $3,200): 15 points
- Wages accrual journal created and posted (CO): 20 points
- Wages journal debit line correct (60110 = $8,500): 15 points
- Wages journal credit line correct (22100 = $8,500): 15 points

Pass threshold: 70 points

## Schema Reference

- `gl_journalbatch` — GL batch header
- `gl_journal` — individual journal entries (docstatus='CO' = posted)
- `gl_journalline` — DR/CR lines (account_id, amtacctdr, amtacctcr)
- Account IDs: Rent Expense (61100) = 474, AP Trade (21100) = 749, Wages (60110) = 772, Accrued Payroll (22100) = 602

## Key Challenge

GL Journals in iDempiere are in a separate module (Finance → GL Journal or Accounting → GL Journal). The agent must create a batch, then add individual journals to it, then for each journal add a debit line and a credit line with the correct account codes. All journals must be completed (posted) for the period to be closed. The agent must navigate the batch/journal/line hierarchy without step-by-step UI guidance.
