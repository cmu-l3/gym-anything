# Task: Bank Account Reconciliation

## Overview

**Difficulty**: Hard
**Environment**: Manager.io (Northwind Traders business)
**Occupation Context**: Bookkeeper / Accountant performing bank reconciliation
**Features Used**: Bank/Cash Accounts, Journal Entries, Receipts, Payments, Reports

## Domain Context

Bank reconciliation is a fundamental monthly accounting task: comparing the accounting system's cash balance to the bank statement and recording any discrepancies (bank charges, unrecorded transfers, interest). This task requires understanding of double-entry bookkeeping, knowing how to record bank transfers between accounts in Manager.io, and how to handle charges not recorded in normal transactions.

This task is hard because:
- The agent must create a second bank account
- Inter-account transfers require manual journal entries in Manager.io
- Bank charges must be journaled against a specific expense account
- The agent must verify the final balance matches the corrected bank statement

## Task Description (as seen by agent)

"Northwind Traders needs to reconcile its Cash on Hand account and set up a new current account. Complete these tasks: (1) Create a new bank account called 'Business Checking Account'. (2) The Cash on Hand account currently has a balance from recorded transactions. The bank statement shows $35.00 in bank service charges that were not recorded — create a journal entry to record this: Debit 'Bank Charges' $35.00, Credit 'Cash on Hand' $35.00, narration 'Bank service charges — monthly'. (3) Transfer $5,000.00 from Cash on Hand to Business Checking Account by creating a journal entry: Debit 'Business Checking Account' $5,000.00, Credit 'Cash on Hand' $5,000.00, narration 'Inter-account transfer to business checking'. After completing all three, open the bank accounts list to verify both accounts are visible. Login: administrator (no password) at http://localhost:8080"

## Ground Truth

### Actions Required:

| Action | Detail |
|--------|--------|
| Create bank account | "Business Checking Account" |
| Journal entry 1 | Dr Bank Charges $35, Cr Cash on Hand $35 (bank fees) |
| Journal entry 2 | Dr Business Checking Account $5,000, Cr Cash on Hand $5,000 (transfer) |

### Why This Is Hard:
- Agent must navigate to bank accounts to create a new one
- Journal entries for bank operations require understanding that bank accounts appear in the chart of accounts
- Two separate but related journal entries required
- "Bank Charges" account may need to be created if not in default CoA

## Verification Strategy

### Scoring (100 points, pass ≥ 65):

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Business Checking Account created | 20 | bank-accounts page contains "Business Checking" |
| Bank charges JE $35 exists | 25 | journal-entries page: $35 in an entry with "charges" or "bank" in narration |
| Inter-account transfer JE $5,000 exists | 25 | journal-entries page: $5,000 in an entry |
| Both journal entries are balanced | 15 | amounts on both sides equal for each entry |
| Bank accounts list shows 2+ accounts | 15 | bank-accounts page has at least 2 accounts |

### Anti-Gaming:
- Initial bank account count and journal entry count saved in setup
- Verifier checks NEW bank accounts and journal entries only
- Wrong amount journal entries (e.g., $350 instead of $35) fail criterion

## Schema Reference

### Manager.io Bank Account JSON:
```json
{"Name": "Business Checking Account"}
```

### Manager.io Journal Entry for Bank Transfer:
```json
{
  "Date": "2026-03-02",
  "Narration": "Inter-account transfer to business checking",
  "Lines": [
    {"Account": "<business_checking_uuid>", "Dr": 5000.00},
    {"Account": "<cash_on_hand_uuid>", "Cr": 5000.00}
  ]
}
```

### Manager.io API Endpoints:
- `GET /bank-and-cash-accounts?{key}` — bank account list
- `GET /journal-entries?{key}` — journal entries with narration, amount
- `POST /bank-or-cash-account-form?{key}` — create bank account
- `POST /journal-entry-form?{key}` — create journal entry
