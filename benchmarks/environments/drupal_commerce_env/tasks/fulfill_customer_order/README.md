# fulfill_customer_order

## Domain Context

Online merchants use Drupal Commerce to manage customer orders, apply promotional discounts, and configure billing/shipping details. This task simulates a common admin workflow: manually creating an order on behalf of a customer (e.g., from a phone call), applying a coupon, and placing it.

## Goal

Create and place a complete order for customer Jane Smith (username: `janesmith`, uid=3) containing two specific products with a coupon discount and a billing address.

**End state:**
- A new order exists for janesmith containing 1x Sony WH-1000XM5 ($348.00) and 1x Logitech MX Master 3S ($99.99)
- The WELCOME10 coupon code is applied (10% discount)
- Billing address is set to Portland, OR 97201
- The order is placed (state is NOT draft)

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Order created for correct customer | 15 | New order exists for uid=3 (janesmith) |
| 2 | Contains Sony WH-1000XM5 | 15 | Order includes variation_id=1 (SKU: SONY-WH1000XM5) |
| 3 | Contains Logitech MX Master 3S | 15 | Order includes variation_id=5 (SKU: LOGI-MXM3S) |
| 4 | WELCOME10 coupon applied | 20 | Coupon linked to order with promotion adjustment |
| 5 | Billing address correct | 15 | Portland, OR in billing profile |
| 6 | Order placed | 20 | Order state is not 'draft' |

**Pass threshold:** 70/100

## Verification Strategy

- **Baseline recording:** Initial order/item counts saved at setup; verifier checks for NEW orders
- **Wrong-target rejection:** If order belongs to wrong uid, score = 0 immediately
- **Gate:** If no order found for janesmith at all, score = 0

## Schema Reference

| Table | Key Fields |
|-------|-----------|
| `commerce_order` | order_id, uid, state, total_price__number, billing_profile__target_id |
| `commerce_order_item` | order_item_id, purchased_entity (variation_id), title, quantity, unit_price__number |
| `commerce_order__order_items` | entity_id (order_id), order_items_target_id (order_item_id) |
| `commerce_order__coupons` | entity_id (order_id), coupons_target_id |
| `commerce_order__adjustments` | entity_id, adjustments__type, adjustments__amount__number |
| `profile__address` | entity_id, address_locality, address_administrative_area |

## Edge Cases

- Agent might create order for wrong customer (wrong-target check catches this)
- Agent might add wrong products — each verified independently by variation_id
- Agent might apply coupon but not place the order — partial credit
- Coupon could be applied but no discount adjustment created if order total calc is skipped
