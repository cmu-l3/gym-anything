# Task: Shift End Reconciliation

**Difficulty:** Very Hard
**Timeout:** 720 seconds | **Max Steps:** 90
**Environment:** Copper Point of Sale (Windows 11)

## Scenario

You are the afternoon cashier/supervisor ending your shift. Two files are on the Desktop: a shift inventory CSV to import and a transaction log detailing 5 customer interactions. You must import the inventory, process all transactions exactly as specified (including a loyalty discount and a void), then generate and export the day's sales report.

## Required Actions

1. **Import inventory**: Load `C:\Users\Docker\Desktop\shift_items.csv` (6 items) into Copper.

2. **Process 5 transactions** from `C:\Users\Docker\Desktop\shift_log.txt`:
   - **T1**: Ocean Blue Shirt ×2 + Classic Varsity Top ×1 → Cash payment (~$160.00)
   - **T2**: Yellow Wool Jumper ×1 with **15% loyalty discount** → Cash (~$68.00 after discount)
   - **T3**: Classic Leather Jacket ×1 → Credit Card payment (~$80.00)
   - **T4**: Soft Winter Jacket ×2 → **VOID/CANCEL** (wrong size, cashier error)
   - **T5**: Floral White Top ×1 → Cash (~$75.00)

3. **Generate and export Sales Report**: Navigate to Reports, generate a Sales Report for today's date range, and export to `C:\Users\Docker\Desktop\shift_report.csv`.

## Expected Totals

- Completed transactions: 4 (T1, T2, T3, T5)
- Voided transactions: 1 (T4)
- Expected revenue range: **$350 – $450** (T1+T2+T3+T5, allowing for tax variations)

## Scoring (100 pts)

| Criterion | Points |
|-----------|--------|
| shift_report.csv exists and is new | 20 |
| Report has ≥3 data rows | 15 |
| Discount evidence in report | 15 |
| Void/cancel evidence in report | 15 |
| Total within $350–$450 range | 20 |
| ≥4 transactions recorded | 15 |
| **Total** | **100** |

**Pass threshold:** ≥ 55 points
**Gate:** Report file must exist and be newer than task start timestamp.

## Verification Output

The export script writes `C:\Users\Docker\shift_end_result.json` with parsed transaction counts, discount evidence, void evidence, and extracted totals.
