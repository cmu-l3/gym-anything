# Task: Inventory Product Launch Full Cycle

## Overview

**Difficulty**: Hard
**Environment**: Manager.io (Northwind Traders business)
**Occupation Context**: Bookkeeper / Office Manager at a small trading company
**Features Used**: Inventory Items, Customers, Sales Invoices, Receipts, Credit Notes

## Domain Context

When a small trading company launches a new product line, the bookkeeper must: set up inventory items in the accounting system, create the first sales invoice using those items, record the customer's deposit payment, and issue a credit note for any returned or damaged items. This tests a common, complete workflow in accounting software.

Real Northwind product line featured — specialty teas:
- **Chai Tea** — Blend No. 1 (real Northwind product from Exotic Liquids)
- **English Breakfast Tea** — Classic blend
- **Darjeeling Reserve** — Premium single-origin

## Task Description (as seen by agent)

"Northwind Traders is launching a new specialty tea product line. Complete the setup and first order processing: (1) Create three inventory items — Chai Tea (unit: box, sales price: $19.50, purchase price: $7.25), English Breakfast Tea (unit: box, sales price: $16.00, purchase price: $5.80), and Darjeeling Reserve (unit: box, sales price: $34.00, purchase price: $12.00). (2) Create a sales invoice for Alfreds Futterkiste for their first order: 5 boxes of Chai Tea and 10 boxes of English Breakfast Tea. (3) Record a 50% deposit receipt from Alfreds Futterkiste received into Cash on Hand. (4) Issue a credit note to Alfreds for 2 boxes of Chai Tea that arrived damaged. Then check the sales invoices list to confirm the invoice is on record. Login: administrator (no password) at http://localhost:8080"

## Ground Truth

### Inventory Items to Create:

| Item | Unit | Sales Price | Purchase Price |
|------|------|-------------|----------------|
| Chai Tea | box | $19.50 | $7.25 |
| English Breakfast Tea | box | $16.00 | $5.80 |
| Darjeeling Reserve | box | $34.00 | $12.00 |

### Invoice Calculation:
- 5 × Chai Tea @ $19.50 = $97.50
- 10 × English Breakfast Tea @ $16.00 = $160.00
- **Invoice Total = $257.50**

### Receipt:
- 50% of $257.50 = **$128.75** (deposit from Alfreds, to Cash on Hand)

### Credit Note:
- 2 × Chai Tea @ $19.50 = **$39.00** (damaged goods returned)

### Final Alfreds Balance:
- $257.50 − $128.75 − $39.00 = **$89.75**

## Verification Strategy

### Scoring (100 points, pass ≥ 65):

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Chai Tea created with correct sales price $19.50 | 15 | inventory-items page: "Chai Tea" and "19.50" |
| English Breakfast Tea created with correct sales price $16.00 | 15 | inventory-items page: "English Breakfast" and "16.00" |
| Darjeeling Reserve created with correct sales price $34.00 | 10 | inventory-items page: "Darjeeling" and "34.00" |
| Sales invoice for ~$257.50 created for Alfreds | 20 | sales-invoices page: "Alfreds" and "257.50" |
| Receipt for ~$128.75 recorded | 20 | receipts page: "128.75" |
| Credit note for ~$39.00 issued | 20 | credit-notes page: "39.00" near "Alfreds" |

### Anti-Gaming:
- Initial counts of inventory items, invoices, receipts, credit notes all saved
- Verifier checks NEW records only (delta from baseline)
- Wrong prices for items → item criteria fail independently
- Wrong invoice total → invoice criterion fails independently

## Schema Reference

### Manager.io Inventory Item JSON:
```json
{"Name": "Chai Tea", "Unit": "box", "SalesUnitPrice": 19.50, "PurchaseUnitPrice": 7.25}
```

### Manager.io API Endpoints:
- `GET /inventory-items?{key}` — item list with name, code, sales price
- `GET /sales-invoices?{key}` — invoice list with customer, total
- `GET /receipts?{key}` — receipts list with payer, amount, bank account
- `GET /credit-notes?{key}` — credit notes with customer, amount
