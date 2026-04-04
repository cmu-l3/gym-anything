# Task: Multi-Report Sales Analytics

**Difficulty:** Very Hard
**Timeout:** 720 seconds | **Max Steps:** 90
**Environment:** Copper Point of Sale (Windows 11)

## Scenario

You are the regional sales manager preparing a quarterly analytics package for a board review meeting. An inventory CSV and analytics brief are on the Desktop. You must import the inventory, process three transactions from different product categories, export two Copper reports, and create a hand-written analytics summary with accurate revenue figures.

## Required Actions

1. **Import inventory**: Load `C:\Users\Docker\Desktop\electronics_clothing_inventory.csv` (15 items: 10 Electronics + 5 Clothing) into Copper.

2. **Process 3 transactions** from `C:\Users\Docker\Desktop\analytics_brief.txt`:
   - **Transaction A**: Anker PowerCore 10000 ×2 + Apple Lightning Cable ×1 → Cash (~$71.97)
   - **Transaction B**: Samsung Galaxy Buds FE ×1 with **10% manager discount** → Credit Card (~$89.99 after discount)
   - **Transaction C**: Ocean Blue Shirt ×2 + Classic Varsity Top ×1 → Cash (~$160.00)

3. **Export Sales Report** (broadest available date range): `C:\Users\Docker\Desktop\weekly_sales.csv`

4. **Export Inventory/Stock Report**: `C:\Users\Docker\Desktop\stock_levels.csv`

5. **Write analytics summary**: `C:\Users\Docker\Desktop\analytics_summary.txt` with:
   ```
   Total Items in Inventory: 15
   Transactions Processed Today: 3
   Transaction A Revenue: $71.97
   Transaction B Revenue: $89.99
   Transaction C Revenue: $160.00
   Total Today Revenue: $321.96
   Top Category Today: Electronics
   ```

## Revenue Calculations

| Transaction | Items | Calculation | Revenue |
|-------------|-------|-------------|---------|
| A | Anker PowerCore ×2 ($24.99 each) + Lightning Cable ($22.00) | $49.98 + $22.00 | $71.97 |
| B | Galaxy Buds FE ($99.99) × 90% discount | $99.99 × 0.90 | $89.99 |
| C | Ocean Blue Shirt ×2 ($50.00 each) + Varsity Top ($60.00) | $100.00 + $60.00 | $160.00 |
| **Total** | | | **$321.96** |

## Scoring (100 pts)

| Criterion | Points |
|-----------|--------|
| weekly_sales.csv exists and new | 20 |
| stock_levels.csv exists and new | 20 |
| analytics_summary.txt exists and new | 15 |
| Item count found in summary | 10 |
| Transaction count found in summary | 5 |
| Revenue ~$321.96 in summary (±$5.00) | 20 |
| "Electronics" as top category in summary | 5 |
| weekly_sales.csv has data rows | 5 |
| **Total** | **100** |

**Pass threshold:** ≥ 60 points
**Gate:** At least one output file must exist and be newer than task start timestamp.

## Verification Output

The export script writes `C:\Users\Docker\multi_report_result.json` with file existence/timestamp flags, parsed revenue values, item counts, and row counts from each report file.
