# Task: Inventory Physical Count Adjustment

## Difficulty: Very Hard

## Occupation Context
**Primary occupations**: Loss Prevention Managers ($1.87B GDP), Stockers & Order Fillers ($1.12B GDP)
**Why realistic**: Physical inventory counts are a standard warehouse management procedure. Reconciling system quantities with physical counts, then establishing reorder rules to prevent stockouts, is a multi-step workflow that requires navigating both the Physical Inventory and Replenishment features of the Inventory module.

## Scenario
The warehouse team completed a physical inventory count for three product lines. The physical count results (in `/home/ga/Desktop/physical_count.txt`) differ from the system's recorded quantities — some products show more stock than the system recorded (received goods not logged), others show less (breakage, theft). The agent must:

1. **Read** the physical count file on the Desktop
2. **Navigate** to Odoo Inventory → Physical Inventory (or Operations → Physical Inventory)
3. **Enter** the counted quantities for each of the 3 products
4. **Apply** the inventory adjustment
5. **Navigate** to the Reorder Rules section (Inventory → Configuration → Reorder Rules OR Replenishment)
6. **Create** reorder rules for all 3 products: min=15, max=60

## Why This Is Very Hard
- Agent must read an external reference file and apply those values in Odoo
- Navigating to Physical Inventory requires knowing the Inventory module's Operations menu
- Physical inventory adjustment workflow has multiple steps (enter counted qty → apply)
- Reorder rules are in a separate location, requiring a second navigation
- 6 independent reorder rules values to set correctly (min AND max for 3 products)

## Setup Details
`setup_task.sh` performs:
1. Creates 3 storable products: Wireless Ergonomic Keyboard, USB-C Multiport Docking Station, Adjustable Monitor Arm - Single
2. Sets their stock.quant quantities (system quantities that appear in Odoo)
3. Records the "physical count" (different from system) in `/home/ga/Desktop/physical_count.txt`
4. Records setup metadata in `/tmp/inventory_physical_count_setup.json`

| Product | System Qty | Physical Count | Delta |
|---------|-----------|---------------|-------|
| Wireless Ergonomic Keyboard | 47 | 35 | -12 |
| USB-C Multiport Docking Station | 31 | 38 | +7 |
| Adjustable Monitor Arm - Single | 19 | 12 | -7 |

## Verification Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Each product quantity adjusted correctly (×3) | 15 each = 45 | `abs(current_qty - physical_qty) < 0.5` |
| Reorder rule with correct min=15 (×3) | 10 each = 30 | `product_min_qty == 15` |
| Reorder rule with correct max=60 (×3) | 8 each + 1 bonus = 25 | `product_max_qty == 60` |
| **Pass threshold** | **65** | **Must score ≥65** |

## Key Odoo Tables
- `stock.quant` — actual on-hand quantities per location
- `stock.quant_package` / `stock.move` — movement tracking
- `stock.warehouse.orderpoint` — reorder rules (min/max qty, reorder point)

## Features Exercised
- Inventory module: Physical Inventory (Operations menu)
- Inventory counting workflow: "Counted Quantity" column → Apply All
- Replenishment / Reorder Rules: Create rules per product with min/max qty
