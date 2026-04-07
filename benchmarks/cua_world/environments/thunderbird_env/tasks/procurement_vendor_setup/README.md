# Task: procurement_vendor_setup

## Overview

**Difficulty**: very_hard
**Environment**: thunderbird_env
**Occupation**: Procurement Director
**Industry**: Manufacturing (Industrial Components)

The agent acts as the Procurement Director at Summit Manufacturing. The purchasing inbox has been unmanaged for two weeks and contains open RFQ responses from vendors, contract documents requiring legal review, and logistics updates. The agent must categorize vendor correspondence, add the primary vendor contact to the address book, and set up routing for future vendor emails.

## What the Agent Must Do

1. Create a **Vendors** folder in Local Folders
2. Create **Active_RFQs** subfolder — move all 4 RFQ/quotation emails there
3. Create **Contract_Review** subfolder — move all 3 contract documents there
4. Add vendor account manager **Sandra Chen** (s.chen@globalsupplyco.com) to the address book
5. Create a message filter routing future **@globalsupplyco.com** emails to Active_RFQs

## Injected Emails (9 total)

| # | From | Subject | Should Go To |
|---|------|---------|-------------|
| 1 | s.chen@globalsupplyco.com | RFQ Response #RFQ-2025-0187 - Stainless Steel 316L Tubing | Active_RFQs |
| 2 | bids@industrialparts.com | Quotation Submission - Carbon Steel Plate - Bid #IP-447 | Active_RFQs |
| 3 | s.chen@globalsupplyco.com | Revised Pricing - RFQ-2025-0187 - Volume Discount Applied | Active_RFQs |
| 4 | procurement@alloymaster.com | Alloy Components Quotation - Inconel 625 Parts | Active_RFQs |
| 5 | legal@globalsupplyco.com | Master Supply Agreement FY2025 - Signature Required | Contract_Review |
| 6 | contracts@industrialparts.com | Amendment to PO #PO-2024-8831 - Payment Terms Change | Contract_Review |
| 7 | s.chen@globalsupplyco.com | Contract Addendum - Force Majeure - Tariff Escalation Provision | Contract_Review |
| 8 | warehouse@summitmfg.com | March Physical Inventory Count - Procurement Input Needed | (stay in Inbox) |
| 9 | shipping@fastfreight.com | Shipment Update - Pro# FF-2025-3392 | (stay in Inbox) |

## Scoring (100 points total)

| Criterion | Points | Details |
|-----------|--------|---------|
| Vendors folder structure (Vendors.sbd exists) | 10 | Any variant folder name accepted |
| Active_RFQs subfolder with ≥4 emails | 25 | Partial credit: ≥2 → 13 pts, ≥1 → 6 pts, folder only → 3 pts |
| Contract_Review subfolder with ≥3 emails | 20 | Partial credit: ≥2 → 12 pts, ≥1 → 5 pts, folder only → 2 pts |
| Sandra Chen (s.chen@globalsupplyco.com) in address book | 20 | Full credit requires email match; name only → 12 pts |
| @globalsupplyco.com routing filter exists | 15 | Filter must reference globalsupplyco.com or globalsupply |
| **Total** | **90** | |

**Pass threshold**: 60 points

## Anti-Gaming Measures

- **Wrong-target guard**: If `Vendors.sbd` exists but zero emails in any subfolder, score capped at 5.
- **Score cap**: If total emails moved = 0 and computed score ≥ 60, score reduced to 59.
- **Clean baseline**: `setup_task.sh` removes existing Vendors folder, clears Sandra Chen from address book, resets filter rules.

## Accepted Folder Name Variants

- Parent: Vendors, Vendor_Emails, Vendor
- Subfolder 1: Active_RFQs, Active-RFQs, ActiveRFQs, RFQs, Active_Quotes, Open_RFQs
- Subfolder 2: Contract_Review, Contract-Review, ContractReview, Contracts_Pending, Legal_Review

## Files

| File | Description |
|------|-------------|
| `task.json` | Task metadata, hooks, difficulty |
| `setup_task.sh` | Clears state, injects 9 emails, records baseline, starts Thunderbird |
| `export_result.sh` | Kills Thunderbird, checks folder structure, email counts, address book, filter rules |
| `verifier.py` | Scores result JSON on 5 criteria; includes 4 pipeline tests |
| `README.md` | This file |

## Testing

```bash
python3 examples/thunderbird_env/tasks/procurement_vendor_setup/verifier.py
```
Expected: 4/4 tests passed
