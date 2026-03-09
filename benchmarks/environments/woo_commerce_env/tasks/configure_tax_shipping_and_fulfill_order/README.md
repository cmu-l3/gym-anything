# Configure Tax, Shipping, and Fulfill Order

## Domain Context
Order clerks and fulfillment specialists need to configure store-level settings (tax rates, shipping zones) before processing orders. This is a realistic onboarding workflow: a new store being prepared for US sales requires tax compliance, shipping logistics, and then processing the first real order. Each area (taxes, shipping, orders) lives in a different part of the admin.

## Occupation
Order Clerks (imp=83), Customer Service Representatives (imp=89)

## Goal
Configure the WooCommerce store for California sales and process the first order:
- Enable tax calculations and add a CA sales tax rate (8.25%)
- Create a California shipping zone with flat-rate shipping ($7.99)
- Create a manual order with specific products, assigned customer, billing state set to CA, a private order note, and status set to Processing

The end state: tax and shipping infrastructure is configured, and one order exists with correct products, customer, tax region, note, and status.

## Difficulty
`very_hard` — Requires navigating 4 distinct WooCommerce admin areas (Settings > General, Settings > Tax, Settings > Shipping, Orders), with each area having its own sub-UI. The agent must enable taxes, add a specific tax rate row, create a shipping zone with a method, and then create a full order.

## Verification Strategy
Hybrid: Programmatic (70 pts) + VLM trajectory (30 pts)

### Programmatic Criteria (70 points)
| Criterion | Points | Source |
|-----------|--------|--------|
| Taxes enabled | 5 | `wp_options.woocommerce_calc_taxes` |
| CA tax rate = 8.25% | 10 | `wp_woocommerce_tax_rates` |
| Shipping zone "California" exists | 5 | `wp_woocommerce_shipping_zones` |
| Flat rate $7.99 configured | 5 | `wp_woocommerce_shipping_zone_methods` + `wp_options` |
| Order products correct | 15 | `wp_woocommerce_order_items` + itemmeta |
| Order customer = Jane Smith | 5 | `wp_postmeta._customer_user` |
| Order billing state = CA | 5 | `wp_postmeta._billing_state` |
| Order status = processing | 5 | `wp_posts.post_status` |
| Order note correct | 10 | `wp_comments` (comment_type='order_note') |
| Order count increased | 5 | Delta of `wp_posts` shop_order count |

### VLM Criteria (30 points)
- Process verification (15 pts): multi-area progression (settings + orders)
- Final state (10 pts): success indicators visible
- Cross-validation (5 pts): DB + VLM agreement

### Pass Threshold
Score >= 50 AND tax rate exists AND order found AND order status = processing

### Do-Nothing Test
Setup script removes CA tax rates, removes California shipping zone, disables taxes. Score = 0 guaranteed.

## Schema Reference
- Tax rates: `wp_woocommerce_tax_rates` (tax_rate, tax_rate_state, tax_rate_name, tax_rate_country)
- Shipping zones: `wp_woocommerce_shipping_zones`, `wp_woocommerce_shipping_zone_methods`, `wp_woocommerce_shipping_zone_locations`
- Flat rate settings: `wp_options` (woocommerce_flat_rate_{instance_id}_settings, serialized PHP)
- Orders: `wp_posts` (post_type='shop_order'), `wp_postmeta`, `wp_woocommerce_order_items`
- Order notes: `wp_comments` (comment_type='order_note', comment_post_ID=order_id)
