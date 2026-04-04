# audit_fix_product_pricing

## Domain Context

Online merchants routinely audit product catalogs to fix pricing errors, correct SKUs, manage list/sale prices, and unpublish out-of-stock items. This task simulates a pricing audit requiring the agent to make five distinct corrections across different products and product attributes.

## Goal

Correct five specific product discrepancies identified in a pricing audit:

1. **Bose QuietComfort Ultra Earbuds** (SKU: BOSE-QCUE): Change price from $299.00 to $279.00
2. **WD Black SN850X 2TB NVMe SSD** (SKU: WD-SN850X-2TB): Change price from $149.99 to $129.99
3. **Corsair Vengeance DDR5 32GB RAM Kit** (SKU: CORSAIR-DDR5-32G): Append 'B' to SKU -> CORSAIR-DDR5-32GB
4. **Sony WH-1000XM5 Wireless Headphones** (SKU: SONY-WH1000XM5): Set list price to $399.99 (keep selling price $348.00)
5. **Anker PowerCore 26800mAh Portable Charger** (product_id=7): Unpublish (set status=0)

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Bose price = $279.00 | 20 | variation_id=4 price__number = 279.00 |
| 2 | WD SSD price = $129.99 | 20 | variation_id=9 price__number = 129.99 |
| 3 | Corsair SKU = CORSAIR-DDR5-32GB | 20 | variation_id=12 sku field corrected |
| 4 | Sony list price = $399.99 | 20 | variation_id=1 list_price__number = 399.99, selling price unchanged |
| 5 | Anker unpublished | 20 | product_id=7 status = 0 |

**Pass threshold:** 60/100 (3 of 5 subtasks)

## Verification Strategy

- **Baseline recording:** Initial prices, SKU, list price, and status recorded at setup for all 5 products
- **Gate:** If no changes detected across any of the 5 products, score = 0
- **Independent criteria:** Each product fix is scored independently — partial credit for any subset
- **Partial credit within criterion:** If a price was changed but to a wrong value, 5 points awarded

## Schema Reference

| Table | Key Fields |
|-------|-----------|
| `commerce_product_variation_field_data` | variation_id, sku, price__number, price__currency_code, list_price__number |
| `commerce_product_field_data` | product_id, status, title |

## Edge Cases

- Agent might fix some products but not others — independent scoring handles this
- Agent might change the Sony selling price while setting list price — criterion 4 checks both
- Agent might delete Anker instead of unpublishing — unpublish check would fail
- Corsair SKU is case-insensitive in verification (upper comparison)
