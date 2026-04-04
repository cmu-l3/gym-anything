# Cart Price Rule Task

## Overview

This task tests a Magento admin's ability to configure promotional marketing rules. It reflects a real workflow performed by digital marketing managers and e-commerce merchandisers: setting up a targeted discount campaign with auto-generated coupon codes.

**Domain context**: Fashion e-commerce brands routinely create seasonal promotional rules (back-to-school, holidays, flash sales) scoped to specific customer segments. The auto-generated coupon workflow is heavily used in paid advertising campaigns where each coupon tracks a specific channel or audience.

## Goal

Create a cart price rule named `BACK2SCHOOL25` in Magento that:

- Applies a 25% discount on cart subtotals of $75 or more
- Targets the **General** customer group only (not Wholesale or Retailer)
- Uses auto-generated coupons with prefix `B2S`, with 5 uses per coupon and 1 use per customer
- Expires on 12/31/2025, Priority 1, Stop Further Rules Processing = Yes

After saving the rule, generate **exactly 10 coupon codes** from the Manage Coupon Codes section.

**The agent must discover the Magento admin navigation independently** — no UI path is provided.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Rule `BACK2SCHOOL25` exists in database | 20 |
| Discount is 25% (by_percent type, amount=25) | 20 |
| At least 5 B2S-prefixed coupon codes generated (full credit at 10) | 25 |
| Rule applies to General group only (partial credit if other groups also included) | 20 |
| Minimum subtotal condition of $75 is set | 15 |

**Pass threshold: 60 points**

## Verification Strategy

- `setup_task.sh` records initial `salesrule` and `salesrule_coupon` counts to `/tmp/initial_rule_count` and `/tmp/initial_coupon_count`
- `export_result.sh` queries the `salesrule` table for a rule matching `BACK2SCHOOL25`, checks `conditions_serialized` for the subtotal condition, queries `salesrule_customer_group` for group assignments, and counts coupon codes with `LOWER(code) LIKE 'b2s%'`
- `verifier.py` gates on rule existence, then scores each criterion independently

## Database Schema Reference

```sql
-- Cart price rules
SELECT rule_id, name, simple_action, discount_amount, coupon_type,
       use_auto_generation, uses_per_coupon, uses_per_customer, to_date
FROM salesrule WHERE LOWER(TRIM(name))='back2school25';

-- Customer group assignments
SELECT customer_group_id FROM salesrule_customer_group WHERE rule_id=<rule_id>;

-- Coupon codes
SELECT code FROM salesrule_coupon WHERE rule_id=<rule_id>;

-- Conditions (JSON/serialized blob)
SELECT conditions_serialized FROM salesrule WHERE rule_id=<rule_id>;
```

## Edge Cases

- The Magento admin has two separate steps: (1) save the rule, (2) generate codes from the Manage Coupon Codes tab. An agent that saves the rule but doesn't generate codes will score ~60 points (partial credit).
- The General customer group typically has `customer_group_id = 1` in standard Magento installs.
- The `coupon_type` field value for auto-generated coupons is `3` in Magento 2.
- The subtotal condition is stored as a JSON blob in `conditions_serialized`; the verifier looks for `base_subtotal` and value `75` in that field.
