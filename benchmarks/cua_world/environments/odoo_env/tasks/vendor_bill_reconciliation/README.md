# Task: Vendor Bill Reconciliation

## Difficulty: Very Hard

## Occupation Context
**Primary occupations**: Treasurers & Controllers ($1.61B GDP), Accountants & Auditors ($911M GDP)
**Why realistic**: Vendor bill reconciliation is a core accounts-payable workflow. Controllers must regularly verify that vendor invoices match purchase orders before approving payment. Overpayment due to unchecked vendor bills is a significant source of financial loss in businesses.

## Scenario
A vendor has submitted an invoice that the accounts payable system has flagged as potentially overcharged. The vendor bill amount is significantly higher than the corresponding purchase order amount. The agent must:

1. **Discover** the discrepant vendor bill by navigating Accounting → Vendors → Bills
2. **Identify** the discrepancy by comparing the bill to its referenced purchase order
3. **Correct** the bill amount to match the purchase order
4. **Post/Validate** the corrected bill
5. **Register** full payment for the corrected bill

## Why This Is Very Hard
- Agent must navigate both Accounting module (for the bill) and Purchase module (for the PO)
- No explicit instructions on which menu to use or how to find the discrepant bill
- Agent must understand the relationship between bills and purchase orders
- Three distinct sequential operations: find → correct → post → pay
- Wrong target (paying without correcting, or paying wrong vendor) returns score=0

## Setup Details
`setup_task.sh` performs:
1. Finds an existing vendor from Odoo demo data (supplier_rank > 0)
2. Finds an existing purchasable product with a non-zero cost
3. Creates a Purchase Order at the correct unit price × 8 units
4. Confirms the PO (moves it to 'purchase' state)
5. Creates a vendor bill for the same vendor and product at **~42% inflated price**
6. Saves setup metadata to `/tmp/vendor_bill_setup.json`

## Verification Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Bill amount corrected (within 5% of PO) | 30 | `abs(bill_amount - po_amount) / po_amount < 0.05` |
| Bill posted/validated | 20 | `bill.state == 'posted'` |
| Payment registered | 35 | `bill.payment_state in ['paid', 'in_payment']` |
| **Pass threshold** | **70** | **Must score ≥70** |

Wrong target (different vendor): immediate score=0

## Key Odoo Tables
- `account.move` (move_type='in_invoice') — vendor bills
- `purchase.order` — purchase orders
- `account.payment` — payments registered against bills

## Features Exercised
- Accounting module: Vendor Bills list, bill edit form, posting
- Purchase module: PO reference, PO amount comparison
- Payment registration: Register Payment dialog
