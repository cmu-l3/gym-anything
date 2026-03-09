# Task: Lot Tracking Receipt & Delivery

**Difficulty**: Hard
**Category**: Inventory Quality / Compliance
**Occupation Context**: Industrial Production Manager, Quality Control Manager

## Overview

This task simulates a real compliance scenario faced by medical supply distribution managers: products arrive from a vendor without lot tracking enabled, requiring the manager to configure traceability settings before validating receipt with the manufacturer-provided lot numbers.

## Starting State

- Vendor **Medline Industries Inc.** exists in the system
- A **Draft Purchase Order** has been created with 3 medical diagnostic products
- All 3 products have tracking set to **"none"** (lot tracking disabled — compliance violation)
- The PO is in **"Purchase Order"** state (confirmed, waiting for receipt)
- No stock quants exist for these products

## Task Goal

1. **Enable lot tracking** on all 3 products (tracking = "By Lot")
2. **Validate the PO receipt** and assign the provided lot numbers:
   - LOT-TRACK-001: receive 200 units with lot `MED-2024-AB-001`
   - LOT-TRACK-002: receive 150 units with lot `MED-2024-BR-001`
   - LOT-TRACK-003: receive 300 units with lot `MED-2024-3M-001`

## Why This Is Hard

- Must navigate to product configuration before receipt validation
- Lot tracking must be enabled on the product template (not the PO line)
- Receipt validation flow requires entering lot numbers in the detailed operations view
- All three products must be tracked and received with correct lots
- Products have zero initial stock — receipt is the first stock entry

## Verification Strategy

- **30 pts**: All 3 products have `tracking = 'lot'` enabled
- **30 pts**: Receipt validated (picking state = 'done')
- **20 pts**: Correct lot numbers assigned to each product in stock move lines
- **20 pts**: Correct quantities received per product

**Pass threshold**: 60/100

## Products

| SKU | Name | Qty | Lot Number |
|-----|------|-----|------------|
| LOT-TRACK-001 | Abbott FreeStyle Lite Test Strips 50ct | 200 | MED-2024-AB-001 |
| LOT-TRACK-002 | Braun ThermoScan Lens Filters LF40 | 150 | MED-2024-BR-001 |
| LOT-TRACK-003 | 3M Nexcare Waterproof Bandages 30ct | 300 | MED-2024-3M-001 |

## Files

- `task.json` — Task specification and metadata
- `setup_task.sh` — Creates products, vendor, draft PO; disables lot tracking
- `export_result.sh` — Queries lot tracking status, picking state, lot numbers, quantities
- `verifier.py` — Multi-criterion scoring with partial credit
