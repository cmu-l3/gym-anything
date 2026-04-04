# Task: Replenishment Rules Setup and Procurement

## Occupation Context
**General and Operations Manager** — The #1 Odoo user by economic GDP impact ($3.3B). Operations managers use Odoo for supply chain oversight, procurement, and inventory management. Configuring reorder rules and running replenishment are core daily tasks.

## Task Overview (Very Hard)
The agent plays Operations Manager at Meridian Industrial Supply. Seven real PPE/safety products exist in the warehouse. Five have fallen to critically low stock with no reorder rules; two have adequate stock. The agent receives no list of which products need attention — they must independently review inventory, identify products meeting the criteria (low stock + no reorder rule), configure appropriate rules, and trigger procurement.

## Starting State
Seven real PPE products seeded in the database:
| SKU | Product | Stock | Has Rule? |
|-----|---------|-------|-----------|
| REPR-001 | 3M Hi-Vis Safety Vest Class 2 | 5 | No |
| REPR-002 | Pyramex RIDGELINE Hard Hat | 0 | No |
| REPR-003 | Ansell Edge 82-113 Nitrile Gloves | 18 | No |
| REPR-004 | Ergodyne Skullerz 8985 Safety Glasses | 2 | No |
| REPR-005 | MSA V-Gard 500 Safety Helmet | 8 | No |
| REPR-006 | Uvex S2300 Uvextra Spectacles | 45 | No (adequate stock) |
| REPR-007 | 3M 1100 EarSoft Earplugs 200-Pack | 120 | No (adequate stock) |

All existing reorder rules for these products are deleted in setup.

## What the Agent Must Do
1. Navigate to Inventory > Reporting or product views to find stock levels
2. Identify 5 products with low stock (< 20 units) and no reorder rule
3. Create minimum stock reorder rules for those 5 products
4. Trigger replenishment to generate purchase orders for the items already below minimum
5. Verify procurement orders are created

## Why This Is Very Hard
- No product names or SKUs are given in the description
- Agent must discover which products qualify through exploration
- Must understand Odoo's reorder rules feature and how to reach it
- Must understand the difference between "run replenishment" and just creating rules
- Two products (REPR-006, REPR-007) should NOT get rules (adequate stock) — tests judgment

## Difficulty
**Very Hard** — Agent receives only the goal; must discover targets, determine values, find the feature.

## Verification Strategy
- 10 pts each: reorder rule created for each of 5 low-stock products (50 pts total)
- 10 pts: at least one procurement order generated from replenishment
- 15 pts: rules for REPR-001 and REPR-002 (most critical — zero/near-zero stock) created
- 5 pts: high-stock products (REPR-006, REPR-007) do NOT have new rules

Pass threshold: 55/100

## Key Odoo Tables
- `stock_warehouse_orderpoint`: Reorder rules (product_id, warehouse_id, product_min_qty, product_max_qty)
- `purchase_order`, `purchase_order_line`: Generated procurement orders
- `stock_quant`: Current inventory levels

## Data Sources
Real PPE products from leading occupational safety manufacturers:
- 3M Hi-Vis Safety Vest: ANSI/ISEA 107-2015 compliant vest, 3M catalog
- Pyramex RIDGELINE: ANSI Z89.1 Type I Class C hard hat
- Ansell Edge 82-113: EN388 nitrile chemical-resistant gloves
- Ergodyne Skullerz 8985: ANSI Z87.1 protective eyewear
- MSA V-Gard 500: ANSI Z89.1 Type I Class E ventilated cap-style helmet
- Uvex S2300: ANSI Z87.1 anti-fog safety glasses
- 3M 1100 EarSoft: NRR 29 dB corded foam earplugs, 3M hearing protection catalog
