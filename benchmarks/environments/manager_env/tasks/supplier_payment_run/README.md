# Task: Supplier Payment Run

## Overview

**Difficulty**: Very Hard
**Environment**: Manager.io (Northwind Traders business)
**Occupation Context**: Accounts Payable Clerk / Bookkeeper
**Features Used**: Suppliers, Purchase Invoices, Payments, Debit Notes, Reports (Aged Payables)

## Domain Context

Bookkeeping and accounts-payable clerks regularly perform supplier payment runs — reviewing all outstanding purchase invoices, identifying which are overdue, applying any agreed supplier credits (debit notes), and processing payment. This is one of the most economically important recurring workflows in any small business using accounting software.

Real Northwind Traders suppliers featured:
- **Pavlova, Ltd.** (Melbourne, Australia) — supplier of Pavlova, Alice Mutton
- **Specialty Biscuits, Ltd.** (Manchester, UK) — Teatime Chocolate Biscuits
- **Grandma Kelly's Homestead** (Ann Arbor, MI, USA) — Boysenberry Spread, Cranberry Sauce
- **Exotic Liquids** (London, UK) — already in system, Chai Tea

## Task Description (as seen by agent)

"Northwind Traders has fallen behind on supplier payments and suppliers are threatening to suspend credit. Complete the overdue payment run: identify all outstanding purchase invoices, process payments for any invoice that is more than 30 days old (based on invoice date), and handle any agreed supplier credits before settlement. Note that Pavlova, Ltd. has a credit of $200.00 due for a damaged batch — this must be recorded as a debit note and applied before settling their account. Process all overdue payments from the Cash on Hand bank account. Login: administrator (no password) at http://localhost:8080"

## Ground Truth

### Invoices Created in Setup (agent must discover these):

| Supplier | Invoice Ref | Age | Amount | Due? |
|----------|-------------|-----|--------|------|
| Pavlova, Ltd. | PI-PAV-001 | 40 days | $1,520.00 | YES |
| Pavlova, Ltd. | PI-PAV-002 | 12 days | $875.00 | NO |
| Specialty Biscuits, Ltd. | PI-SB-001 | 35 days | $2,430.00 | YES |
| Grandma Kelly's Homestead | PI-GK-001 | 45 days | $1,890.00 | YES |
| Exotic Liquids | PI-EL-001 | 5 days | $1,080.00 | NO |

### Expected Agent Actions:
1. Create debit note for Pavlova, Ltd. → $200.00
2. Pay Pavlova, Ltd. → $1,320.00 (= $1,520 − $200 debit note)
3. Pay Specialty Biscuits, Ltd. → $2,430.00
4. Pay Grandma Kelly's Homestead → $1,890.00
5. Do NOT pay PI-PAV-002 ($875) or PI-EL-001 ($1,080)

## Verification Strategy

### Scoring (100 points, pass ≥ 65):

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Debit note exists for Pavlova ~$200 | 20 | debit-notes page contains $200 near "Pavlova" |
| Payment to Pavlova ~$1,320 | 20 | payments page contains $1,320 near "Pavlova" |
| Payment to Specialty Biscuits ~$2,430 | 20 | payments page contains $2,430 near "Specialty Biscuits" |
| Payment to Grandma Kelly's ~$1,890 | 20 | payments page contains $1,890 near "Grandma Kelly" |
| Recent invoices NOT paid (no $875 payment, no Exotic payment) | 20 | payments page lacks $875 Pavlova payment and Exotic Liquids |

### Anti-Gaming:
- Setup records initial payment count; verifier checks NEW payments only
- Wrong-supplier payments return 0 for the affected criterion
- Score capped if required debit note is missing but payment run appears done

## Schema Reference

### Manager.io API Endpoints Used:
- `GET /suppliers?{key}` — supplier list with names
- `GET /purchase-invoices?{key}` — purchase invoice list with dates, amounts, outstanding
- `GET /payments?{key}` — payment list with payee, amount, date
- `GET /debit-notes?{key}` — debit note list with supplier, amount

### Key Date Logic:
- Invoice date > 30 days ago = overdue
- Task setup uses dates calculated relative to task start

## Edge Cases
- Agent might pay all invoices (including non-overdue ones) — partial credit only for overdue payments
- Agent might not create debit note but pays $1,520 directly — debit note criterion fails, payment criterion fails (looking for $1,320)
- Agent creates debit note but forgets to reduce payment — both debit note and payment criteria checked independently
