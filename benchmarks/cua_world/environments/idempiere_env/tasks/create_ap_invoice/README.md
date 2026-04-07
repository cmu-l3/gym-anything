# Task: Create AP Invoice for Tree Farm Inc.

## Overview

Tree Farm Inc. has delivered nursery stock to GardenWorld's warehouse and submitted their invoice. An accountant must record this vendor invoice in iDempiere's accounts payable system and post it so the liability is properly recorded in the general ledger.

This task tests the agent's ability to navigate iDempiere's Vendor Invoice module — distinct from Purchase Orders — enter product lines with correct quantities and prices, and complete/post the document.

## Goal

Create a **vendor (AP) invoice** for Tree Farm Inc. with the following items and post it:

| Product | Quantity | Unit Price | Line Total |
|---------|----------|-----------|------------|
| Holly Bush | 5 | $24.00 | $120.00 |
| Oak Tree | 3 | $36.00 | $108.00 |
| **Total** | | | **$228.00** |

The invoice must have Document Status = **Completed (CO)** after posting.

## Credentials

- **URL**: https://localhost:8443/webui/
- **User**: GardenAdmin
- **Password**: GardenAdmin

## Success Criteria

- A new vendor invoice exists for Tree Farm Inc. (issotrx=N)
- Invoice status is Completed (docstatus='CO')
- Invoice has a line for Holly Bush (product_id=129) with qty ≥ 5
- Invoice has a line for Oak Tree (product_id=123) with qty ≥ 3
- Invoice grand total is between $200 and $260

## Verification Strategy

The verifier queries `c_invoice` for new records created after task start for vendor Tree Farm Inc. (c_bpartner_id=114), then checks `c_invoiceline` for the required products and quantities.

**Scoring (100 points):**
- Invoice created for Tree Farm Inc., status Completed: 30 points
- Holly Bush line present with qty ≥ 5: 25 points
- Oak Tree line present with qty ≥ 3: 25 points
- Grand total in range $200–$260: 20 points

Pass threshold: 70 points

## Schema Reference

- `c_invoice` — invoice header (c_bpartner_id=114, issotrx='N', docstatus='CO')
- `c_invoiceline` — invoice lines (m_product_id, qtyinvoiced, priceactual)
- Vendor: Tree Farm Inc., c_bpartner_id=114
- Products: Holly Bush=129, Oak Tree=123

## Key Challenge

In iDempiere, vendor invoices are accessed through the **Vendor Invoice** window (under Open Items or Purchase), not through Purchase Orders. The agent must locate this window, create a new record, select the correct vendor, add product lines with correct quantities and prices, and click Complete to post.
