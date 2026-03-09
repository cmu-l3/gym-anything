# Product Catalog Reorganization

## Domain Context
Online merchants periodically reorganize their product catalogs as inventory grows. This involves creating category hierarchies, tagging products for discoverability, featuring top products, and updating descriptions. This is a content management workflow that touches many products and multiple taxonomy systems simultaneously.

## Occupation
Online Merchants (imp=92), Customer Service Representatives (imp=89)

## Goal
Reorganize the product catalog:
- Create a category hierarchy: "Outdoor & Recreation" parent with "Camping Gear" and "Fitness Equipment" subcategories
- Assign 3 products to the appropriate new subcategories
- Create 3 product tags and assign them to 6 products across the catalog
- Mark 2 products as Featured
- Update the short description of one product

The end state: a well-organized catalog with hierarchical categories, tagged products, featured products, and updated descriptions.

## Difficulty
`very_hard` — Requires working across product categories (with parent/child hierarchy), product tags, individual product editing (for category, tags, featured status, and description), touching 8 different products and 3 different taxonomy systems. Agent must discover how to set parent categories, create tags, and toggle featured status.

## Verification Strategy
Hybrid: Programmatic (70 pts) + VLM trajectory (30 pts)

### Programmatic Criteria (70 points)
| Criterion | Points | Source |
|-----------|--------|--------|
| Parent category exists | 8 | `wp_terms` + `wp_term_taxonomy` |
| Camping Gear subcategory (correct parent) | 8 | `wp_term_taxonomy.parent` |
| Fitness Equipment subcategory (correct parent) | 8 | `wp_term_taxonomy.parent` |
| 3 products in correct subcategories | 12 (4 each) | `wp_term_relationships` |
| 3 tags exist | 6 (2 each) | `wp_terms` + taxonomy=product_tag |
| 6 tag assignments correct | 12 (2 each) | `wp_term_relationships` |
| 2 products featured | 8 (4 each) | `wp_term_relationships` + product_visibility |
| Short description correct | 8 | `wp_posts.post_excerpt` |

### VLM Criteria (30 points)
- Process verification (15 pts): category management + multi-product editing
- Final state (10 pts): success indicators visible
- Cross-validation (5 pts): DB + VLM agreement

### Pass Threshold
Score >= 50 AND parent category exists AND >= 1 subcategory AND >= 2 products correctly categorized

### Do-Nothing Test
Setup script removes all target categories, tags, featured status, and clears the short description. Score = 0 guaranteed.

## Schema Reference
- Categories: `wp_terms` + `wp_term_taxonomy` (taxonomy='product_cat', parent=term_id)
- Tags: `wp_terms` + `wp_term_taxonomy` (taxonomy='product_tag')
- Featured: `wp_term_relationships` linking product to 'featured' term in 'product_visibility' taxonomy
- Short description: `wp_posts.post_excerpt`

## Product Assignments
- Camping Gear: Portable Camping Hammock (PCH-DUO)
- Fitness Equipment: Yoga Mat Premium (YMP-001), Resistance Band Set (RBS-005)

## Tag Assignments
- bestseller: WBH-001, YMP-001
- eco-friendly: OCT-BLK-M, BCB-SET2
- gift-idea: LED-DL-01, CPP-SET3
