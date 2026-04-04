# Configure Seasonal Flash Sale

## Domain Context
Online merchants and e-commerce operations managers regularly set up promotional campaigns that span multiple store systems: product categorization, individual product pricing, and coupon configuration with complex restrictions. A "flash sale" is a realistic, high-stakes workflow because misconfigured coupons or wrong sale prices directly impact revenue.

## Occupation
Online Merchants (imp=92), Customer Service Representatives (imp=89)

## Goal
Set up a complete "Summer Flash Sale" promotion across the WooCommerce store, involving:
- A new product category for the sale
- Sale prices on 3 specific existing products
- A coupon with percentage discount, minimum spend, category restriction, usage limit, and expiry date

The end state: 3 products show sale prices on the storefront, all 3 belong to the new "Flash Sale" category, and a coupon "FLASH30" exists with all required restrictions correctly configured.

## Difficulty
`very_hard` — Requires navigating 3 distinct WooCommerce admin areas (Categories, Products, Coupons), editing 3 separate products, and configuring a coupon with 5+ distinct settings. No UI steps are spelled out.

## Verification Strategy
Hybrid: Programmatic (70 pts) + VLM trajectory (30 pts)

### Programmatic Criteria (70 points)
| Criterion | Points | Source |
|-----------|--------|--------|
| "Flash Sale" category exists | 10 | `wp_terms` + `wp_term_taxonomy` |
| 3 products in Flash Sale category | 15 (5 each) | `wp_term_relationships` |
| 3 sale prices correct | 15 (5 each) | `wp_postmeta._sale_price` |
| Coupon type=percent, amount=30 | 10 | `wp_postmeta.discount_type`, `coupon_amount` |
| Coupon min spend=$50 | 5 | `wp_postmeta.minimum_amount` |
| Coupon usage limit=100 | 5 | `wp_postmeta.usage_limit` |
| Coupon category restriction | 5 | `wp_postmeta.product_categories` |
| Coupon expiry=2026-12-31 | 5 | `wp_postmeta.date_expires` |

### VLM Criteria (30 points)
- Process verification (15 pts): trajectory shows multi-area navigation
- Final state (10 pts): success indicators visible
- Cross-validation (5 pts): DB + VLM agreement

### Pass Threshold
Score >= 55 AND category exists AND coupon found AND >= 2 products correctly configured

### Do-Nothing Test
Setup script clears all pre-existing sale prices, removes any existing "Flash Sale" category and FLASH30 coupon. Score = 0 guaranteed.

## Schema Reference
- Products: `wp_posts` (post_type='product') + `wp_postmeta` (_sku, _sale_price, _regular_price)
- Categories: `wp_terms` + `wp_term_taxonomy` (taxonomy='product_cat') + `wp_term_relationships`
- Coupons: `wp_posts` (post_type='shop_coupon') + `wp_postmeta` (discount_type, coupon_amount, minimum_amount, usage_limit, date_expires, product_categories)

## Target Products
- Wireless Bluetooth Headphones (WBH-001): sale $59.99
- Yoga Mat Premium (YMP-001): sale $29.99
- LED Desk Lamp (LED-DL-01): sale $34.99
