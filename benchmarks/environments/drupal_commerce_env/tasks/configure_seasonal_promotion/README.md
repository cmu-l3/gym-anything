# configure_seasonal_promotion

## Domain Context

Online merchants regularly configure promotional campaigns in their e-commerce platform — seasonal sales, coupon-driven discounts, minimum-order thresholds. This task requires creating a complete promotion with multiple interrelated settings across Drupal Commerce's promotion system.

## Goal

Create a fully configured seasonal promotion for a Spring Clearance sale with a specific percentage discount, coupon requirement, minimum order condition, and store assignment.

**End state:**
- A promotion named "Spring Clearance 30% Off" is active
- The offer is 30% off the order subtotal
- A coupon with code SPRING30 is linked to the promotion (usage limit: 50)
- The promotion requires a coupon to be applied
- A minimum order condition of $150 is configured
- The promotion is assigned to the Urban Electronics store

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Promotion active with correct name | 15 | Name contains "Spring Clearance" and "30", status=1 |
| 2 | 30% percentage offer | 20 | Offer type is percentage_off, value is 0.30 |
| 3 | SPRING30 coupon linked | 20 | Coupon exists with code SPRING30, linked to promotion |
| 4 | Min order $150 condition | 20 | Condition with $150 minimum order amount |
| 5 | Require coupon + usage limit 50 | 10 | require_coupon=1, coupon usage_limit=50 |
| 6 | Store assigned | 15 | Promotion linked to store_id=1 |

**Pass threshold:** 70/100

## Verification Strategy

- **Baseline recording:** Initial promotion and coupon counts saved; verifier checks for NEW promotions
- **Gate:** If no promotion with "Spring Clearance" in name is found, score = 0
- **Offer parsing:** The percentage value is stored in a serialized PHP blob (`offer__target_plugin_configuration`); export script uses Python regex to extract it

## Schema Reference

| Table | Key Fields |
|-------|-----------|
| `commerce_promotion_field_data` | promotion_id, name, display_name, offer__target_plugin_id, offer__target_plugin_configuration, status, require_coupon |
| `commerce_promotion_coupon` | id, promotion_id, code, usage_limit, status |
| `commerce_promotion__coupons` | entity_id (promotion_id), coupons_target_id (coupon_id) |
| `commerce_promotion__conditions` | entity_id, conditions__target_plugin_id, conditions__target_plugin_configuration |
| `commerce_promotion__stores` | entity_id (promotion_id), stores_target_id (store_id) |

## Edge Cases

- Agent might create coupon but not link it to the promotion — partial credit (10/20)
- Agent might set wrong percentage (e.g., 30 instead of 0.30) — partial credit for type
- Agent might set condition amount wrong — partial credit if condition exists at all
- Existing promotions (WELCOME10, SAVE25, Electronics 15%) must not be confused with the new one
