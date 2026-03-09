# Configurable Product Task

## Overview

This task tests a Magento catalog manager's ability to create a configurable product — Magento's most complex product type. Configurable products are used for items sold in multiple variants (size, color, material) and require creating both a parent product and child simple products, then linking them through a shared attribute.

**Domain context**: Outdoor gear, apparel, and sporting goods retailers universally use configurable products. A backpack sold in multiple colors requires this exact structure: a parent configurable product that the customer sees, and invisible child products that track per-variant inventory and pricing. This workflow involves multiple screens and is a core catalog management skill.

## Goal

Create a configurable product:

**Parent product:**
- Name: `Trailmaster Summit Backpack 45L`
- SKU: `TMS-BP-45L`
- Attribute Set: Default, Type: Configurable, Configurable by: Color
- Price: $149.99, Weight: 2.5
- Category: Sports
- Status: Enabled, Visibility: Catalog, Search

**Two child simple products:**
1. Color: Black, SKU: `TMS-BP-45L-BLK`, Price: $149.99, Qty: 30, Enabled, In Stock
2. Color: Green, SKU: `TMS-BP-45L-GRN`, Price: $159.99, Qty: 25, Enabled, In Stock

Both children must be linked to the parent through the Color attribute.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Parent configurable product `TMS-BP-45L` exists with type=configurable | 20 |
| Parent name matches `Trailmaster Summit Backpack 45L` | 10 |
| Black child (`TMS-BP-45L-BLK`) exists and is linked to parent | 20 |
| Green child (`TMS-BP-45L-GRN`) exists and is linked to parent | 20 |
| Parent is assigned to Sports category | 15 |
| Both children are Enabled and In Stock | 15 |

**Pass threshold: 60 points**

## Verification Strategy

- `setup_task.sh` records initial product count and existing configurable count; records the Color attribute ID
- `export_result.sh` queries `catalog_product_entity` by SKU for the parent and both children, verifies `type_id='configurable'` on parent, checks `catalog_product_super_link` for parent-child links, verifies category assignment via `catalog_category_product`, checks stock status and enabled status via EAV attributes
- `verifier.py` gates on parent existence (type=configurable), then scores each subtask independently

## Database Schema Reference

```sql
-- Find parent by SKU
SELECT entity_id, sku, type_id FROM catalog_product_entity
WHERE LOWER(TRIM(sku))='tms-bp-45l';

-- Configurable product children (super links)
SELECT product_id, parent_id FROM catalog_product_super_link
WHERE parent_id=<parent_entity_id>;

-- Check child by SKU
SELECT entity_id, sku, type_id FROM catalog_product_entity
WHERE LOWER(TRIM(sku)) IN ('tms-bp-45l-blk', 'tms-bp-45l-grn');

-- Product status (attribute_id for 'status' in entity_type_id=4)
SELECT value FROM catalog_product_entity_int
WHERE entity_id=<entity_id>
AND attribute_id=(SELECT attribute_id FROM eav_attribute
                  WHERE attribute_code='status' AND entity_type_id=4);

-- Category assignment
SELECT category_id FROM catalog_category_product WHERE product_id=<entity_id>;

-- Stock status
SELECT qty, is_in_stock FROM cataloginventory_stock_item WHERE product_id=<entity_id>;
```

## Edge Cases

- Magento's Catalog > Products > Add Product workflow defaults to Simple product. The agent must select "Configurable Product" from the product type dropdown before proceeding.
- The Color attribute must exist in Magento's EAV system before it can be used as a configurable attribute. Standard Magento installations include Color by default.
- Creating the child variants requires either using "Create New Configuration" (auto-creates simple products) or linking pre-existing simple products. Most agents will use "Create New Configuration."
- A Sports category must exist; if it does not, the agent must create it first (adds complexity).
