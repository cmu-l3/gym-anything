# Task: Sales Quotation to Invoice Workflow

## Difficulty: Hard

## Occupation Context
**Primary occupations**: Sales Representatives – Wholesale/Manufacturing ($832M GDP), Customer Service Representatives ($2.91B GDP)
**Why realistic**: The complete sales cycle — quotation → order confirmation → invoice → payment — is the most fundamental B2B sales workflow in any ERP system. This task requires navigating across the Sales and Accounting modules and understanding the state machine that moves a document from quotation through to paid invoice.

## Scenario
**Meridian Pacific Group** has submitted their monthly office furniture order and needs a formal quotation, sales order, and paid invoice. The agent must complete the full order-to-cash cycle:

1. Create a quotation for "Meridian Pacific Group" with:
   - 15 units of "Standing Desk Pro - Height Adjustable"
   - 8 units of "Executive High-Back Chair"
   - Payment terms: 30 days
   - Internal note: "Priority order — expedite shipping"
2. Confirm the quotation (generates a Sales Order)
3. Create an invoice from the Sales Order
4. Post (validate) the invoice
5. Register full payment

## Why This Is Hard
- Multi-step workflow spanning Sales AND Accounting modules
- Agent must find the customer in Contacts, then navigate to Sales to create a quotation
- Product names must be found/selected correctly in the product catalog
- Payment terms must be set correctly (not default)
- Note must be entered in the correct field
- Three distinct validation steps (confirm order, post invoice, register payment)
- Invoice must be created from the sales order (not independently)

## Setup Details
`setup_task.sh` performs:
1. Creates customer "Meridian Pacific Group" (if not exists)
2. Creates two products: "Standing Desk Pro - Height Adjustable" ($649) and "Executive High-Back Chair" ($425)
3. Finds 30-day payment terms (already in demo data)
4. Saves setup metadata to `/tmp/sales_quotation_setup.json`

Expected order total: 15 × $649 + 8 × $425 = $9,735 + $3,400 = $13,135

## Verification Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Sales order confirmed | 15 | `sale.order.state in ['sale', 'done']` |
| Both products on order | 20 | Both product IDs found in order lines |
| Payment terms = 30 days | 10 | `payment_term_id` name contains '30' |
| Internal note with 'Priority' | 10 | `note` field contains 'priority' |
| Invoice posted | 20 | `account.move.state == 'posted'` |
| Invoice paid | 25 | `payment_state in ['paid', 'in_payment']` |
| **Pass threshold** | **70** | **Must score ≥70; invoice paid required** |

## Key Odoo Tables
- `sale.order` — sales quotations and orders
- `sale.order.line` — order line items (product, qty, price)
- `account.move` (move_type='out_invoice') — customer invoices
- `account.payment` — payments registered against invoices

## Features Exercised
- Sales module: New Quotation form, product selection, payment terms
- Sales → Invoicing: Create Invoice from Sales Order button
- Accounting module: Invoice form, Confirm / Post button
- Payment registration: Register Payment dialog (bank, amount, date)
