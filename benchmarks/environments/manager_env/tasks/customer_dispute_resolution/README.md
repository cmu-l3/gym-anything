# Task: Customer Dispute Resolution

## Overview

**Difficulty**: Hard
**Environment**: Manager.io (Northwind Traders business)
**Occupation Context**: Accounts Receivable Clerk / Bookkeeper
**Features Used**: Customers, Sales Invoices, Receipts, Credit Notes, Reports (Aged Receivables)

## Domain Context

AR clerks routinely handle customer invoice disputes — issuing credit notes for wrong goods or overcharges, and allocating unmatched receipts to outstanding invoices. This is a core accounts-receivable workflow for any product-based business.

Real Northwind Traders customers:
- **Alfreds Futterkiste** (Berlin, Germany) — long-standing customer
- **Ernst Handel** (Graz, Austria) — regular beverage buyer

## Task Description (as seen by agent)

"Alfreds Futterkiste and Ernst Handel have raised invoice disputes that must be resolved before month-end close. Alfreds is rejecting invoice INV-A002 entirely because the wrong products were shipped — issue a full credit note for $600.00. Alfreds also has an overcharge of $60.00 on invoice INV-A003 due to a pricing error — issue a partial credit note for $60.00. Ernst Handel made a payment of $450.00 that was received into Cash on Hand but has not yet been allocated to any invoice — allocate this receipt to invoice INV-E002. After resolving all three issues, check the Aged Receivables report to confirm the updated customer balances. Login: administrator (no password) at http://localhost:8080"

## Ground Truth

### Invoices Created in Setup:

| Customer | Invoice Ref | Amount | Issue |
|----------|-------------|--------|-------|
| Alfreds Futterkiste | INV-A002 | $600.00 | Wrong products — fully rejected |
| Alfreds Futterkiste | INV-A003 | $180.00 | $60 overcharge — partial credit |
| Ernst Handel | INV-E001 | $1,200.00 | No issue — normal outstanding |
| Ernst Handel | INV-E002 | $450.00 | Receipt exists but unallocated |

### Receipt Created in Setup:
- Ernst Handel: $450.00, received into Cash on Hand, UNALLOCATED (agent must allocate to INV-E002)

### Expected Final Balances:
- Alfreds: $120.00 (INV-A003 $180 minus $60 credit = $120; INV-A002 zeroed out)
- Ernst: $1,200.00 (INV-E001 still outstanding; INV-E002 cleared by receipt)

## Verification Strategy

### Scoring (100 points, pass ≥ 65):

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Credit note for Alfreds ~$600 | 25 | credit-notes page has $600 near "Alfreds" |
| Credit note for Alfreds ~$60 | 25 | credit-notes page has $60 near "Alfreds" |
| Receipt allocated (Ernst INV-E002 cleared) | 25 | sales invoices page: INV-E002 shows $0 outstanding OR receipts page shows Ernst $450 allocated |
| Aged Receivables viewed (report accessed) | 25 | verifier checks screenshot timestamp or report page was loaded |

### Anti-Gaming:
- Initial credit note count saved; verifier checks NEW credit notes only
- Wrong customer credit notes (e.g., issuing credit to Ernst for Alfreds' dispute) fails criterion
- Wrong amount credit notes (e.g., $600 for Alfreds A003 instead of $60) scored separately

## Schema Reference

### Manager.io API Endpoints:
- `GET /credit-notes?{key}` — credit note list with customer, amount, reference
- `GET /receipts?{key}` — receipt list with payer, amount, bank account
- `GET /sales-invoices?{key}` — invoice list with customer, amount outstanding
- `GET /customers?{key}` — customer list with outstanding balances

### Amounts Used in Setup:
- INV-A002: Products from Alfreds' order of specialty beverages, total $600.00
- INV-A003: Mixed food items order, total $180.00 ($60 pricing error)
- INV-E001: Ernst's standard beverage order, total $1,200.00
- INV-E002: Smaller beverage supplemental order, total $450.00
