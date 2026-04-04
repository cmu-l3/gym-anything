# Setup Variable Product with Inventory

## Domain Context
Craft artists and online merchants frequently sell products with multiple options (size, color, material). WooCommerce's variable product system requires navigating between Attributes, Variations, and Linked Products tabs — each with distinct UI patterns. This is one of the most complex product creation workflows in WooCommerce, as each variation needs individual price and stock configuration.

## Occupation
Online Merchants (imp=92), Craft Artists (imp=52)

## Goal
Create a variable product "Premium Merino Wool Scarf" with:
- Two variation attributes: Color (Burgundy, Charcoal, Navy) and Size (Standard, Oversized)
- 6 variations with per-size pricing and per-combination stock quantities
- Cross-sell linkage to an existing product
- Assigned to the Clothing category and published

The end state: a published variable product with 6 purchasable variations, each with correct individual pricing and managed stock.

## Difficulty
`very_hard` — Requires using at least 4 distinct product data tabs (General, Attributes, Variations, Linked Products), generating variations, and configuring 6 individual variations with different prices and stock values. The Variations tab UI is non-trivial to navigate.

## Verification Strategy
Hybrid: Programmatic (70 pts) + VLM trajectory (30 pts)

### Programmatic Criteria (70 points)
| Criterion | Points | Source |
|-----------|--------|--------|
| Product exists with correct name/SKU | 10 | `wp_posts`, `wp_postmeta._sku` |
| Product type = variable | 5 | `wp_term_relationships` + product_type taxonomy |
| Category = Clothing | 5 | `wp_term_relationships` + product_cat taxonomy |
| 6 variations exist | 10 | `wp_posts` (post_type='product_variation') |
| Variation prices correct by size | 15 | `wp_postmeta._regular_price` per variation |
| Variation stock quantities correct | 15 | `wp_postmeta._stock` per variation |
| Cross-sell = Merino Wool Sweater | 5 | `wp_postmeta._crosssell_ids` |
| Product published | 5 | `wp_posts.post_status` |

### VLM Criteria (30 points)
- Process verification (15 pts): variable product workflow with multi-tab navigation
- Final state (10 pts): product page with success indicators
- Cross-validation (5 pts): DB + VLM agreement

### Pass Threshold
Score >= 50 AND product found AND product is variable type AND >= 4 variations exist

### Do-Nothing Test
Setup script deletes any pre-existing product with SKU PMWS-001 and all its variations. Score = 0 guaranteed.

## Schema Reference
- Variable product: `wp_posts` (post_type='product') with 'variable' in product_type taxonomy
- Variations: `wp_posts` (post_type='product_variation', post_parent=product_ID)
- Variation attributes: `wp_postmeta` (attribute_pa_color, attribute_pa_size or attribute_color, attribute_size)
- Stock: `wp_postmeta` (_manage_stock='yes', _stock=N)
- Cross-sells: `wp_postmeta` (_crosssell_ids, serialized PHP array)

## Stock Quantities
| Color | Standard | Oversized |
|-------|----------|-----------|
| Burgundy | 25 | 15 |
| Charcoal | 30 | 20 |
| Navy | 35 | 10 |
