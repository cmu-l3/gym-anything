# Task: Seasonal Clearance Markdown

**Difficulty:** Very Hard
**Timeout:** 660 seconds | **Max Steps:** 85
**Environment:** Copper Point of Sale (Windows 11)

## Scenario

You are the store manager preparing for the end-of-season clearance event. A Clothing & Apparel inventory CSV has been staged on the Desktop. You must import it, apply selective pricing adjustments based on stock levels, and export the updated inventory.

## Required Actions

1. **Import inventory**: Load `C:\Users\Docker\Desktop\clothing_inventory.csv` (20 items) into Copper's Items/Inventory list.

2. **Apply clearance pricing** (any item with **qty ≥ 30** = overstocked):
   - Reduce price by **exactly 20%** (round to nearest cent)
   - 8 items qualify: Floral White Top, Striped Silk Blouse, Dark Denim Top, Navy Sports Jacket, Soft Winter Jacket, Black Leather Bag, Zipped Jacket, LED High Tops

3. **Apply premium pricing** (any item with **qty ≤ 7** = low stock):
   - Increase price by **exactly 15%** (round to nearest cent)
   - 3 items qualify: Ocean Blue Shirt, Silk Summer Top, Striped Skirt and Top

4. **Export inventory**: Export the complete item list to `C:\Users\Docker\Desktop\clearance_inventory.csv`.

## Ground Truth

| Item | Qty | Original | Expected Clearance |
|------|-----|----------|--------------------|
| Floral White Top | 39 | $75.00 | $60.00 |
| Striped Silk Blouse | 32 | $50.00 | $40.00 |
| Dark Denim Top | 37 | $60.00 | $48.00 |
| Navy Sports Jacket | 40 | $60.00 | $48.00 |
| Soft Winter Jacket | 46 | $50.00 | $40.00 |
| Black Leather Bag | 31 | $30.00 | $24.00 |
| Zipped Jacket | 42 | $65.00 | $52.00 |
| LED High Tops | 39 | $80.00 | $64.00 |

| Item | Qty | Original | Expected Premium |
|------|-----|----------|------------------|
| Ocean Blue Shirt | 6 | $50.00 | $57.50 |
| Silk Summer Top | 5 | $70.00 | $80.50 |
| Striped Skirt and Top | 7 | $50.00 | $57.50 |

## Scoring (100 pts)

| Criterion | Points |
|-----------|--------|
| clearance_inventory.csv exists and is new | 15 |
| Export has ≥15 rows | 15 |
| Each clearance item correctly priced (×8) | 5 pts each = 40 |
| Each premium item correctly priced (×3) | 10 pts each = 30 |
| **Total** | **100** |

**Pass threshold:** ≥ 60 points
**Gate:** Export file must exist and be newer than task start timestamp.

## Verification Output

The export script writes `C:\Users\Docker\seasonal_clearance_result.json` with parsed pricing accuracy per item.
