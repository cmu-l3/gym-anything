# Tax Configuration Task

## Overview

This task tests a Magento administrator's ability to configure a complete multi-state tax system, which involves three interdependent configuration steps: creating a product tax class, creating multiple tax rates, and creating a tax rule that links them together. This is a core e-commerce compliance workflow performed by tax analysts and platform administrators.

**Domain context**: B2B equipment distributors are subject to complex multi-state sales tax obligations. Industrial machinery sold to California buyers is taxed at the CA base state rate of 7.25% (California Board of Equalization, effective 2017). Sales to New York buyers are taxed at the NY base state rate of 4.00% (New York State Department of Taxation and Finance). Configuring Magento to correctly collect these taxes requires the exact three-step workflow tested here.

## Real Data Sources

- California base state sales tax rate: 7.25% — Source: California Board of Equalization, effective January 1, 2017
- New York base state sales tax rate: 4.00% — Source: New York State Department of Taxation and Finance

## Goal

Configure three interdependent items in Magento's tax system:

**1. Product Tax Class:**
- Name: `Industrial Machinery`
- Type: Product Tax Class

**2. Two Tax Rates:**
- `California State Tax`: US / CA / * (all) / 7.25%
- `New York State Tax`: US / NY / * (all) / 4.00%

**3. Tax Rule:**
- Name: `Industrial Equipment Tax Rule`
- Customer Tax Class: Taxable Goods
- Product Tax Class: Industrial Machinery (just created)
- Tax Rates: California State Tax AND New York State Tax (both selected)
- Priority: 0

All three items must be saved.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Product tax class `Industrial Machinery` created | 20 |
| California tax rate at 7.25% for CA exists | 20 |
| New York tax rate at 4.00% for NY exists | 20 |
| Tax rule `Industrial Equipment Tax Rule` exists | 20 |
| Tax rule links both state rates AND the Industrial Machinery class | 20 |

**Pass threshold: 60 points**

## Verification Strategy

- `setup_task.sh` records initial counts for `tax_class`, `tax_calculation_rate`, and `tax_calculation_rule`; also records the region IDs for California and New York from `directory_country_region`
- `export_result.sh` queries each table for the created items; validates CA rate (7.25 ± 0.01) and NY rate (4.00 ± 0.01); checks `tax_calculation` junction table to confirm both rates are linked to the rule, and that the rule uses the Industrial Machinery tax class
- `verifier.py` gates on tax class existence, then scores each criterion independently

## Database Schema Reference

```sql
-- Product tax classes
SELECT class_id, class_name, class_type FROM tax_class
WHERE LOWER(TRIM(class_name)) LIKE '%industrial%' AND class_type='PRODUCT';

-- Tax rates
SELECT tax_calculation_rate_id, code, rate, tax_country_id, tax_region_id, tax_postcode
FROM tax_calculation_rate WHERE code IN ('California State Tax', 'New York State Tax');

-- Region IDs for CA and NY
SELECT region_id, code FROM directory_country_region
WHERE country_id='US' AND code IN ('CA', 'NY');

-- Tax rule
SELECT rule_id, code, priority FROM tax_calculation_rule
WHERE LOWER(TRIM(code)) LIKE '%industrial%equipment%';

-- Tax rule linkages (rates and classes)
SELECT * FROM tax_calculation WHERE rule_id=<rule_id>;

-- Customer tax class (for verification)
SELECT class_id FROM tax_class WHERE class_type='CUSTOMER' AND class_name='Taxable Goods';
```

## Edge Cases

- Magento admin requires creating the tax class first (in Stores > Tax > Product Tax Classes), then creating rates (Stores > Tax > Tax Rates), then creating the rule (Stores > Tax > Tax Rules) — each in a different section. The agent must navigate all three.
- In the tax rule creation form, both the CA and NY rates must be selected simultaneously from the multiselect "Tax Rate" field.
- The `tax_calculation_rate` table uses `tax_region_id` (a numeric foreign key to `directory_country_region`), not the two-letter state code directly. The export script handles this mapping.
- The CA rate of 7.25% exactly matches the California BOE base state rate; any deviation (e.g., entering 8.25% which includes the average county rate) will score partial credit.
