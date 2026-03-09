# Task: Set Up WooCommerce Online Store

## Domain Context
**Occupation:** E-Commerce Manager / Marketing Manager (SOC 11-2021.00)
**Rationale:** Marketing managers frequently set up and configure WooCommerce stores, creating product catalogs with proper categorization, pricing, and SKU management. This task simulates the initial store configuration workflow.

## Goal
Activate the WooCommerce plugin (pre-installed but inactive), configure store settings, create a product category, and add three products with exact pricing and SKU values.

## Expected End State
- WooCommerce plugin is active
- Store currency set to USD
- Product category "Artisan Coffee Blends" exists
- Three products published in that category:
  - "Ethiopian Yirgacheffe" — $18.99, SKU: ACB-ETH-001
  - "Colombian Supremo" — $15.49, SKU: ACB-COL-002
  - "Sumatra Mandheling" — $16.99, SKU: ACB-SUM-003

## Setup (setup_task.sh)
- Installs WooCommerce via wp-cli (download only, NOT activated)
- Records baseline: no products exist, WooCommerce inactive

## Verification Strategy
7 programmatic criteria (70 pts total):
1. WooCommerce plugin active (10 pts)
2. Product category "Artisan Coffee Blends" exists (10 pts)
3. "Ethiopian Yirgacheffe" — correct price + SKU + category (15 pts)
4. "Colombian Supremo" — correct price + SKU + category (15 pts)
5. "Sumatra Mandheling" — correct price + SKU + category (15 pts)
6. Store currency is USD (5 pts)

VLM checks (30 pts).

Pass threshold: score >= 70 AND WooCommerce active AND all 3 products found.

## Schema Reference
- Plugin status: `wp plugin is-active woocommerce`
- Products: `wp_posts WHERE post_type='product'`
- Prices: `wp_postmeta WHERE meta_key='_regular_price'`
- SKUs: `wp_postmeta WHERE meta_key='_sku'`
- Categories: `wp_term_taxonomy WHERE taxonomy='product_cat'`
- Currency: `wp_options WHERE option_name='woocommerce_currency'`

## Edge Cases
- WooCommerce setup wizard may appear on first visit — agent should dismiss or complete it
- Product prices must match exactly (string comparison: "18.99")
- SKUs are case-sensitive
- Products must be in 'publish' status (not draft)
