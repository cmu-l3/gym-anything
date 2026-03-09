# Task: Purchase Order Partial Receipt

**Difficulty**: Hard
**Category**: Procurement / Supply Chain
**Occupation Context**: Procurement Manager, Operations Manager, Purchasing Agent

## Overview

This task simulates a core procurement workflow: selecting the cheapest vendor from competing quotes, creating separate purchase orders, and processing partial receipts when vendors cannot fulfill the full order immediately. The agent must understand vendor comparison, PO creation, and Odoo's backorder flow.

## Starting State

- Three vendors exist: Industrial Supplies Co., Automation Parts Direct, Component World
- Three products exist with no vendor pricelists configured
- No purchase orders exist for these products

## Task Goal

For each of 3 electronic component products:
1. **Identify the cheapest vendor** from the provided quotes
2. **Create a purchase order** with that vendor for the required quantity
3. **Validate a partial receipt** for the quantity immediately available
4. **Create a backorder** for the remaining quantity

### Correct Vendor Selections

| Product | Cheapest Vendor | Price |
|---------|----------------|-------|
| ELEC-COMP-001 (Parker Fitting) | Automation Parts Direct | $3.42/unit |
| ELEC-COMP-002 (Phoenix Contact Terminal) | Component World | $1.87/unit |
| ELEC-COMP-003 (HellermannTyton Cable Ties) | Component World | $7.95/unit |

### Partial Receipt Quantities

| Product | Total Ordered | Receive Now | Backorder |
|---------|--------------|-------------|-----------|
| ELEC-COMP-001 | 100 units | 40 units | 60 units |
| ELEC-COMP-002 | 200 units | 200 units (full) | 0 units |
| ELEC-COMP-003 | 1000 units | 600 units | 400 units |

## Why This Is Hard

- Requires comparing 9 vendor prices (3 vendors × 3 products) correctly
- Must create 3 separate POs with different vendors
- Partial receipt flow requires overriding default quantities and choosing "Create Backorder"
- ELEC-COMP-002 is a full receipt (no backorder needed) — tricky edge case
- Must avoid accidentally using wrong vendor for any product

## Verification Strategy

- **15 pts each**: Correct vendor chosen for each of 3 products (45 pts)
- **10 pts each**: Partial receipt validated for each product (30 pts)
- **15 pts**: Backorders created for ELEC-COMP-001 and ELEC-COMP-003 (non-full receipts)
- **10 pts**: Correct quantities received (within tolerance)

**Pass threshold**: 55/100

## Files

- `task.json` — Task specification with vendor prices and expected quantities
- `setup_task.sh` — Creates products and vendors; clears old POs
- `export_result.sh` — Queries PO partner, line prices, picking states, received quantities, backorders
- `verifier.py` — Multi-criterion scoring
