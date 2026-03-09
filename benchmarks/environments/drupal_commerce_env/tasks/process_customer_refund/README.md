# process_customer_refund

## Domain Context

Online merchants must handle order cancellations and issue store credit. This task combines order state management with promotion/coupon creation — a multi-step workflow touching two distinct Drupal Commerce subsystems (orders and promotions).

## Goal

Process a refund for customer John Doe (username: `johndoe`, uid=2) whose completed order of $1,298.00 (1x MacBook Air M2 + 1x Keychron Q1 Pro) needs to be canceled with store credit issued.

**End state:**
- johndoe's order (created by setup) is in "canceled" state
- A new promotion exists named "Store Credit - John Doe Refund" (or similar containing "Refund" / "Store Credit")
- The promotion is a fixed dollar amount off of $1,298.00
- A coupon with code REFUND-JOHNDOE is linked to the promotion with usage limit=1
- The promotion is active, requires a coupon, and is assigned to the store

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Correct customer identified | 10 | Order belongs to uid=2 (johndoe) |
| 2 | Order canceled | 25 | Order state changed to "canceled" |
| 3 | Refund promotion with $1,298 amount | 25 | Fixed-amount promotion with correct dollar value |
| 4 | REFUND-JOHNDOE coupon linked | 20 | Coupon code matches, linked to promotion, limit=1 |
| 5 | Promotion config correct | 20 | Active, requires coupon, store assigned (7+7+6 pts) |

**Pass threshold:** 70/100

## Verification Strategy

- **Baseline recording:** Initial promotion/coupon counts and order state saved; order ID recorded
- **Wrong-target rejection:** If order belongs to wrong uid, score = 0 immediately
- **Gate:** If neither order state changed nor refund promotion created, score = 0
- **Offer parsing:** Fixed-amount value extracted from serialized PHP blob using regex

## Schema Reference

| Table | Key Fields |
|-------|-----------|
| `commerce_order` | order_id, uid, state, total_price__number |
| `commerce_promotion_field_data` | promotion_id, name, offer__target_plugin_id, offer__target_plugin_configuration, status, require_coupon |
| `commerce_promotion_coupon` | id, code, usage_limit, status |
| `commerce_promotion__coupons` | entity_id, coupons_target_id |
| `commerce_promotion__stores` | entity_id, stores_target_id |

## Edge Cases

- Agent might cancel the wrong order — wrong-target check (uid mismatch = score 0)
- Agent might create promotion but forget to link coupon — partial credit
- Agent might use percentage instead of fixed amount — 5 pts partial credit
- Agent might set wrong refund amount — partial credit if amount > 0
- setup_task.sh creates the order via Drush PHP (it doesn't exist initially)
