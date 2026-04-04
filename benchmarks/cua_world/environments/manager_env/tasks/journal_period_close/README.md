# Task: Journal Entry Period Close

## Overview

**Difficulty**: Hard
**Environment**: Manager.io (Northwind Traders business)
**Occupation Context**: Accountant / Bookkeeper performing month-end close
**Features Used**: Journal Entries, Reports (Trial Balance / Balance Sheet)

## Domain Context

At the end of each accounting period, accountants must record adjusting journal entries for items not captured in normal transactions: depreciation of fixed assets, recognition of prepaid expenses, and accrual of wages or other obligations. These entries require knowledge of double-entry bookkeeping (debits must equal credits) and require navigating the chart of accounts to find or create appropriate accounts.

This task is genuinely hard because:
- The agent must navigate the Chart of Accounts to find correct account names
- The agent must create accounts if they don't exist (e.g., "Depreciation Expense")
- Each journal entry must be balanced (total debits = total credits)
- Three independent entries must be created correctly

## Task Description (as seen by agent)

"Northwind Traders needs to record three adjusting journal entries for the period ending on the last day of the current month. Create the following entries: (1) Depreciation: Debit 'Depreciation Expense' $450.00, Credit 'Accumulated Depreciation' $450.00, narration 'Monthly depreciation — office equipment'. (2) Prepaid insurance recognition: Debit 'Insurance Expense' $300.00, Credit 'Prepaid Insurance' $300.00, narration 'Monthly insurance expense recognition'. (3) Accrued wages payable: Debit 'Wages Expense' $2,400.00, Credit 'Wages Payable' $2,400.00, narration 'Accrued wages for period end'. All entries should be dated the last day of the current month. After creating the entries, open the Balance Sheet report and verify the entries are reflected in the system. Login: administrator (no password) at http://localhost:8080"

## Ground Truth

### Journal Entries to Create:

| # | Debit Account | Credit Account | Amount | Narration |
|---|---------------|----------------|--------|-----------|
| JE-1 | Depreciation Expense | Accumulated Depreciation | $450.00 | Monthly depreciation — office equipment |
| JE-2 | Insurance Expense | Prepaid Insurance | $300.00 | Monthly insurance expense recognition |
| JE-3 | Wages Expense | Wages Payable | $2,400.00 | Accrued wages for period end |

### Why This Is Hard:
- Manager.io's default chart of accounts may not include all required accounts
- Agent must discover which accounts exist and create missing ones
- Three separate, balanced entries required
- Entry dates must be end-of-month

## Verification Strategy

### Scoring (100 points, pass ≥ 65):

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| JE-1 depreciation $450 exists and is balanced | 25 | journal-entries page: $450 in an entry |
| JE-2 insurance $300 exists and is balanced | 25 | journal-entries page: $300 in an entry |
| JE-3 wages $2,400 exists and is balanced | 25 | journal-entries page: $2,400 in an entry |
| Total journal entry count increased by ≥ 3 | 15 | count delta from baseline |
| Balance Sheet or Trial Balance accessed | 10 | screenshot taken after report load |

### Anti-Gaming:
- Initial journal entry count saved; verifier checks NEW entries only
- Each entry checked for specific amount independently
- Entries checked for balanced debits/credits (equal amounts on both sides)

## Schema Reference

### Manager.io Journal Entry JSON:
```json
{
  "Date": "2026-03-31",
  "Narration": "Monthly depreciation — office equipment",
  "Lines": [
    {"Account": "<account-uuid>", "Dr": 450.00},
    {"Account": "<account-uuid>", "Cr": 450.00}
  ]
}
```

### Manager.io API Endpoints:
- `GET /journal-entries?{key}` — journal entry list with date, narration, amount
- `GET /reports?{key}` — reports page (Balance Sheet, Trial Balance)
- `GET /chart-of-accounts?{key}` or similar — chart of accounts

### Common Manager.io Default Accounts:
Standard accounts typically include: Sales, Purchases, Cash, Accounts Receivable, Accounts Payable, Retained Earnings. Expense-specific accounts may need to be created by the agent.
