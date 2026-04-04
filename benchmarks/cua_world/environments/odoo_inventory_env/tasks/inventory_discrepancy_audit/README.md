# Task: Inventory Discrepancy Audit and Reconciliation

## Occupation Context
**Loss Prevention Manager** — One of the top Odoo users by economic GDP impact ($1.87B). LPMs reconcile physical stock with system records, investigate variances, and resolve discrepancies across product categories.

## Task Overview
The agent plays the role of a Loss Prevention Manager at Meridian Industrial Supply. A physical cycle count has just been completed for 6 industrial safety product SKUs. The system inventory does not match physical reality for 5 of the 6 products. The agent must identify the discrepancies and apply inventory adjustments in Odoo to reconcile the records.

## Starting State
Six real industrial safety products exist in the Odoo database with deliberately incorrect system quantities:
| SKU | Product | System Qty | Physical Count |
|-----|---------|-----------|----------------|
| INV-AUDIT-001 | 3M Peltor OX2000 Safety Glasses | 8 | 45 (discrepancy!) |
| INV-AUDIT-002 | Milwaukee 2606-20 M18 Drill Driver | 3 | 12 (discrepancy!) |
| INV-AUDIT-003 | Stanley 33-725 FatMax 25ft Tape | 22 | 18 (discrepancy!) |
| INV-AUDIT-004 | Honeywell FAK10-012 First Aid Kit | 15 | 0 (discrepancy!) |
| INV-AUDIT-005 | 3M 8210 N95 Respirator 20-Pack | 33 | 50 (discrepancy!) |
| INV-AUDIT-006 | Klein Tools 32500 11-in-1 Screwdriver | 7 | 7 (NO discrepancy — distractor) |

## Expected End State
All 5 discrepant products have on-hand quantity matching the physical count. The inventory adjustment is validated.

## Why This Is Hard
- Agent must compare system quantities vs physical count table for each product
- Agent must navigate to Odoo's inventory adjustment feature (not obviously labeled)
- Must apply adjustments for 5 products across different categories of change (up, down, to zero)
- Agent should NOT adjust product 6 (no discrepancy)
- Odoo 17's Physical Inventory feature requires specific navigation steps that aren't obvious

## Difficulty
**Hard** — targets and expected values are given, but UI navigation must be discovered by the agent.

## Verification Strategy
Each of the 5 discrepant products is worth 20 points (100 total). Points awarded when `current_qty == expected_qty` (within 0.5 unit tolerance). Pass threshold: 60/100 (at least 3 products corrected).

## Key Odoo Tables
- `stock_quant`: Current inventory (qty on hand per product per location)
- `product_template`: Product master (default_code, name)
- `stock_location`: Locations (usage='internal' for WH/Stock)

## Data Sources
All product names, SKUs, and pricing are based on real commercially available industrial safety products:
- 3M Peltor OX2000: 3M PPE catalog, occupational safety eyewear
- Milwaukee 2606-20: Milwaukee Tool M18 product line
- Stanley 33-725: Stanley FatMax measuring tools
- Honeywell FAK10-012: Honeywell Safety first aid kits
- 3M 8210: 3M respiratory protection catalog
- Klein Tools 32500: Klein Tools screwdriver product line
