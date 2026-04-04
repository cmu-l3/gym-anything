# Store Configuration and Multi-Order Fulfillment

## Domain Context
Customer service representatives and order clerks routinely configure payment methods, set up shipping classifications, and process multiple orders in a single work session. This task simulates a realistic day-one setup for a fulfillment workflow: enabling a payment method, creating a shipping class for special-handling items, and then processing two distinct customer orders with different products, statuses, and notes.

## Occupation
Customer Service Representatives (imp=89), Order Clerks (imp=83)

## Goal
Prepare the store and process two customer orders:
- Enable and configure Cash on Delivery payment with a custom title and description
- Create an "Oversized Items" shipping class and assign it to 2 products
- Create Order A for Mike Wilson: 2 products, status=Completed, with a specific private note
- Create Order B for John Doe: 2 products, status=Processing, with a different private note

The end state: COD payment is enabled with custom text, a shipping class exists and is assigned to the correct products, and two orders exist with distinct customers, products, statuses, and notes.

## Difficulty
`very_hard` — Requires navigating 4+ distinct admin areas (Settings > Payments, Settings > Shipping > Shipping Classes, Products for shipping class assignment, Orders x2), creating 2 separate orders with different configurations, and correctly setting order notes and statuses. The agent must handle the COD payment gateway settings UI, shipping class creation/assignment, and the full order creation workflow twice with different parameters.

## Verification Strategy
Hybrid: Programmatic (70 pts) + VLM trajectory (30 pts)

### Programmatic Criteria (70 points)
| Criterion | Points | Source |
|-----------|--------|--------|
| COD enabled with correct title/desc | 10 | `wp_options.woocommerce_cod_settings` |
| Shipping class exists | 5 | `wp_terms` + taxonomy=product_shipping_class |
| Shipping class on 2 products | 10 (5 each) | `wp_term_relationships` |
| Order A products correct | 8 | `wp_woocommerce_order_items` |
| Order A customer = Mike Wilson | 3 | `wp_postmeta._customer_user` |
| Order A status = completed | 4 | `wp_posts.post_status` |
| Order A note correct | 5 | `wp_comments` (order_note) |
| Order B products correct | 8 | `wp_woocommerce_order_items` |
| Order B customer = John Doe | 3 | `wp_postmeta._customer_user` |
| Order B status = processing | 4 | `wp_posts.post_status` |
| Order B note correct | 5 | `wp_comments` (order_note) |
| >= 2 new orders created | 5 | Order count delta |

### VLM Criteria (30 points)
- Process verification (15 pts): multi-area workflow with settings + orders
- Final state (10 pts): success indicators visible
- Cross-validation (5 pts): DB + VLM agreement

### Pass Threshold
Score >= 45 AND at least one order found AND shipping class exists

### Do-Nothing Test
Setup script disables COD, removes shipping class and its product assignments. Score = 0 guaranteed.

## Schema Reference
- COD settings: `wp_options` key `woocommerce_cod_settings` (JSON: enabled, title, description)
- Shipping classes: `wp_terms` + `wp_term_taxonomy` (taxonomy='product_shipping_class')
- Product-class assignment: `wp_term_relationships`
- Orders: `wp_posts` (post_type='shop_order'), `wp_postmeta`, `wp_woocommerce_order_items`
- Order notes: `wp_comments` (comment_type='order_note')

## Order Details
### Order A (Mike Wilson)
- Wireless Bluetooth Headphones (WBH-001) x1
- USB-C Laptop Charger (USBC-065) x1
- Status: Completed
- Note: "Delivered via express courier"

### Order B (John Doe)
- Slim Fit Denim Jeans (SFDJ-BLU-32) x2
- Merino Wool Sweater (MWS-GRY-L) x1
- Status: Processing
- Note: "Customer requested gift wrapping"
