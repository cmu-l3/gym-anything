# Task: New Store Configuration

**Difficulty:** Very Hard
**Timeout:** 720 seconds | **Max Steps:** 90
**Environment:** Copper Point of Sale (Windows 11)

## Scenario

You are setting up a brand-new Copper POS installation for "Meridian Goods & Supply," a general merchandise retailer opening a new location in Cleveland, OH. The store_specs.txt on the Desktop contains all configuration requirements. You must configure everything from scratch and validate the tax setup by processing a test transaction.

## Required Actions

1. **Business Info** (Settings → Business):
   - Name: `Meridian Goods & Supply`
   - Address: `4720 Commerce Parkway, Suite 100, Cleveland, OH 44135`
   - Phone: `(216) 555-0294`

2. **Receipt** (Settings → Receipt):
   - Header: `Premium Quality, Fair Prices`
   - Footer: `Thank you for shopping Meridian Goods! Returns accepted within 21 days with receipt. meridiangoodssupply.com`
   - Enable date/time printing

3. **Tax** (Settings → Tax):
   - Default tax rate: **8.00%**

4. **Categories** (Inventory → Categories):
   - `Food & Grocery` — 0.00% (exempt)
   - `Electronics & Tech` — 9.50%
   - `Apparel` — 8.00%
   - `Gift Cards` — 0.00% (exempt)

5. **Payment Methods**: Ensure `Check` is available.

6. **Verification**: Add test item `Varsity Top Test` (Apparel, $60.00, taxable at 8%). Process a cash sale and write to `C:\Users\Docker\Desktop\tax_verification.txt`:
   ```
   Item: Varsity Top Test
   Price: $60.00
   Tax Rate: 8.00%
   Tax Amount: $4.80
   Total: $64.80
   ```

## Ground Truth

- 8% tax on $60.00 = **$4.80**
- Total = **$64.80**

## Scoring (100 pts)

| Criterion | Points |
|-----------|--------|
| tax_verification.txt exists and is new | 20 |
| "Meridian" in verification file | 20 |
| "8.00%" or "8%" in verification file | 20 |
| Tax amount $4.80 (±$0.10) found | 20 |
| Total $64.80 (±$0.20) found | 20 |
| **Total** | **100** |

**Pass threshold:** ≥ 60 points
**Gate:** tax_verification.txt must exist and be newer than task start timestamp.

## Verification Output

The export script writes `C:\Users\Docker\new_store_config_result.json` with parsed business name, tax rate, tax amount, and total from the verification file, plus optional Copper SQLite DB cross-checks.
