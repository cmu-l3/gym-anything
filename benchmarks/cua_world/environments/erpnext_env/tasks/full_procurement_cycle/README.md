# Task: full_procurement_cycle

**Difficulty**: very_hard
**Environment**: erpnext_env
**Occupation alignment**: Production/Planning/Expediting Clerks (importance=84, GDP=$163M)

## Overview

Wind Power LLC has an open Purchase Order with Eagle Hardware for 50 units of Upper Bearing Plate at $50 each (total $2,500). The parts have physically arrived at the warehouse. The agent must complete the entire procurement cycle to close out this payable.

## Setup State

- Eagle Hardware supplier is created
- Upper Bearing Plate item exists (stock item)
- **A submitted Purchase Order (PO) for 50 × Upper Bearing Plate @ $50.00 is ready**
- Browser is open to the Purchase Order list

## Required Agent Actions (in order)

1. Find the submitted PO for Eagle Hardware
2. Create a **Purchase Receipt** from the PO (receive goods into Stores - WP)
3. Create a **Purchase Invoice** from the PR or PO (record the supplier invoice)
4. Create a **Payment Entry** from the PI (pay Eagle Hardware)
5. Verify Eagle Hardware outstanding balance reaches $0

## Scoring (100 pts, pass >= 70)

| Criterion | Points | Check |
|-----------|--------|-------|
| C1: Purchase Receipt submitted, linked to PO, qty >= 50 | 30 | Export queries PR items |
| C2: Purchase Invoice submitted, grand_total >= $2,400 | 30 | Export queries PI |
| C3: Payment Entry (Pay) submitted for Eagle Hardware | 20 | Export queries PE |
| C4: Eagle Hardware outstanding balance = $0 | 20 | Sum of PI outstanding_amount |

## Key ERPNext Workflow Notes

- From a submitted PO, click **Create > Purchase Receipt** to start goods receipt
- From a submitted PR (or PO), click **Create > Purchase Invoice**
- From a submitted PI, click **Make > Payment Entry** to pay the supplier
- The Payment Account should use "Cash - WP" or appropriate bank account

## Files

- `task.json` — task metadata and init config
- `setup_task.sh` — creates supplier, item, submits PO
- `export_result.sh` — queries ERPNext for PR/PI/PE, writes `/tmp/full_procurement_cycle_result.json`
- `verifier.py` — scores based on exported result JSON
